// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IAaveOracle, IPriceOracleGetter} from "./external/aave-v3/IAaveOracle.sol";
import "./interfaces/ICouponOracle.sol";

contract CouponOracle is ICouponOracle {
    address private immutable _weth;
    address private immutable _oracle;
    address private immutable _fallbackOracle;

    constructor(address weth_, address oracle_, address fallbackOracle_) {
        _weth = weth_;
        _oracle = oracle_;
        _fallbackOracle = fallbackOracle_;
    }

    /**
     * @notice Returns the asset price in the base currency
     * @param asset The address of the asset
     * @return The price of the asset
     */
    function getAssetPrice(address asset) external view returns (uint256) {
        if (asset == address(0)) asset = _weth;
        uint256 price = IAaveOracle(_oracle).getAssetPrice(asset);
        return price == 0 ? IPriceOracleGetter(_fallbackOracle).getAssetPrice(asset) : price;
    }

    /**
     * @notice Returns a list of prices from a list of assets addresses
     * @param assets The list of assets addresses
     * @return prices The prices of the given assets
     */
    function getAssetsPrices(address[] memory assets) external view returns (uint256[] memory prices) {
        uint256 length = assets.length;
        unchecked {
            for (uint256 i = 0; i < length; ++i) {
                if (assets[i] == address(0)) assets[i] = _weth;
            }
            prices = IAaveOracle(_oracle).getAssetsPrices(assets);
            for (uint256 i = 0; i < length; ++i) {
                if (prices[i] == 0) prices[i] = IPriceOracleGetter(_fallbackOracle).getAssetPrice(assets[i]);
            }
        }
    }
}
