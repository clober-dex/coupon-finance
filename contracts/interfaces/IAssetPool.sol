// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

interface IAssetPoolTypes {
    error InvalidAccess();
    error InvalidAsset();
    error ExceedsBalance(uint256 balance);
}

interface IAssetPool is IAssetPoolTypes {
    function treasury() external view returns (address);

    function totalReservedAmount(address asset) external view returns (uint256);

    function isAssetRegistered(address asset) external view returns (bool);

    function isOperator(address operator) external view returns (bool);

    function claimableAmount(address asset) external view returns (uint256);

    function claim(address asset) external;

    function deposit(address asset, uint256 amount) external;

    function withdraw(address asset, uint256 amount, address recipient) external;

    function setTreasury(address newTreasury) external;

    function registerAsset(address asset) external;

    function withdrawLostToken(address asset, address recipient) external;
}
