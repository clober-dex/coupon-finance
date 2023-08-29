// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

interface IController {
    struct ERC20PermitParams {
        uint256 permitAmount;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    struct ERC721PermitParams {
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    error ValueTransferFailed();
    error InvalidAccess();
    error InvalidMarket();
    error ControllerSlippage();
}
