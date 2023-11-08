// SPDX-License-Identifier: -
// License: https://license.coupon.finance/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

import {LoanPosition} from "./libraries/LoanPosition.sol";
import {IWETH9} from "./external/weth/IWETH9.sol";
import {ISubstitute} from "./interfaces/ISubstitute.sol";
import {ILoanPositionManager} from "./interfaces/ILoanPositionManager.sol";
import {IPositionLocker} from "./interfaces/IPositionLocker.sol";
import {ICouponLiquidator} from "./interfaces/ICouponLiquidator.sol";
import {ReentrancyGuard} from "./libraries/ReentrancyGuard.sol";

contract CouponLiquidator is ICouponLiquidator, Ownable2Step, ReentrancyGuard, IPositionLocker {
    using SafeERC20 for IERC20;

    ILoanPositionManager private immutable _loanManager;
    address private immutable _router;
    IWETH9 internal immutable _weth;

    constructor(address loanManager, address router, address weth) {
        _loanManager = ILoanPositionManager(loanManager);
        _router = router;
        _weth = IWETH9(weth);
    }

    function positionLockAcquired(bytes memory data) external returns (bytes memory) {
        (uint256 positionId, uint256 swapAmount, bytes memory swapData) = abi.decode(data, (uint256, uint256, bytes));

        LoanPosition memory position = _loanManager.getPosition(positionId);
        (uint256 liquidationAmount, uint256 repayAmount, uint256 protocolFeeAmount) =
            _loanManager.liquidate(positionId, swapAmount);

        uint256 collateralAmount = liquidationAmount - protocolFeeAmount;
        _loanManager.withdrawToken(position.collateralToken, address(this), collateralAmount);
        _burnAllSubstitute(position.collateralToken, address(this));

        address inToken = ISubstitute(position.collateralToken).underlyingToken();
        address outToken = ISubstitute(position.debtToken).underlyingToken();
        if (inToken == address(_weth)) {
            _weth.deposit{value: collateralAmount}();
        }

        _swap(inToken, swapAmount, swapData);
        IERC20(outToken).approve(position.debtToken, repayAmount);
        ISubstitute(position.debtToken).mint(repayAmount, address(this));
        IERC20(position.debtToken).approve(address(_loanManager), repayAmount);
        _loanManager.depositToken(position.debtToken, repayAmount);

        return abi.encode(inToken, outToken);
    }

    function liquidate(uint256 positionId, uint256 swapAmount, bytes memory swapData, address feeRecipient)
        external
        returns (bytes memory result)
    {
        bytes memory lockData = abi.encode(positionId, swapAmount, swapData);
        (address collateralToken, address debtToken) = abi.decode(_loanManager.lock(lockData), (address, address));

        uint256 collateralAmount = IERC20(collateralToken).balanceOf(address(this));
        if (collateralAmount > 0) {
            IERC20(collateralToken).safeTransfer(feeRecipient, collateralAmount);
        }

        uint256 debtAmount = IERC20(debtToken).balanceOf(address(this));
        if (debtAmount > 0) {
            IERC20(debtToken).safeTransfer(feeRecipient, debtAmount);
        }

        return "";
    }

    function _swap(address inToken, uint256 inAmount, bytes memory swapData) internal {
        IERC20(inToken).approve(_router, inAmount);
        (bool success, bytes memory result) = _router.call(swapData);
        if (!success) revert CollateralSwapFailed(string(result));
        IERC20(inToken).approve(_router, 0);
    }

    function _burnAllSubstitute(address substitute, address to) internal {
        uint256 leftAmount = IERC20(substitute).balanceOf(address(this));
        if (leftAmount == 0) return;
        ISubstitute(substitute).burn(leftAmount, to);
    }
}
