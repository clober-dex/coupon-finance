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
import {IPositionLocker} from "./interfaces/IPositionLocker.sol";

contract BorrowController is IBorrowController, Controller, IPositionLocker {
    using SafeERC20 for IERC20;
    using LoanPositionLibrary for LoanPosition;
    using CouponKeyLibrary for CouponKey;
    using EpochLibrary for Epoch;

    bytes private constant _EMPTY_BYTES = "E";

    ILoanPositionManager private immutable _loanManager;

    bytes private _swapData;

    modifier onlyPositionOwner(uint256 positionId) {
        if (_loanManager.ownerOf(positionId) != msg.sender) {
            revert InvalidAccess();
        }
        _;
    }

    constructor(
        address assetPool,
        address wrapped1155Factory,
        address cloberMarketFactory,
        address couponManager,
        address weth,
        address loanManager
    ) Controller(assetPool, wrapped1155Factory, cloberMarketFactory, couponManager, weth) {
        _loanManager = ILoanPositionManager(loanManager);
        _swapData = _EMPTY_BYTES;
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

        uint256 maxPayAmount;
        uint256 minEarnedInterest;
        (position.collateralAmount, position.debtAmount, position.expiredWith, maxPayAmount, minEarnedInterest) =
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
            _loanManager.withdrawCoupons(couponsToRefund, address(this), new bytes(0));
            _wrapCoupons(couponsToRefund);
        }

        if (_swapData.length > _EMPTY_BYTES.length) {
            _swapCollateral(position.debtToken);
        }

        _executeCouponTrade(
            user,
            position.debtToken,
            couponsToPay,
            couponsToRefund,
            uint256(-debtDelta),
            maxPayAmount,
            minEarnedInterest
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
            _loanManager.depositCoupons(couponsToPay);
        }
        if (_swapData.length > _EMPTY_BYTES.length) {
            uint256 leftDebtToken = IERC20(position.debtToken).balanceOf(address(this));
            if (leftDebtToken > 0) {
                position = _loanManager.getPosition(positionId);
                (, Coupon[] memory leftCoupons,,) = _loanManager.adjustPosition(
                    positionId,
                    position.collateralAmount,
                    position.debtAmount > leftDebtToken ? position.debtAmount - leftDebtToken : 0,
                    position.expiredWith
                );
                _loanManager.depositToken(position.debtToken, leftDebtToken);
                _loanManager.withdrawCoupons(leftCoupons, user, "");
            }
        }

        _loanManager.settlePosition(positionId);
    }

    function borrow(
        address collateralToken,
        address debtToken,
        uint256 collateralAmount,
        uint256 borrowAmount,
        uint256 maxPayAmount,
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
                abi.encode(collateralAmount, borrowAmount, EpochLibrary.current().add(loanEpochs - 1), maxPayAmount, 0)
            )
        );
        uint256 positionId = abi.decode(_loanManager.lock(lockData), (uint256));

        _flush(collateralToken, msg.sender);
        _flush(debtToken, msg.sender);
        _loanManager.transferFrom(address(this), msg.sender, positionId);
    }

    function borrowMore(
        uint256 positionId,
        uint256 amount,
        uint256 maxPayAmount,
        PermitParams calldata positionPermitParams
    ) external nonReentrant onlyPositionOwner(positionId) {
        _permitERC721(_loanManager, positionId, positionPermitParams);
        LoanPosition memory position = _loanManager.getPosition(positionId);
        _loanManager.lock(
            abi.encode(
                positionId,
                msg.sender,
                abi.encode(
                    position.collateralAmount, position.debtAmount + amount, position.expiredWith, maxPayAmount, 0
                )
            )
        );
        _flush(position.debtToken, msg.sender);
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
        _loanManager.lock(
            abi.encode(
                positionId,
                msg.sender,
                abi.encode(position.collateralAmount + amount, position.debtAmount, position.expiredWith, 0, 0)
            )
        );
    }

    function removeCollateral(uint256 positionId, uint256 amount, PermitParams calldata positionPermitParams)
        external
        nonReentrant
        onlyPositionOwner(positionId)
    {
        _permitERC721(_loanManager, positionId, positionPermitParams);
        LoanPosition memory position = _loanManager.getPosition(positionId);
        _loanManager.lock(
            abi.encode(
                positionId,
                msg.sender,
                abi.encode(position.collateralAmount - amount, position.debtAmount, position.expiredWith, 0, 0)
            )
        );
        _flush(position.collateralToken, msg.sender);
    }

    function extendLoanDuration(
        uint256 positionId,
        uint8 epochs,
        uint256 maxPayAmount,
        PermitParams calldata positionPermitParams,
        PermitParams calldata debtPermitParams
    ) external payable nonReentrant onlyPositionOwner(positionId) wrapETH {
        _permitERC721(_loanManager, positionId, positionPermitParams);
        LoanPosition memory position = _loanManager.getPosition(positionId);
        _permitERC20(position.collateralToken, maxPayAmount, debtPermitParams);
        _loanManager.lock(
            abi.encode(
                positionId,
                msg.sender,
                abi.encode(
                    position.collateralAmount, position.debtAmount, position.expiredWith.add(epochs), maxPayAmount, 0
                )
            )
        );
        _flush(position.debtToken, msg.sender);
    }

    function shortenLoanDuration(
        uint256 positionId,
        uint8 epochs,
        uint256 minEarnInterest,
        PermitParams calldata positionPermitParams
    ) external nonReentrant onlyPositionOwner(positionId) {
        _permitERC721(_loanManager, positionId, positionPermitParams);
        LoanPosition memory position = _loanManager.getPosition(positionId);
        _loanManager.lock(
            abi.encode(
                positionId,
                msg.sender,
                abi.encode(
                    position.collateralAmount, position.debtAmount, position.expiredWith.sub(epochs), 0, minEarnInterest
                )
            )
        );
        _flush(position.debtToken, msg.sender);
    }

    function repay(
        uint256 positionId,
        uint256 amount,
        uint256 minEarnedInterest,
        PermitParams calldata positionPermitParams,
        PermitParams calldata debtPermitParams
    ) external payable nonReentrant onlyPositionOwner(positionId) wrapETH {
        _permitERC721(_loanManager, positionId, positionPermitParams);
        LoanPosition memory position = _loanManager.getPosition(positionId);
        _permitERC20(position.debtToken, amount, debtPermitParams);
        _loanManager.lock(
            abi.encode(
                positionId,
                msg.sender,
                abi.encode(
                    position.collateralAmount, position.debtAmount - amount, position.expiredWith, 0, minEarnedInterest
                )
            )
        );
        _flush(position.debtToken, msg.sender);
    }

    function repayWithCollateral(
        uint256 positionId,
        uint256 collateralAmount,
        uint256 maxDebtAmount,
        bytes calldata swapData,
        PermitParams calldata positionPermitParams
    ) external nonReentrant onlyPositionOwner(positionId) {
        _permitERC721(_loanManager, positionId, positionPermitParams);
        LoanPosition memory position = _loanManager.getPosition(positionId);
        require(swapData.length > 2, "wrong swap data");
        _swapData = swapData;

        require(maxDebtAmount < position.debtAmount, "Wrong debt amount");
        _loanManager.lock(
            abi.encode(
                positionId,
                msg.sender,
                abi.encode(
                    position.collateralAmount - collateralAmount,
                    maxDebtAmount,
                    position.expiredWith,
                    type(uint256).max,
                    0
                )
            )
        );
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

    function setCollateralAllowance(address collateralToken) external onlyOwner {
        IERC20(collateralToken).approve(address(_loanManager), type(uint256).max);
    }
}
