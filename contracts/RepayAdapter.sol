// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ISubstitute} from "./interfaces/ISubstitute.sol";
import {ILoanPositionManager} from "./interfaces/ILoanPositionManager.sol";
import {LoanPosition} from "./libraries/LoanPosition.sol";
import {Coupon} from "./libraries/Coupon.sol";
import {Controller} from "./libraries/Controller.sol";
import {IPositionLocker} from "./interfaces/IPositionLocker.sol";
import {IRepayAdapter} from "./interfaces/IRepayAdapter.sol";

contract RepayAdapter is IRepayAdapter, Controller, IPositionLocker {
    ILoanPositionManager private immutable _loanManager;
    address private immutable _router;

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
        address router
    ) Controller(wrapped1155Factory, cloberMarketFactory, couponManager, weth) {
        _loanManager = ILoanPositionManager(loanManager);
        _router = router;
    }

    function positionLockAcquired(bytes memory data) external returns (bytes memory) {
        if (msg.sender != address(_loanManager)) revert InvalidAccess();

        (uint256 positionId, address user, uint256 sellCollateralAmount, uint256 minRepayAmount, bytes memory swapData)
        = abi.decode(data, (uint256, address, uint256, uint256, bytes));
        LoanPosition memory position = _loanManager.getPosition(positionId);
        uint256 maxDebtAmount = position.debtAmount - minRepayAmount;

        _loanManager.withdrawToken(position.collateralToken, address(this), sellCollateralAmount);
        (uint256 leftCollateralAmount, uint256 repayDebtAmount) =
            _swapCollateral(position.collateralToken, position.debtToken, sellCollateralAmount, swapData);
        _loanManager.depositToken(position.collateralToken, leftCollateralAmount);
        position.collateralAmount = position.collateralAmount - sellCollateralAmount + leftCollateralAmount;
        if (position.debtAmount < repayDebtAmount) {
            repayDebtAmount = position.debtAmount;
        }

        // @dev We know that couponsToBurn.length == 0
        (Coupon[] memory couponsToMint, Coupon[] memory couponsToBurn,,) = _loanManager.adjustPosition(
            positionId, position.collateralAmount, position.debtAmount - repayDebtAmount, position.expiredWith
        );
        if (couponsToMint.length > 0) {
            _loanManager.mintCoupons(couponsToMint, address(this), new bytes(0));
            _wrapCoupons(couponsToMint);
        }

        _executeCouponTrade(
            user, position.debtToken, couponsToBurn, couponsToMint, repayDebtAmount, type(uint256).max, 0
        );

        uint256 depositDebtTokenAmount = IERC20(position.debtToken).balanceOf(address(this));

        if (position.debtAmount < depositDebtTokenAmount) {
            depositDebtTokenAmount = position.debtAmount;
        }

        _loanManager.depositToken(position.debtToken, depositDebtTokenAmount);
        position.debtAmount = position.debtAmount - depositDebtTokenAmount;
        if (maxDebtAmount < position.debtAmount) revert ControllerSlippage();

        (Coupon[] memory leftCoupons,,,) = _loanManager.adjustPosition(
            positionId, position.collateralAmount, position.debtAmount, position.expiredWith
        );
        _loanManager.mintCoupons(leftCoupons, user, "");
        _burnAllSubstitute(position.debtToken, user);
        _loanManager.settlePosition(positionId);
        return "";
    }

    function repayWithCollateral(
        uint256 positionId,
        uint256 sellCollateralAmount,
        uint256 minRepayAmount,
        bytes memory swapData,
        PermitSignature calldata positionPermitParams
    ) external nonReentrant onlyPositionOwner(positionId) {
        _permitERC721(_loanManager, positionId, positionPermitParams);
        _loanManager.lock(abi.encode(positionId, msg.sender, sellCollateralAmount, minRepayAmount, swapData));
    }

    function _swapCollateral(address collateral, address debt, uint256 inAmount, bytes memory swapData)
        internal
        returns (uint256 leftInAmount, uint256 outAmount)
    {
        address inToken = ISubstitute(collateral).underlyingToken();
        address outToken = ISubstitute(debt).underlyingToken();

        ISubstitute(collateral).burn(inAmount, address(this));
        IERC20(inToken).approve(_router, inAmount);
        (bool success, bytes memory result) = _router.call(swapData);
        if (!success) revert CollateralSwapFailed(string(result));
        IERC20(inToken).approve(_router, 0);

        outAmount = IERC20(outToken).balanceOf(address(this));
        leftInAmount = IERC20(inToken).balanceOf(address(this));

        if (leftInAmount > 0) {
            IERC20(inToken).approve(collateral, leftInAmount);
            ISubstitute(collateral).mint(leftInAmount, address(this));
        }

        IERC20(outToken).approve(debt, outAmount);
        ISubstitute(debt).mint(outAmount, address(this));
    }

    function setCollateralAllowance(address collateralToken) external onlyOwner {
        IERC20(collateralToken).approve(address(_loanManager), type(uint256).max);
    }
}
