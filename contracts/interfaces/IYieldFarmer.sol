// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

interface IYieldFarmer {
    function assetBalance(address asset) external view returns (uint256);

    function withdrawableBalance(address asset) external view returns (uint256);

    function deposit(address asset, uint256 amount) external;

    function withdraw(address asset, uint256 amount) external;
}
