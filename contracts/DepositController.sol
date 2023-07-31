// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {IWETH9} from "./external/weth/IWETH9.sol";
import {IERC721Permit} from "./interfaces/IERC721Permit.sol";
import {IDepositController} from "./interfaces/IDepositController.sol";
import {IBondPositionManager} from "./interfaces/IBondPositionManager.sol";
import {BondPosition} from "./libraries/BondPosition.sol";
import {CouponKey, CouponKeyLibrary} from "./libraries/CouponKey.sol";
import {Coupon} from "./libraries/Coupon.sol";
import {PermitParams} from "./libraries/PermitParams.sol";
import {Currency, CurrencyLibrary} from "./libraries/Currency.sol";
import {Controller} from "./libraries/Controller.sol";

contract DepositController is IDepositController, Controller {
    using CouponKeyLibrary for CouponKey;
    using CurrencyLibrary for Currency;

    IBondPositionManager private immutable _bondManager;

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
        uint16 lockEpochs,
        uint256 minInterestEarned,
        PermitParams calldata tokenPermitParams
    ) external payable returns (uint256 positionId) {
        _permitERC20(currency, amount, tokenPermitParams);
        bool isNative = currency.isNative();
        bytes memory data = abi.encode(msg.sender, isNative, minInterestEarned, 0);
        positionId = _bondManager.mint(isNative ? address(_weth) : Currency.unwrap(currency), amount, lockEpochs, address(this), data);
        _bondManager.transferFrom(address(this), msg.sender, positionId);
        _flush(currency, msg.sender);
    }

    function withdraw(
        uint256 positionId,
        uint256 withdrawAmount,
        uint256 maxInterestPaid,
        PermitParams calldata positionPermitParams
    ) external {
        _permitERC721(IERC721Permit(_bondManager), positionId, positionPermitParams);
        BondPosition memory position = _bondManager.getPosition(positionId);
        Currency currency = Currency.wrap(position.asset);
        bytes memory data = abi.encode(msg.sender, currency.isNative(), 0, maxInterestPaid);
        _bondManager.adjustPosition(positionId, position.amount - withdrawAmount, position.expiredWith, data);
        _flush(currency, msg.sender);
    }

    function collect(uint256 positionId, PermitParams calldata positionPermitParams) external {
        _permitERC721(IERC721Permit(_bondManager), positionId, positionPermitParams);
        Currency currency = Currency.wrap(_bondManager.getPosition(positionId).asset);
        _bondManager.burnExpiredPosition(positionId);
        _flush(currency, msg.sender);
    }

    function bondPositionAdjustCallback(
        uint256,
        BondPosition memory oldPosition,
        BondPosition memory newPosition,
        Coupon[] memory couponsMinted,
        Coupon[] memory couponsToBurn,
        bytes calldata data
    ) external {
        require(msg.sender == address(_bondManager));
        (address user, bool useNative, uint256 sellThreshold, uint256 buyThreshold) =
            abi.decode(data, (address, bool, uint256, uint256));
        Currency currency = Currency.wrap(newPosition.asset);
        uint256 earnedAmount;

        if (couponsMinted.length > 0) {
            earnedAmount = _sellCoupons(couponsMinted, sellThreshold, currency, user);
        }

        if (oldPosition.amount < newPosition.amount) {
            uint256 amountNeeded = newPosition.amount - oldPosition.amount - earnedAmount;
            if (useNative) {
                IWETH9(currency.unwrap()).deposit{value: amountNeeded}();
            } else {
                currency.transferFrom(user, address(this), amountNeeded);
            }
        }

        if (couponsToBurn.length > 0) {
            _buyCoupons(couponsToBurn, buyThreshold, user, currency, useNative);
        }
    }

    function getCouponMarket(CouponKey memory couponKey) external view returns (address) {
        return _couponMarkets[couponKey.toId()];
    }

    function setCouponMarket(CouponKey memory couponKey, address cloberMarket) external onlyOwner {
        Currency.wrap(couponKey.asset).approve(address(_bondManager), type(uint256).max);
        return _setCouponMarket(couponKey, cloberMarket);
    }
}
