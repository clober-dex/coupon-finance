// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {ILoanPositionCallbackReceiver} from "./ILoanPositionCallbackReceiver.sol";
import {PermitParams} from "../libraries/PermitParams.sol";
import {CouponKey} from "../libraries/CouponKey.sol";
import {Epoch} from "../libraries/Epoch.sol";

interface IBorrowController is ILoanPositionCallbackReceiver {
    function borrow(
        address collateralToken,
        address debtToken,
        uint256 collateralAmount,
        uint256 borrowAmount,
        uint256 maxPayAmount,
        uint8 loanEpochs,
        PermitParams calldata collateralPermitParams
    ) external payable;

    function borrowMore(
        uint256 positionId,
        uint256 amount,
        uint256 maxPayAmount,
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

    function adjustLoanEpochs(
        uint256 positionId,
        Epoch newEpoch,
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
        uint256 collateralAmount,
        uint256 minEarnedInterest,
        bytes calldata swapData,
        PermitParams calldata positionPermitParams
    ) external;
}
