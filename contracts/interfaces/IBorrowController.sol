// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {PermitParams} from "../libraries/PermitParams.sol";

interface IBorrowController {
    function borrow(
        address collateralToken,
        address debtToken,
        uint256 collateralAmount,
        uint256 borrowAmount,
        uint256 maxPayInterest,
        uint8 loanEpochs,
        PermitParams calldata collateralPermitParams
    ) external payable;

    function borrowMore(
        uint256 positionId,
        uint256 amount,
        uint256 maxPayInterest,
        PermitParams calldata positionPermitParams
    ) external;

    function addCollateral(
        uint256 positionId,
        uint256 amount,
        PermitParams calldata positionPermitParams,
        PermitParams calldata collateralPermitParams
    ) external payable;

    function removeCollateral(uint256 positionId, uint256 amount, PermitParams calldata positionPermitParams)
        external;

    function extendLoanDuration(
        uint256 positionId,
        uint8 epochs,
        uint256 maxPayInterest,
        PermitParams calldata positionPermitParams,
        PermitParams calldata debtPermitParams
    ) external payable;

    function shortenLoanDuration(
        uint256 positionId,
        uint8 epochs,
        uint256 minEarnInterest,
        PermitParams calldata positionPermitParams
    ) external;

    function repay(
        uint256 positionId,
        uint256 amount,
        uint256 minEarnInterest,
        PermitParams calldata positionPermitParams,
        PermitParams calldata debtPermitParams
    ) external payable;

    struct SwapData {
        address swap;
        uint256 inAmount;
        uint256 minOutAmount;
        bytes data;
    }

    function repayWithCollateral(
        uint256 positionId,
        uint256 maxDebtAmount,
        SwapData calldata swapData,
        PermitParams calldata positionPermitParams
    ) external;
}
