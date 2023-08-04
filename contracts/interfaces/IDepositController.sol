// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {PermitParams} from "../libraries/PermitParams.sol";

interface IDepositController {
    function deposit(
        address token,
        uint256 amount,
        uint8 lockEpochs,
        uint256 minEarnInterest,
        PermitParams calldata tokenPermitParams
    ) external payable;

    function withdraw(
        uint256 positionId,
        uint256 withdrawAmount,
        uint256 maxPayInterest,
        PermitParams calldata positionPermitParams
    ) external;

    function collect(uint256 positionId, PermitParams calldata positionPermitParams) external;
}
