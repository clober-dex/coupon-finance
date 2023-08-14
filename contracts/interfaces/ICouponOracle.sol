// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

interface ICouponOracle {
    error LengthMismatch();
    error InvalidDecimals();
    error AssetFeedAlreadySet();

    function decimals() external view returns (uint8);

    function fallbackOracle() external view returns (address);

    function getFeed(address asset) external view returns (address);

    function getAssetPrice(address asset) external view returns (uint256);

    function getAssetsPrices(address[] calldata assets) external view returns (uint256[] memory);

    function setFallbackOracle(address newFallbackOracle) external;

    function setFeeds(address[] memory assets, address[] memory feeds) external;
}
