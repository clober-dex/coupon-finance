// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {Epoch} from "../libraries/Epoch.sol";

interface IController {
    struct ERC20PermitParams {
        uint256 permitAmount;
        PermitSignature signature;
    }

    struct PermitSignature {
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    event SetManagerAllowance(address indexed token);
    event SetCouponMarket(address indexed asset, Epoch indexed epoch, address indexed cloberMarket);

    error InvalidAccess();
    error InvalidMarket();
    error ControllerSlippage();

    function giveManagerAllowance(address token) external;
}
