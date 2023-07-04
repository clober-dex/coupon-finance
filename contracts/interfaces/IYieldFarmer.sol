// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

interface IYieldFarmer {
    function totalReservedAmount(address asset) external view returns (uint256);

    function reservedAmount(address asset, address user) external view returns (uint256);

    function withdrawable(address asset) external view returns (uint256);

    function claimable(address asset, address user) external view returns (uint256);

    function deposit(address asset, uint256 amount, address recipient) external;

    function withdraw(address asset, uint256 amount, address recipient) external;

    function claim(address asset, address user) external;
}
