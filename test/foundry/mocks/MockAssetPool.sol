// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IAssetPool} from "../../../contracts/interfaces/IAssetPool.sol";

contract MockAssetPool is IAssetPool {
    using SafeERC20 for IERC20;

    address public override treasury;
    mapping(address asset => uint256) public override totalReservedAmount;
    mapping(address => bool) public override isAssetRegistered;
    mapping(address => uint256) public withdrawLimit;

    function isOperator(address) external pure returns (bool) {
        return true;
    }

    function withdrawable(address asset) external view returns (uint256 amount) {
        amount = totalReservedAmount[asset];
        if (withdrawLimit[asset] > 0 && amount > withdrawLimit[asset]) {
            amount = withdrawLimit[asset];
        }
    }

    function deposit(address asset, uint256 amount) external {
        require(IERC20(asset).balanceOf(address(this)) >= totalReservedAmount[asset] + amount, "insufficient balance");
        totalReservedAmount[asset] += amount;
    }

    function withdraw(address asset, uint256 amount, address recipient) external {
        require(totalReservedAmount[asset] >= amount, "insufficient balance");
        IERC20(asset).safeTransfer(recipient, amount);
        totalReservedAmount[asset] -= amount;
    }

    function claimableAmount(address asset) public view returns (uint256) {
        return IERC20(asset).balanceOf(address(this)) - totalReservedAmount[asset];
    }

    function claim(address asset) external {
        IERC20(asset).safeTransfer(treasury, claimableAmount(asset));
    }

    function setWithdrawLimit(address asset, uint256 amount) external {
        withdrawLimit[asset] = amount;
    }

    function setTreasury(address newTreasury) external {
        treasury = newTreasury;
    }

    function registerAsset(address asset) external {
        isAssetRegistered[asset] = true;
    }

    function withdrawLostToken(address asset, address recipient) external {
        IERC20(asset).safeTransfer(recipient, IERC20(asset).balanceOf(address(this)));
    }
}
