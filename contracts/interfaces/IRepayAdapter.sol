// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

interface IRepayAdapter {
    error InvalidAccess();

    struct PermitParams {
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    function repayWithCollateral(
        uint256 positionId,
        uint256 sellCollateralAmount,
        uint256 minRepayAmount,
        bytes swapData,
        PermitParams calldata positionPermitParams
    ) external;
}
