// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface ICouponOracle {
    function aaveOracle() external returns (address);

    function wethAddress() external returns (address);

    /**
     * @notice Returns the asset price in the base currency
     * @param asset The address of the asset
     * @return The price of the asset
     */
    function getAssetPrice(address asset) external view returns (uint256);

    /**
     * @notice Returns a list of prices from a list of assets addresses
     * @param assets The list of assets addresses
     * @return The prices of the given assets
     */
    function getAssetsPrices(address[] calldata assets) external view returns (uint256[] memory);

    /**
     * @notice Returns a list of prices from a list of assets addresses
     * @param asset1 The address of the first asset
     * @param asset2 The address of the second asset
     * @return The prices of the given assets with eth price
     */
    function getTwoAssetsPricesWithEthPrice(
        address asset1,
        address asset2
    ) external view returns (uint256, uint256, uint256);
}
