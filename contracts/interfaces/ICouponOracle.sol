// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

interface ICouponOracleTypes {
    error LengthMismatch();
    error InvalidDecimals();
    error AssetFeedAlreadySet();
    error InvalidGracePeriod();

    event SetSequencerOracle(address indexed newSequencerOracle);
    event SetGracePeriod(uint256 newGracePeriod);
    event SetFallbackOracle(address indexed newFallbackOracle);
    event SetFeed(address indexed asset, address indexed feed);
}

interface ICouponOracle is ICouponOracleTypes {
    function decimals() external view returns (uint8);

    function sequencerOracle() external view returns (address);

    function gracePeriod() external view returns (uint256);

    function fallbackOracle() external view returns (address);

    function getFeed(address asset) external view returns (address);

    function getAssetPrice(address asset) external view returns (uint256);

    function getAssetsPrices(address[] calldata assets) external view returns (uint256[] memory);

    function isSequencerValid() external view returns (bool);

    function setFallbackOracle(address newFallbackOracle) external;

    function setFeeds(address[] memory assets, address[] memory feeds) external;

    function setSequencerOracle(address newSequencerOracle) external;

    function setGracePeriod(uint256 newGracePeriod) external;
}
