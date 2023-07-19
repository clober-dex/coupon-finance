// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {IPriceOracleGetter} from "../../../contracts/external/aave-v3/IPriceOracleGetter.sol";
import {Constants} from "../Constants.sol";

contract MockOracle is IPriceOracleGetter {
    mapping(address => uint256) private _priceMap;

    function BASE_CURRENCY() external pure returns (address) {
        return address(0);
    }

    function BASE_CURRENCY_UNIT() external pure returns (uint256) {
        return 100000000;
    }

    function getAssetPrice(address asset) external view override returns (uint256) {
        return asset == address(0) ? _priceMap[Constants.MOCK_WETH] : _priceMap[asset];
    }

    function getAssetsPrices(address[] calldata assets) external view returns (uint256[] memory prices) {
        uint256 length = assets.length;
        prices = new uint256[](length);
        unchecked {
            for (uint256 i = 0; i < length; ++i) {
                prices[i] = assets[i] == address(0) ? _priceMap[Constants.MOCK_WETH] : _priceMap[assets[i]];
            }
        }
    }

    function setAssetPrice(address asset, uint256 price) external {
        _priceMap[asset] = price;
    }
}
