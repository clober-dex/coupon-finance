// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IAaveOracle} from "./external/aave-v3/IAaveOracle.sol";
import "./interfaces/ICouponOracle.sol";

contract CouponOracle is ICouponOracle {
    address public immutable override aaveOracle;
    address public immutable override wethAddress;

    constructor(address aaveOracle_, address wethAddress_) {
        aaveOracle = aaveOracle_;
        wethAddress = wethAddress_;
    }

    /**
     * @notice Returns the asset price in the base currency
     * @param asset The address of the asset
     * @return The price of the asset
     */
    function getAssetPrice(address asset) external view returns (uint256) {
        if (asset == address(0)) return IAaveOracle(aaveOracle).getAssetPrice(wethAddress);
        return IAaveOracle(aaveOracle).getAssetPrice(asset);
    }

    /**
     * @notice Returns a list of prices from a list of assets addresses
     * @param assets The list of assets addresses
     * @return The prices of the given assets
     */
    function getAssetsPrices(address[] memory assets) external view returns (uint256[] memory) {
        uint256 length = assets.length;
        for (uint256 i = 0; i < length; ++i) {
            if (assets[i] == address(0)) assets[i] = wethAddress;
        }
        return IAaveOracle(aaveOracle).getAssetsPrices(assets);
    }

    /**
     * @notice Returns a list of prices from a list of assets addresses
     * @param asset1 The address of the first asset
     * @param asset2 The address of the second asset
     * @return The prices of the given assets with eth price
     */
    function getTwoAssetsPricesWithEthPrice(
        address asset1,
        address asset2
    ) external view returns (uint256, uint256, uint256) {
        address[] memory assets = new address[](3);
        assets[0] = asset1;
        assets[1] = asset2;
        assets[2] = wethAddress;

        uint256[] memory prices = IAaveOracle(aaveOracle).getAssetsPrices(assets);

        return (prices[0], prices[1], prices[2]);
    }
}
