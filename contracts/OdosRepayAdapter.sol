// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IWETH9} from "./external/weth/IWETH9.sol";
import {IERC721Permit} from "./interfaces/IERC721Permit.sol";
import {ISubstitute} from "./interfaces/ISubstitute.sol";
import {ILoanPositionManager} from "./interfaces/ILoanPositionManager.sol";
import {LoanPosition, LoanPositionLibrary} from "./libraries/LoanPosition.sol";
import {CouponKey, CouponKeyLibrary} from "./libraries/CouponKey.sol";
import {Coupon} from "./libraries/Coupon.sol";
import {Epoch, EpochLibrary} from "./libraries/Epoch.sol";
import {Controller} from "./libraries/Controller.sol";
import {IPositionLocker} from "./interfaces/IPositionLocker.sol";
import {IRepayAdapter} from "./interfaces/IRepayAdapter.sol";

contract OdosRepayAdapter is IRepayAdapter, Controller, IPositionLocker {
    using SafeERC20 for IERC20;
    using LoanPositionLibrary for LoanPosition;
    using CouponKeyLibrary for CouponKey;
    using EpochLibrary for Epoch;

    ILoanPositionManager private immutable _loanManager;
    address private immutable _odosRouter;

    modifier onlyPositionOwner(uint256 positionId) {
        if (_loanManager.ownerOf(positionId) != msg.sender) revert InvalidAccess();
        _;
    }

    constructor(
        address wrapped1155Factory,
        address cloberMarketFactory,
        address couponManager,
        address weth,
        address loanManager,
        address odosRouter
    ) Controller(wrapped1155Factory, cloberMarketFactory, couponManager, weth) {
        _loanManager = ILoanPositionManager(loanManager);
        _odosRouter = odosRouter;
    }

    function positionLockAcquired(bytes memory data) external returns (bytes memory result) {
        if (msg.sender != address(_loanManager)) revert InvalidAccess();

        (uint256 positionId, address user, uint256 sellCollateralAmount, uint256 minRepayAmount, bytes memory swapData)
        = abi.decode(data, (uint256, address, uint256, uint256, bytes));
        LoanPosition memory position = _loanManager.getPosition(positionId);
        uint256 maxDebtAmount = position.debtAmount - minRepayAmount;

        _loanManager.withdrawToken(position.collateralToken, address(this), sellCollateralAmount);
        uint256 repayDebtAmount =
            _swapCollateral(position.collateralToken, position.debtToken, sellCollateralAmount, swapData);
        position.collateralAmount = position.collateralAmount - sellCollateralAmount;

        (Coupon[] memory couponsToPay, Coupon[] memory couponsToRefund,,) = _loanManager.adjustPosition(
            positionId, position.collateralAmount, position.debtAmount - repayDebtAmount, position.expiredWith
        );
        if (couponsToRefund.length > 0) {
            _loanManager.mintCoupons(couponsToRefund, address(this), new bytes(0));
            _wrapCoupons(couponsToRefund);
        }

        _executeCouponTrade(
            user, position.debtToken, couponsToPay, couponsToRefund, repayDebtAmount, type(uint256).max, 0
        );

        uint256 depositDebtTokenAmount = IERC20(position.debtToken).balanceOf(address(this));

        if (position.debtAmount < depositDebtTokenAmount) {
            depositDebtTokenAmount = position.debtAmount;
        }

        _loanManager.depositToken(position.debtToken, depositDebtTokenAmount);
        position.debtAmount = position.debtAmount - depositDebtTokenAmount;
        if (maxDebtAmount < position.debtAmount) revert ControllerSlippage();

        (, Coupon[] memory leftCoupons,,) = _loanManager.adjustPosition(
            positionId, position.collateralAmount, position.debtAmount, position.expiredWith
        );
        _loanManager.mintCoupons(leftCoupons, user, "");
        _burnAllSubstitute(position.debtToken, user);
        _loanManager.settlePosition(positionId);
    }

    function repayWithCollateral(
        uint256 positionId,
        uint256 sellCollateralAmount,
        uint256 minRepayAmount,
        bytes memory swapData,
        PermitParams calldata positionPermitParams
    ) external nonReentrant onlyPositionOwner(positionId) {
        _permitERC721(_loanManager, positionId, positionPermitParams);
        LoanPosition memory position = _loanManager.getPosition(positionId);

        position.collateralAmount -= sellCollateralAmount;
        _loanManager.lock(abi.encode(positionId, msg.sender, sellCollateralAmount, minRepayAmount, swapData));
    }

    function _swapCollateral(address inToken, address outToken, uint256 inAmount, bytes memory swapData)
        internal
        returns (uint256 outAmount)
    {
        ISubstitute(inToken).burn(inAmount, address(this));
        IERC20(ISubstitute(inToken).underlyingToken()).approve(_odosRouter, inAmount);

        address outTokenUnderlying = ISubstitute(outToken).underlyingToken();

        (bool success, bytes memory result) = _odosRouter.call(swapData);
        if (!success) revert CollateralSwapFailed(string(result));

        outAmount = IERC20(outTokenUnderlying).balanceOf(address(this));

        IERC20(outTokenUnderlying).approve(outToken, outAmount);
        ISubstitute(outToken).mint(outAmount, address(this));
    }

    function setCollateralAllowance(address collateralToken) external onlyOwner {
        IERC20(collateralToken).approve(address(_loanManager), type(uint256).max);
    }
}
