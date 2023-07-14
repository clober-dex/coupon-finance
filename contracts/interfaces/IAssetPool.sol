// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

interface IAssetPool {
    function treasury() external view returns (address);

    function totalReservedAmount(address asset) external view returns (uint256);

    function reservedAmount(address asset) external view returns (uint256);

    function withdrawable(address asset) external view returns (uint256);

    function deposit(address asset, uint256 amount) external;

    function withdraw(address asset, uint256 amount, address recipient) external;

    function claimableAmount(address asset) external view returns (uint256);

    function claim(address asset, address recipient) external;

    function setTreasury(address newTreasury) external;
}
