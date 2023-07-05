// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../../contracts/interfaces/IYieldFarmer.sol";

contract MockYieldFarmer is IYieldFarmer {
    mapping(address asset => uint256) public override totalReservedAmount;
    mapping(address asset => uint256) public override reservedAmount;
    mapping(address => uint256) public withdrawLimit;

    function withdrawable(address asset) external view returns (uint256 amount) {
        amount = totalReservedAmount[asset];
        if (withdrawLimit[asset] > 0 && amount > withdrawLimit[asset]) {
            amount = withdrawLimit[asset];
        }
    }

    function deposit(address asset, uint256 amount) external {
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        totalReservedAmount[asset] += amount;
        reservedAmount[asset] += amount;
    }

    function withdraw(address asset, uint256 amount, address recipient) external {
        require(totalReservedAmount[asset] >= amount, "insufficient balance");
        IERC20(asset).transfer(recipient, amount);
        totalReservedAmount[asset] -= amount;
        reservedAmount[asset] -= amount;
    }

    function setWithdrawLimit(address asset, uint256 amount) external {
        withdrawLimit[asset] = amount;
    }
}
