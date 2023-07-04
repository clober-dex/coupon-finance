// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../../contracts/interfaces/IYieldFarmer.sol";

contract MockYieldFarmer is IYieldFarmer {
    mapping(address => uint256) public override assetBalance;

    function withdrawable(address asset) external view returns (uint256) {
        return assetBalance[asset];
    }

    function deposit(address asset, uint256 amount) external {
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        assetBalance[asset] += amount;
    }

    function withdraw(address asset, uint256 amount) external {
        require(assetBalance[asset] >= amount, "insufficient balance");
        IERC20(asset).transfer(msg.sender, amount);
        assetBalance[asset] -= amount;
    }
}
