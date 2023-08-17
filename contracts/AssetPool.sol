// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IAssetPool} from "./interfaces/IAssetPool.sol";

contract AssetPool is IAssetPool {
    using SafeERC20 for IERC20;

    mapping(address => bool) public override isOperator;

    constructor(address[] memory operators) {
        for (uint256 i = 0; i < operators.length; ++i) {
            isOperator[operators[i]] = true;
        }
    }

    function withdraw(address asset, uint256 amount, address recipient) external {
        if (!isOperator[msg.sender]) {
            revert InvalidAccess();
        }
        IERC20(asset).safeTransfer(recipient, amount);
    }
}
