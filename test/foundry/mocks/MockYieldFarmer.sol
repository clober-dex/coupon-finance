// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IYieldFarmer} from "../../../contracts/interfaces/IYieldFarmer.sol";
import {IWETH9} from "../../../contracts/external/weth/IWETH9.sol";

contract MockYieldFarmer is IYieldFarmer {
    using SafeERC20 for IERC20;

    IWETH9 private immutable _weth;

    address public override treasury;
    mapping(address asset => uint256) public override totalReservedAmount;
    mapping(address asset => uint256) public override reservedAmount;
    mapping(address => uint256) public withdrawLimit;

    constructor(address weth) {
        _weth = IWETH9(weth);
    }

    receive() external payable {}

    function withdrawable(address asset) external view returns (uint256 amount) {
        amount = totalReservedAmount[asset];
        if (withdrawLimit[asset] > 0 && amount > withdrawLimit[asset]) {
            amount = withdrawLimit[asset];
        }
    }

    function deposit(address asset, uint256 amount) external {
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        totalReservedAmount[asset] += amount;
        reservedAmount[asset] += amount;
    }

    function withdraw(address asset, uint256 amount, address recipient) external {
        bool isNative = asset == address(0);
        if (isNative) {
            asset = address(_weth);
        }
        require(totalReservedAmount[asset] >= amount, "insufficient balance");
        if (isNative) {
            _weth.withdraw(amount);
            (bool success, ) = recipient.call{value: amount}("");
            require(success, "failed to send native");
        } else {
            IERC20(asset).safeTransfer(recipient, amount);
        }
        totalReservedAmount[asset] -= amount;
        reservedAmount[asset] -= amount;
    }

    function claimableAmount(address asset) public view returns (uint256) {
        return IERC20(asset).balanceOf(address(this)) - totalReservedAmount[asset];
    }

    function claim(address asset, address recipient) external {
        IERC20(asset).safeTransfer(recipient, claimableAmount(asset));
    }

    function setWithdrawLimit(address asset, uint256 amount) external {
        withdrawLimit[asset] = amount;
    }

    function setTreasury(address newTreasury) external {
        treasury = newTreasury;
    }
}
