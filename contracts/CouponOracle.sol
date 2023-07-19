// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IAaveOracle} from "./external/aave-v3/IAaveOracle.sol";
import "./interfaces/ICouponOracle.sol";

contract CouponOracle is ICouponOracle {
    address public immutable override oracle;
    address public immutable override weth;

    constructor(address oracle_, address weth_) {
        oracle = oracle_;
        weth = weth_;
    }

    /**
     * @notice Returns the asset price in the base currency
     * @param asset The address of the asset
     * @return The price of the asset
     */
    function getAssetPrice(address asset) external view returns (uint256) {
        return IAaveOracle(oracle).getAssetPrice(asset == address(0) ? weth : asset);
    }

    /**
     * @notice Returns a list of prices from a list of assets addresses
     * @param assets The list of assets addresses
     * @return The prices of the given assets
     */
    function getAssetsPrices(address[] memory assets) external view returns (uint256[] memory) {
        uint256 length = assets.length;
        unchecked {
            for (uint256 i = 0; i < length; ++i) {
                if (assets[i] == address(0)) assets[i] = weth;
            }
        }
        return IAaveOracle(oracle).getAssetsPrices(assets);
    }
}
