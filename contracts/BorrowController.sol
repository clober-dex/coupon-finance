// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IWETH9} from "./external/weth/IWETH9.sol";
import {IERC721Permit} from "./interfaces/IERC721Permit.sol";
import {IBorrowController} from "./interfaces/IBorrowController.sol";
import {ILoanPositionManager} from "./interfaces/ILoanPositionManager.sol";
import {LoanPosition, LoanPositionLibrary} from "./libraries/LoanPosition.sol";
import {CouponKey, CouponKeyLibrary} from "./libraries/CouponKey.sol";
import {Coupon} from "./libraries/Coupon.sol";
import {Epoch, EpochLibrary} from "./libraries/Epoch.sol";
import {PermitParams} from "./libraries/PermitParams.sol";
import {Controller} from "./libraries/Controller.sol";

contract BorrowController is IBorrowController, Controller {
    using SafeERC20 for IERC20;
    using LoanPositionLibrary for LoanPosition;
    using CouponKeyLibrary for CouponKey;
    using EpochLibrary for Epoch;

    bytes private constant _EMPTY_BYTES = "E";

    ILoanPositionManager private immutable _loanManager;

    enum CallType {
        MINT,
        INCREASE_DEBT,
        DECREASE_DEBT
    }

    bytes private _loanManagerData;
    bytes private _swapData;

    constructor(
        address wrapped1155Factory,
        address cloberMarketFactory,
        address couponManager,
        address weth,
        address loanManager
    ) Controller(wrapped1155Factory, cloberMarketFactory, couponManager, weth) {
        _loanManager = ILoanPositionManager(loanManager);
        _loanManagerData = _EMPTY_BYTES;
        _swapData = _EMPTY_BYTES;
    }

    function borrow(
        address collateralToken,
        address debtToken,
        uint256 collateralAmount,
        uint256 borrowAmount,
        uint256 maxDebtAmount,
        uint8 loanEpochs,
        PermitParams calldata collateralPermitParams
    ) external payable nonReentrant wrapETH {
        _permitERC20(collateralToken, collateralAmount, collateralPermitParams);
        LoanPosition memory emptyPosition = LoanPositionLibrary.empty(collateralToken, debtToken);
        LoanPosition memory newPosition = LoanPositionLibrary.from(
            EpochLibrary.current().add(loanEpochs - 1), collateralToken, debtToken, collateralAmount, borrowAmount
        );
        (Coupon[] memory couponsToPay,) = emptyPosition.calculateCouponRequirement(newPosition);

        _loanManagerData = abi.encode(
            CallType.MINT,
            abi.encode(msg.sender, loanEpochs, collateralToken, collateralAmount, borrowAmount, maxDebtAmount)
        );
        _execute(debtToken, couponsToPay, new Coupon[](0), 0, 0);
        _loanManagerData = _EMPTY_BYTES;

        _flush(collateralToken, msg.sender);
        _flush(debtToken, msg.sender);
    }

    function borrowMore(
        uint256 positionId,
        uint256 amount,
        uint256 maxDebtAmount,
        PermitParams calldata positionPermitParams
    ) external nonReentrant {
        _permitERC721(_loanManager, positionId, positionPermitParams);
        LoanPosition memory oldPosition = _loanManager.getPosition(positionId);
        LoanPosition memory newPosition = oldPosition.clone();
        newPosition.debtAmount += amount;
        _adjustPosition(CallType.INCREASE_DEBT, positionId, oldPosition, newPosition, maxDebtAmount);
        _flush(oldPosition.debtToken, msg.sender);
    }

    function addCollateral(
        uint256 positionId,
        uint256 amount,
        PermitParams calldata positionPermitParams,
        PermitParams calldata collateralPermitParams
    ) external payable nonReentrant wrapETH {
        _permitERC721(_loanManager, positionId, positionPermitParams);
        LoanPosition memory position = _loanManager.getPosition(positionId);
        _permitERC20(position.collateralToken, amount, collateralPermitParams);
        _loanManager.adjustPosition(
            positionId,
            position.collateralAmount + amount,
            position.debtAmount,
            position.expiredWith,
            abi.encode(msg.sender)
        );
    }

    function removeCollateral(uint256 positionId, uint256 amount, PermitParams calldata positionPermitParams)
        external
        nonReentrant
    {
        _permitERC721(_loanManager, positionId, positionPermitParams);
        LoanPosition memory position = _loanManager.getPosition(positionId);
        _loanManager.adjustPosition(
            positionId,
            position.collateralAmount - amount,
            position.debtAmount,
            position.expiredWith,
            abi.encode(msg.sender)
        );
        _flush(position.collateralToken, msg.sender);
    }

    function adjustLoanEpochs(
        uint256 positionId,
        Epoch newEpoch,
        uint256 maxDebtAmount,
        PermitParams calldata positionPermitParams
    ) external nonReentrant {
        _permitERC721(_loanManager, positionId, positionPermitParams);
        LoanPosition memory oldPosition = _loanManager.getPosition(positionId);
        LoanPosition memory newPosition = oldPosition.clone();
        newPosition.expiredWith = newEpoch;
        _adjustPosition(CallType.INCREASE_DEBT, positionId, oldPosition, newPosition, maxDebtAmount);
    }

    function repay(
        uint256 positionId,
        uint256 amount,
        uint256 minEarnedInterest,
        PermitParams calldata positionPermitParams,
        PermitParams calldata debtPermitParams
    ) external payable nonReentrant wrapETH {
        _permitERC721(_loanManager, positionId, positionPermitParams);
        LoanPosition memory oldPosition = _loanManager.getPosition(positionId);
        LoanPosition memory newPosition = oldPosition.clone();
        newPosition.debtAmount -= amount;
        _permitERC20(oldPosition.debtToken, amount, debtPermitParams);
        _adjustPosition(CallType.DECREASE_DEBT, positionId, oldPosition, newPosition, minEarnedInterest);
        _flush(oldPosition.debtToken, msg.sender);
    }

    function repayWithCollateral(
        uint256 positionId,
        uint256 collateralAmount,
        uint256 maxDebtAmount,
        bytes calldata swapData,
        PermitParams calldata positionPermitParams
    ) external nonReentrant {
        _permitERC721(_loanManager, positionId, positionPermitParams);
        LoanPosition memory oldPosition = _loanManager.getPosition(positionId);
        LoanPosition memory newPosition = oldPosition.clone();
        require(swapData.length > 2, "wrong swap data");
        _swapData = swapData;
        newPosition.collateralAmount -= collateralAmount;
        require(maxDebtAmount < newPosition.debtAmount, "Wrong debt amount");
        newPosition.debtAmount = maxDebtAmount;
        _adjustPosition(CallType.DECREASE_DEBT, positionId, oldPosition, newPosition, 0);

        uint256 leftDebt = IERC20(newPosition.debtToken).balanceOf(address(this));
        if (leftDebt > 0) {
            _loanManager.adjustPosition(
                positionId,
                newPosition.collateralAmount,
                newPosition.debtAmount > leftDebt ? newPosition.debtAmount - leftDebt : 0,
                newPosition.expiredWith,
                abi.encode(msg.sender)
            );
        }
    }

    function _swapCollateral(address debtToken) internal {
        uint256 beforeBalance = IERC20(debtToken).balanceOf(address(this));
        (address swap, uint256 minOutAmount, bytes memory data) = abi.decode(_swapData, (address, uint256, bytes));
        (bool success, bytes memory result) = swap.call(data);
        require(success, string(result));
        if (minOutAmount > IERC20(debtToken).balanceOf(address(this)) - beforeBalance) {
            revert ControllerSlippage();
        }
        _swapData = _EMPTY_BYTES;
    }

    function _adjustPosition(
        CallType callType,
        uint256 positionId,
        LoanPosition memory oldPosition,
        LoanPosition memory newPosition,
        uint256 threshold
    ) internal {
        (Coupon[] memory couponsToPay, Coupon[] memory couponsToRefund) =
            oldPosition.calculateCouponRequirement(newPosition);
        _loanManagerData = abi.encode(
            callType,
            abi.encode(
                msg.sender,
                newPosition.expiredWith,
                newPosition.collateralAmount,
                newPosition.debtAmount,
                threshold,
                positionId
            )
        );
        _execute(oldPosition.debtToken, couponsToPay, couponsToRefund, 0, 0);
        _loanManagerData = _EMPTY_BYTES;
    }

    function _increaseDebt(
        uint256 positionId,
        LoanPosition memory oldPosition,
        LoanPosition memory newPosition,
        uint256 maxDebtAmount
    ) internal {
        (Coupon[] memory couponsToPay, Coupon[] memory couponsToRefund) =
            oldPosition.calculateCouponRequirement(newPosition);
        _loanManagerData = abi.encode(
            CallType.INCREASE_DEBT,
            abi.encode(
                msg.sender,
                newPosition.expiredWith,
                newPosition.collateralAmount,
                newPosition.debtAmount,
                maxDebtAmount,
                positionId
            )
        );
        _execute(oldPosition.debtToken, couponsToPay, couponsToRefund, 0, 0);
        _loanManagerData = _EMPTY_BYTES;
    }

    function _decreaseDebt(
        uint256 positionId,
        LoanPosition memory oldPosition,
        LoanPosition memory newPosition,
        uint256 minEarnedInterest
    ) internal {
        (Coupon[] memory couponsToPay, Coupon[] memory couponsToRefund) =
            oldPosition.calculateCouponRequirement(newPosition);
        _loanManagerData = abi.encode(
            CallType.DECREASE_DEBT,
            abi.encode(
                msg.sender,
                newPosition.expiredWith,
                newPosition.collateralAmount,
                newPosition.debtAmount,
                minEarnedInterest,
                positionId
            )
        );
        _execute(oldPosition.debtToken, couponsToPay, couponsToRefund, 0, 0);
        _loanManagerData = _EMPTY_BYTES;
    }

    function _callManager(address debtToken, uint256 amountToPay, uint256 earnedAmount) internal override {
        (CallType callType, bytes memory data) = abi.decode(_loanManagerData, (CallType, bytes));
        if (callType == CallType.MINT) {
            (
                address user,
                uint8 loanEpochs,
                address collateralToken,
                uint256 collateralAmount,
                uint256 debtAmount,
                uint256 maxDebtAmount
            ) = abi.decode(data, (address, uint8, address, uint256, uint256, uint256));
            debtAmount += amountToPay;
            if (debtAmount > maxDebtAmount) revert ControllerSlippage();
            uint256 positionId = _loanManager.mint(
                collateralToken, debtToken, collateralAmount, debtAmount, loanEpochs, address(this), abi.encode(user)
            );
            _loanManager.transferFrom(address(this), user, positionId);
        } else if (callType == CallType.INCREASE_DEBT) {
            (
                address user,
                Epoch expiredWith,
                uint256 collateralAmount,
                uint256 debtAmount,
                uint256 maxDebtAmount,
                uint256 positionId
            ) = abi.decode(data, (address, Epoch, uint256, uint256, uint256, uint256));
            debtAmount += amountToPay;
            if (debtAmount > maxDebtAmount) revert ControllerSlippage();
            _loanManager.adjustPosition(positionId, collateralAmount, debtAmount, expiredWith, abi.encode(user));
        } else if (callType == CallType.DECREASE_DEBT) {
            (
                address user,
                Epoch expiredWith,
                uint256 collateralAmount,
                uint256 debtAmount,
                uint256 minEarnedInterest,
                uint256 positionId
            ) = abi.decode(data, (address, Epoch, uint256, uint256, uint256, uint256));
            if (earnedAmount < minEarnedInterest) revert ControllerSlippage();
            _loanManager.adjustPosition(positionId, collateralAmount, debtAmount, expiredWith, abi.encode(user));
        } else {
            revert("invalid call type");
        }
    }

    function loanPositionAdjustCallback(
        uint256,
        LoanPosition memory oldPosition,
        LoanPosition memory newPosition,
        Coupon[] memory couponsToPay,
        Coupon[] memory couponsRefunded,
        bytes calldata data
    ) external {
        if (msg.sender != address(_loanManager)) revert Access();
        (address user) = abi.decode(data, (address));

        if (couponsRefunded.length > 0) _wrapCoupons(couponsRefunded);

        if (_swapData.length > _EMPTY_BYTES.length) {
            _swapCollateral(newPosition.debtToken);
        }

        if (oldPosition.debtAmount > newPosition.debtAmount) {
            _ensureBalance(newPosition.debtToken, user, oldPosition.debtAmount - newPosition.debtAmount);
        }
        if (oldPosition.collateralAmount < newPosition.collateralAmount) {
            _ensureBalance(
                newPosition.collateralToken, user, newPosition.collateralAmount - oldPosition.collateralAmount
            );
        }

        if (couponsToPay.length > 0) _unwrapCoupons(couponsToPay);
    }

    function setCollateralAllowance(address collateralToken) external onlyOwner {
        IERC20(collateralToken).approve(address(_loanManager), type(uint256).max);
    }
}
