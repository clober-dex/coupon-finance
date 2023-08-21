// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IBorrowController} from "./interfaces/IBorrowController.sol";
import {ILoanPositionManager} from "./interfaces/ILoanPositionManager.sol";
import {LoanPosition} from "./libraries/LoanPosition.sol";
import {Coupon} from "./libraries/Coupon.sol";
import {Epoch, EpochLibrary} from "./libraries/Epoch.sol";
import {Controller} from "./libraries/Controller.sol";
import {IPositionLocker} from "./interfaces/IPositionLocker.sol";

contract BorrowController is IBorrowController, Controller, IPositionLocker {
    using EpochLibrary for Epoch;

    ILoanPositionManager private immutable _loanManager;

    modifier onlyPositionOwner(uint256 positionId) {
        if (_loanManager.ownerOf(positionId) != msg.sender) revert InvalidAccess();
        _;
    }

    constructor(
        address wrapped1155Factory,
        address cloberMarketFactory,
        address couponManager,
        address weth,
        address loanManager
    ) Controller(wrapped1155Factory, cloberMarketFactory, couponManager, weth) {
        _loanManager = ILoanPositionManager(loanManager);
    }

    function positionLockAcquired(bytes memory data) external returns (bytes memory result) {
        if (msg.sender != address(_loanManager)) revert InvalidAccess();

        uint256 positionId;
        address user;
        (positionId, user, data) = abi.decode(data, (uint256, address, bytes));
        if (positionId == 0) {
            address collateralToken;
            address debtToken;
            (collateralToken, debtToken, data) = abi.decode(data, (address, address, bytes));
            positionId = _loanManager.mint(collateralToken, debtToken);
            result = abi.encode(positionId);
        }
        LoanPosition memory position = _loanManager.getPosition(positionId);

        uint256 maxPayInterest;
        uint256 minEarnInterest;
        (position.collateralAmount, position.debtAmount, position.expiredWith, maxPayInterest, minEarnInterest) =
            abi.decode(data, (uint256, uint256, Epoch, uint256, uint256));

        (Coupon[] memory couponsToPay, Coupon[] memory couponsToRefund, int256 collateralDelta, int256 debtDelta) =
        _loanManager.adjustPosition(positionId, position.collateralAmount, position.debtAmount, position.expiredWith);
        if (collateralDelta < 0) {
            _loanManager.withdrawToken(position.collateralToken, address(this), uint256(-collateralDelta));
        }
        if (debtDelta > 0) {
            _loanManager.withdrawToken(position.debtToken, address(this), uint256(debtDelta));
        }
        if (couponsToRefund.length > 0) {
            _loanManager.mintCoupons(couponsToRefund, address(this), new bytes(0));
            _wrapCoupons(couponsToRefund);
        }

        _executeCouponTrade(
            user,
            position.debtToken,
            couponsToPay,
            couponsToRefund,
            debtDelta < 0 ? uint256(-debtDelta) : 0,
            maxPayInterest,
            minEarnInterest
        );

        if (collateralDelta > 0) {
            _ensureBalance(position.collateralToken, user, uint256(collateralDelta));
            _loanManager.depositToken(position.collateralToken, uint256(collateralDelta));
        }
        if (debtDelta < 0) {
            _loanManager.depositToken(position.debtToken, uint256(-debtDelta));
        }
        if (couponsToPay.length > 0) {
            _unwrapCoupons(couponsToPay);
            _loanManager.burnCoupons(couponsToPay);
        }

        _loanManager.settlePosition(positionId);
    }

    function borrow(
        address collateralToken,
        address debtToken,
        uint256 collateralAmount,
        uint256 borrowAmount,
        uint256 maxPayInterest,
        uint8 loanEpochs,
        PermitParams calldata collateralPermitParams
    ) external payable nonReentrant wrapETH {
        _permitERC20(collateralToken, collateralAmount, collateralPermitParams);

        bytes memory lockData = abi.encode(
            0,
            msg.sender,
            abi.encode(
                collateralToken,
                debtToken,
                abi.encode(
                    collateralAmount, borrowAmount, EpochLibrary.current().add(loanEpochs - 1), maxPayInterest, 0, ""
                )
            )
        );
        uint256 positionId = abi.decode(_loanManager.lock(lockData), (uint256));

        _burnAllSubstitute(collateralToken, msg.sender);
        _burnAllSubstitute(debtToken, msg.sender);
        _loanManager.transferFrom(address(this), msg.sender, positionId);
    }

    function borrowMore(
        uint256 positionId,
        uint256 amount,
        uint256 maxPayInterest,
        PermitParams calldata positionPermitParams
    ) external nonReentrant onlyPositionOwner(positionId) {
        _permitERC721(_loanManager, positionId, positionPermitParams);
        LoanPosition memory position = _loanManager.getPosition(positionId);
        position.debtAmount += amount;
        _loanManager.lock(_encodeLockData(positionId, position, maxPayInterest, 0));
        _burnAllSubstitute(position.debtToken, msg.sender);
    }

    function addCollateral(
        uint256 positionId,
        uint256 amount,
        PermitParams calldata positionPermitParams,
        PermitParams calldata collateralPermitParams
    ) external payable nonReentrant onlyPositionOwner(positionId) wrapETH {
        _permitERC721(_loanManager, positionId, positionPermitParams);
        LoanPosition memory position = _loanManager.getPosition(positionId);
        _permitERC20(position.collateralToken, amount, collateralPermitParams);
        position.collateralAmount += amount;
        _loanManager.lock(_encodeLockData(positionId, position, 0, 0));
    }

    function removeCollateral(uint256 positionId, uint256 amount, PermitParams calldata positionPermitParams)
        external
        nonReentrant
        onlyPositionOwner(positionId)
    {
        _permitERC721(_loanManager, positionId, positionPermitParams);
        LoanPosition memory position = _loanManager.getPosition(positionId);
        position.collateralAmount -= amount;
        _loanManager.lock(_encodeLockData(positionId, position, 0, 0));
        _burnAllSubstitute(position.collateralToken, msg.sender);
    }

    function extendLoanDuration(
        uint256 positionId,
        uint8 epochs,
        uint256 maxPayInterest,
        PermitParams calldata positionPermitParams,
        PermitParams calldata debtPermitParams
    ) external payable nonReentrant onlyPositionOwner(positionId) wrapETH {
        _permitERC721(_loanManager, positionId, positionPermitParams);
        LoanPosition memory position = _loanManager.getPosition(positionId);
        _permitERC20(position.collateralToken, maxPayInterest, debtPermitParams);
        position.expiredWith = position.expiredWith.add(epochs);
        _loanManager.lock(_encodeLockData(positionId, position, maxPayInterest, 0));
        _burnAllSubstitute(position.debtToken, msg.sender);
    }

    function shortenLoanDuration(
        uint256 positionId,
        uint8 epochs,
        uint256 minEarnInterest,
        PermitParams calldata positionPermitParams
    ) external nonReentrant onlyPositionOwner(positionId) {
        _permitERC721(_loanManager, positionId, positionPermitParams);
        LoanPosition memory position = _loanManager.getPosition(positionId);
        position.expiredWith = position.expiredWith.sub(epochs);
        _loanManager.lock(_encodeLockData(positionId, position, 0, minEarnInterest));
        _burnAllSubstitute(position.debtToken, msg.sender);
    }

    function repay(
        uint256 positionId,
        uint256 amount,
        uint256 minEarnInterest,
        PermitParams calldata positionPermitParams,
        PermitParams calldata debtPermitParams
    ) external payable nonReentrant onlyPositionOwner(positionId) wrapETH {
        _permitERC721(_loanManager, positionId, positionPermitParams);
        LoanPosition memory position = _loanManager.getPosition(positionId);
        _permitERC20(position.debtToken, amount, debtPermitParams);
        position.debtAmount -= amount;
        _loanManager.lock(_encodeLockData(positionId, position, 0, minEarnInterest));
        _burnAllSubstitute(position.debtToken, msg.sender);
    }

    function _encodeLockData(uint256 id, LoanPosition memory p, uint256 maxPay, uint256 minEarn)
        internal
        view
        returns (bytes memory)
    {
        bytes memory data = abi.encode(p.collateralAmount, p.debtAmount, p.expiredWith, maxPay, minEarn);
        return abi.encode(id, msg.sender, data);
    }

    function setCollateralAllowance(address collateralToken) external onlyOwner {
        IERC20(collateralToken).approve(address(_loanManager), type(uint256).max);
    }
}
