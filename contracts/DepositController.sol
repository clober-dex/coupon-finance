// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {IWETH9} from "./external/weth/IWETH9.sol";
import {IERC721Permit} from "./interfaces/IERC721Permit.sol";
import {IDepositController} from "./interfaces/IDepositController.sol";
import {IBondPositionManager} from "./interfaces/IBondPositionManager.sol";
import {BondPosition, BondPositionLibrary} from "./libraries/BondPosition.sol";
import {Epoch, EpochLibrary} from "./libraries/Epoch.sol";
import {CouponKey, CouponKeyLibrary} from "./libraries/CouponKey.sol";
import {Coupon, CouponLibrary} from "./libraries/Coupon.sol";
import {PermitParams} from "./libraries/PermitParams.sol";
import {Currency, CurrencyLibrary} from "./libraries/Currency.sol";
import {Controller} from "./libraries/Controller.sol";
import {Wrapped1155MetadataBuilder} from "./libraries/Wrapped1155MetadataBuilder.sol";

contract DepositController is IDepositController, Controller {
    using BondPositionLibrary for BondPosition;
    using EpochLibrary for Epoch;
    using CouponKeyLibrary for CouponKey;
    using CouponLibrary for Coupon;
    using CurrencyLibrary for Currency;

    IBondPositionManager private immutable _bondManager;

    enum CallType {
        DEPOSIT,
        WITHDRAW
    }

    bytes private _bondManagerData;

    constructor(
        address wrapped1155Factory,
        address cloberMarketFactory,
        address couponManager,
        address weth,
        address bondManager
    ) Controller(wrapped1155Factory, cloberMarketFactory, couponManager, weth) {
        _bondManager = IBondPositionManager(bondManager);
    }

    function deposit(
        Currency currency,
        uint256 amount,
        uint8 lockEpochs,
        uint256 minInterestEarned,
        PermitParams calldata tokenPermitParams
    ) external payable nonReentrant {
        _permitERC20(currency, amount, tokenPermitParams);
        if (msg.value > 0) {
            _weth.deposit{value: msg.value}();
        }
        BondPosition memory emptyPosition = BondPositionLibrary.empty(Currency.unwrap(currency));
        BondPosition memory newPosition =
            BondPositionLibrary.from(Currency.unwrap(currency), EpochLibrary.current().add(lockEpochs - 1), amount);
        (Coupon[] memory mintCoupons,) = emptyPosition.calculateCouponRequirement(newPosition);

        _bondManagerData = abi.encode(CallType.DEPOSIT, abi.encode(msg.sender, lockEpochs, amount, minInterestEarned));
        _sellCoupons(currency, mintCoupons, 0, 0);

        _flush(currency, msg.sender);
    }

    function _callManager(Currency currency, uint256 amountToPay, uint256 earnedAmount) internal override {
        (CallType callType, bytes memory data) = abi.decode(_bondManagerData, (CallType, bytes));
        if (callType == CallType.DEPOSIT) {
            (address user, uint8 lockEpochs, uint256 amount, uint256 minInterestEarned) =
                abi.decode(data, (address, uint8, uint256, uint256));
            if (minInterestEarned > earnedAmount) {
                revert ControllerSlippage();
            }
            uint256 positionId = _bondManager.mint(
                Currency.unwrap(currency), amount, lockEpochs, address(this), abi.encode(user, earnedAmount)
            );
            _bondManager.transferFrom(address(this), user, positionId);
        } else if (callType == CallType.WITHDRAW) {
            (Epoch expiredWith, address user, uint256 amount, uint256 positionId, uint256 maxInterestPaid) =
                abi.decode(data, (Epoch, address, uint256, uint256, uint256));
            if (maxInterestPaid < amountToPay) {
                revert ControllerSlippage();
            }
            _bondManager.adjustPosition(positionId, amount, expiredWith, abi.encode(user, earnedAmount));
        } else {
            revert("invalid call type");
        }
    }

    function bondPositionAdjustCallback(
        uint256,
        BondPosition memory oldPosition,
        BondPosition memory newPosition,
        Coupon[] memory couponsMinted,
        Coupon[] memory couponsToBurn,
        bytes calldata data
    ) external {
        if (msg.sender != address(_bondManager)) {
            revert Access();
        }
        (address user, uint256 earnedAmount) = abi.decode(data, (address, uint256));
        Currency currency = Currency.wrap(newPosition.asset);

        if (couponsToBurn.length > 0) {
            uint256[] memory tokenIds = new uint256[](couponsToBurn.length);
            uint256[] memory amounts = new uint256[](couponsToBurn.length);
            for (uint256 i = 0; i < couponsToBurn.length; i++) {
                tokenIds[i] = couponsToBurn[i].id();
                amounts[i] = couponsToBurn[i].amount;
            }
            _wrapped1155Factory.batchUnwrap(
                address(_couponManager),
                tokenIds,
                amounts,
                address(this),
                Wrapped1155MetadataBuilder.buildWrapped1155BatchMetadata(couponsToBurn)
            );
        }

        if (oldPosition.amount < newPosition.amount) {
            uint256 thisBalance = currency.balanceOfSelf();
            uint256 amountNeeded = newPosition.amount - oldPosition.amount;
            if (amountNeeded > earnedAmount + thisBalance) {
                currency.transferFrom(user, address(this), amountNeeded - earnedAmount - thisBalance);
            }
        }

        if (couponsMinted.length > 0) {
            // wrap 1155 to 20
            _couponManager.safeBatchTransferFrom(
                address(this),
                address(_wrapped1155Factory),
                couponsMinted,
                Wrapped1155MetadataBuilder.buildWrapped1155BatchMetadata(couponsMinted)
            );
        }
    }

    function withdraw(
        uint256 positionId,
        uint256 withdrawAmount,
        uint256 maxInterestPaid,
        PermitParams calldata positionPermitParams
    ) external {
        _permitERC721(IERC721Permit(_bondManager), positionId, positionPermitParams);
        BondPosition memory oldPosition = _bondManager.getPosition(positionId);
        uint256 amount = oldPosition.amount - withdrawAmount;
        BondPosition memory newPosition = BondPosition({
            asset: oldPosition.asset,
            nonce: oldPosition.nonce,
            expiredWith: amount == 0 ? EpochLibrary.current().sub(1) : oldPosition.expiredWith,
            amount: amount
        });
        (, Coupon[] memory burnCoupons) = oldPosition.calculateCouponRequirement(newPosition);

        Currency currency = Currency.wrap(oldPosition.asset);
        _bondManagerData = abi.encode(
            CallType.WITHDRAW, abi.encode(newPosition.expiredWith, msg.sender, amount, positionId, maxInterestPaid)
        );
        _buyCoupons(currency, burnCoupons, 0, 0);

        _flush(currency, msg.sender);
    }

    function collect(uint256 positionId, PermitParams calldata positionPermitParams) external {
        _permitERC721(IERC721Permit(_bondManager), positionId, positionPermitParams);
        Currency currency = Currency.wrap(_bondManager.getPosition(positionId).asset);
        _bondManager.burnExpiredPosition(positionId);
        _flush(currency, msg.sender);
    }

    function setCouponMarket(CouponKey memory couponKey, address cloberMarket) public override onlyOwner {
        Currency.wrap(couponKey.asset).approve(address(_bondManager), type(uint256).max);
        super.setCouponMarket(couponKey, cloberMarket);
    }
}
