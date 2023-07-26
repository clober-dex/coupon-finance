// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {ILoanPositionCallbackReceiver} from "./ILoanPositionCallbackReceiver.sol";
import {PermitParams} from "../libraries/PermitParams.sol";

interface IBorrowController is ILoanPositionCallbackReceiver {
    function borrow(
        address collateralToken,
        address debtToken,
        uint256 collateralAmount,
        uint256 borrowAmount,
        uint256 maxDebtAmount,
        uint16 loanEpochs,
        PermitParams calldata collateralPermitParams
    ) external;

    function borrowMore(
        uint256 positionId,
        uint256 amount,
        uint256 maxDebtIncreaseAmount,
        PermitParams calldata positionPermitParams
    ) external;

    function addCollateral(
        uint256 positionId,
        uint256 amount,
        PermitParams calldata positionPermitParams,
        PermitParams calldata collateralPermitParams
    ) external payable;

    function removeCollateral(uint256 positionId, uint256 amount, PermitParams calldata positionPermitParams) external;

    function adjustLoanEpochs(
        uint256 positionId,
        uint16 loanEpochs,
        uint256 maxDebtAmount,
        PermitParams calldata positionPermitParams
    ) external;

    function repay(
        uint256 positionId,
        uint256 amount,
        uint256 minEarnedInterest,
        PermitParams calldata positionPermitParams,
        PermitParams calldata debtPermitParams
    ) external payable;

    function repayWithCollateral(
        uint256 positionId,
        uint256 repayAmount,
        uint256 minEarnedInterest,
        bytes calldata swapData,
        PermitParams calldata positionPermitParams
    ) external;
}
