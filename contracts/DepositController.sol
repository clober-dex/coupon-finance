// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IWETH9} from "./external/weth/IWETH9.sol";
import {IERC721Permit} from "./interfaces/IERC721Permit.sol";
import {IDepositController} from "./interfaces/IDepositController.sol";
import {IBondPositionManager} from "./interfaces/IBondPositionManager.sol";
import {BondPosition, BondPositionLibrary} from "./libraries/BondPosition.sol";
import {Epoch, EpochLibrary} from "./libraries/Epoch.sol";
import {CouponKey, CouponKeyLibrary} from "./libraries/CouponKey.sol";
import {Coupon, CouponLibrary} from "./libraries/Coupon.sol";
import {PermitParams} from "./libraries/PermitParams.sol";
import {Controller} from "./libraries/Controller.sol";
import {Wrapped1155MetadataBuilder} from "./libraries/Wrapped1155MetadataBuilder.sol";

contract DepositController is IDepositController, Controller {
    using SafeERC20 for IERC20;
    using BondPositionLibrary for BondPosition;
    using EpochLibrary for Epoch;
    using CouponKeyLibrary for CouponKey;
    using CouponLibrary for Coupon;

    bytes private constant _EMPTY_BYTES = "E";

    IBondPositionManager private immutable _bondManager;

    enum CallType {
        DEPOSIT,
        WITHDRAW
    }

    bytes private _bondManagerData;

    constructor(
        address assetPool,
        address wrapped1155Factory,
        address cloberMarketFactory,
        address couponManager,
        address weth,
        address bondManager
    ) Controller(assetPool, wrapped1155Factory, cloberMarketFactory, couponManager, weth) {
        _bondManager = IBondPositionManager(bondManager);
        _bondManagerData = _EMPTY_BYTES;
    }

    function deposit(
        address token,
        uint256 amount,
        uint8 lockEpochs,
        uint256 minInterestEarned,
        PermitParams calldata tokenPermitParams
    ) external payable nonReentrant wrapETH {
        _permitERC20(token, amount, tokenPermitParams);
        BondPosition memory emptyPosition = BondPositionLibrary.empty(token);
        BondPosition memory newPosition =
            BondPositionLibrary.from(token, EpochLibrary.current().add(lockEpochs - 1), amount);
        (Coupon[] memory mintCoupons,) = emptyPosition.calculateCouponRequirement(newPosition);

        _bondManagerData = abi.encode(CallType.DEPOSIT, abi.encode(msg.sender, lockEpochs, amount, minInterestEarned));
        _execute(token, new Coupon[](0), mintCoupons, 0, 0);
        _bondManagerData = _EMPTY_BYTES;

        _flush(token, msg.sender);
    }

    function _callManager(address token, uint256 amountToPay, uint256 earnedAmount) internal override {
        (CallType callType, bytes memory data) = abi.decode(_bondManagerData, (CallType, bytes));
        if (callType == CallType.DEPOSIT) {
            (address user, uint8 lockEpochs, uint256 amount, uint256 minInterestEarned) =
                abi.decode(data, (address, uint8, uint256, uint256));
            if (minInterestEarned > earnedAmount) {
                revert ControllerSlippage();
            }
            uint256 positionId = _bondManager.mint(token, amount, lockEpochs, address(this), abi.encode(user));
            _bondManager.transferFrom(address(this), user, positionId);
        } else if (callType == CallType.WITHDRAW) {
            (Epoch expiredWith, address user, uint256 amount, uint256 positionId, uint256 maxInterestPaid) =
                abi.decode(data, (Epoch, address, uint256, uint256, uint256));
            if (maxInterestPaid < amountToPay) {
                revert ControllerSlippage();
            }
            _bondManager.adjustPosition(positionId, amount, expiredWith, abi.encode(user));
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
        if (msg.sender != address(_bondManager)) revert InvalidAccess();
        (address user) = abi.decode(data, (address));

        if (couponsToBurn.length > 0) _unwrapCoupons(couponsToBurn);

        if (oldPosition.amount < newPosition.amount) {
            _ensureBalance(newPosition.asset, user, newPosition.amount - oldPosition.amount);
        }

        if (couponsMinted.length > 0) _wrapCoupons(couponsMinted);
    }

    function withdraw(
        uint256 positionId,
        uint256 withdrawAmount,
        uint256 maxInterestPaid,
        PermitParams calldata positionPermitParams
    ) external nonReentrant {
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

        _bondManagerData = abi.encode(
            CallType.WITHDRAW, abi.encode(newPosition.expiredWith, msg.sender, amount, positionId, maxInterestPaid)
        );
        _execute(oldPosition.asset, burnCoupons, new Coupon[](0), 0, 0);
        _bondManagerData = _EMPTY_BYTES;

        _flush(oldPosition.asset, msg.sender);
    }

    function collect(uint256 positionId, PermitParams calldata positionPermitParams) external nonReentrant {
        _permitERC721(IERC721Permit(_bondManager), positionId, positionPermitParams);
        _bondManager.burnExpiredPosition(positionId);
        _flush(_bondManager.getPosition(positionId).asset, msg.sender);
    }

    function setCouponMarket(CouponKey memory couponKey, address cloberMarket) public override onlyOwner {
        IERC20(couponKey.asset).approve(address(_bondManager), type(uint256).max);
        super.setCouponMarket(couponKey, cloberMarket);
    }
}
