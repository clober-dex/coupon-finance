// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IDepositController} from "./interfaces/IDepositController.sol";
import {IBondPositionManager} from "./interfaces/IBondPositionManager.sol";
import {IPositionLocker} from "./interfaces/IPositionLocker.sol";
import {BondPosition} from "./libraries/BondPosition.sol";
import {Epoch, EpochLibrary} from "./libraries/Epoch.sol";
import {CouponKey} from "./libraries/CouponKey.sol";
import {Coupon} from "./libraries/Coupon.sol";
import {Controller} from "./libraries/Controller.sol";

contract DepositController is IDepositController, Controller, IPositionLocker {
    using EpochLibrary for Epoch;

    IBondPositionManager private immutable _bondManager;

    modifier onlyPositionOwner(uint256 positionId) {
        if (_bondManager.ownerOf(positionId) != msg.sender) revert InvalidAccess();
        _;
    }

    constructor(
        address wrapped1155Factory,
        address cloberMarketFactory,
        address couponManager,
        address weth,
        address bondManager
    ) Controller(wrapped1155Factory, cloberMarketFactory, couponManager, weth) {
        _bondManager = IBondPositionManager(bondManager);
    }

    function positionLockAcquired(bytes memory data) external returns (bytes memory result) {
        if (msg.sender != address(_bondManager)) revert InvalidAccess();

        uint256 positionId;
        address user;
        (positionId, user, data) = abi.decode(data, (uint256, address, bytes));
        if (positionId == 0) {
            address asset;
            (asset, data) = abi.decode(data, (address, bytes));
            positionId = _bondManager.mint(asset);
            result = abi.encode(positionId);
        }
        BondPosition memory position = _bondManager.getPosition(positionId);

        uint256 maxPayInterest;
        uint256 minEarnInterest;
        (position.amount, position.expiredWith, maxPayInterest, minEarnInterest) =
            abi.decode(data, (uint256, Epoch, uint256, uint256));
        (Coupon[] memory couponsToMint, Coupon[] memory couponsToBurn, int256 amountDelta) =
            _bondManager.adjustPosition(positionId, position.amount, position.expiredWith);
        if (amountDelta < 0) _bondManager.withdrawToken(position.asset, address(this), uint256(-amountDelta));
        if (couponsToMint.length > 0) {
            _bondManager.mintCoupons(couponsToMint, address(this), new bytes(0));
            _wrapCoupons(couponsToMint);
        }

        _executeCouponTrade(
            user,
            position.asset,
            couponsToBurn,
            couponsToMint,
            amountDelta > 0 ? uint256(amountDelta) : 0,
            maxPayInterest,
            minEarnInterest
        );

        if (amountDelta > 0) _bondManager.depositToken(position.asset, uint256(amountDelta));
        if (couponsToBurn.length > 0) {
            _unwrapCoupons(couponsToBurn);
            _bondManager.burnCoupons(couponsToBurn);
        }

        _bondManager.settlePosition(positionId);
    }

    function deposit(
        address asset,
        uint256 amount,
        uint8 lockEpochs,
        uint256 minEarnInterest,
        ERC20PermitParams calldata tokenPermitParams
    ) external payable nonReentrant wrapETH {
        _permitERC20(asset, tokenPermitParams);

        bytes memory lockData = abi.encode(amount, EpochLibrary.current().add(lockEpochs - 1), 0, minEarnInterest);
        uint256 id = abi.decode(_bondManager.lock(abi.encode(0, msg.sender, abi.encode(asset, lockData))), (uint256));

        _burnAllSubstitute(asset, msg.sender);
        _bondManager.transferFrom(address(this), msg.sender, id);
    }

    function withdraw(
        uint256 positionId,
        uint256 withdrawAmount,
        uint256 maxPayInterest,
        ERC721PermitParams calldata positionPermitParams
    ) external nonReentrant onlyPositionOwner(positionId) {
        _permitERC721(_bondManager, positionId, positionPermitParams);
        BondPosition memory position = _bondManager.getPosition(positionId);

        bytes memory lockData = abi.encode(position.amount - withdrawAmount, position.expiredWith, maxPayInterest, 0);
        _bondManager.lock(abi.encode(positionId, msg.sender, lockData));

        _burnAllSubstitute(position.asset, msg.sender);
    }

    function collect(uint256 positionId, ERC721PermitParams calldata positionPermitParams)
        external
        nonReentrant
        onlyPositionOwner(positionId)
    {
        _permitERC721(_bondManager, positionId, positionPermitParams);
        BondPosition memory position = _bondManager.getPosition(positionId);
        _bondManager.lock(abi.encode(positionId, msg.sender, abi.encode(0, position.expiredWith, 0, 0)));
        _burnAllSubstitute(position.asset, msg.sender);
    }

    function setCouponMarket(CouponKey memory couponKey, address cloberMarket) public override onlyOwner {
        IERC20(couponKey.asset).approve(address(_bondManager), type(uint256).max);
        super.setCouponMarket(couponKey, cloberMarket);
    }
}
