// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {Constants} from "../Constants.sol";
import {IAaveOracle} from "../../../contracts/external/aave-v3/IAaveOracle.sol";
import {IPoolAddressesProvider} from "../../../contracts/external/aave-v3/IPoolAddressesProvider.sol";

contract MockOracle is IAaveOracle {
    address private _weth;

    mapping(address => uint256) private _priceMap;

    constructor(address weth_) {
        _weth = weth_;
    }

    function getAssetPrice(address asset) external view override returns (uint256) {
        return asset == address(0) ? _priceMap[_weth] : _priceMap[asset];
    }

    function getAssetsPrices(address[] calldata assets) external view returns (uint256[] memory prices) {
        uint256 length = assets.length;
        prices = new uint256[](length);
        unchecked {
            for (uint256 i = 0; i < length; ++i) {
                prices[i] = assets[i] == address(0) ? _priceMap[_weth] : _priceMap[assets[i]];
            }
        }
    }

    function setAssetPrice(address asset, uint256 price) external {
        _priceMap[asset] = price;
    }

    function BASE_CURRENCY() external view returns (address) {
        revert("not implemented");
    }

    function BASE_CURRENCY_UNIT() external view returns (uint256) {
        revert("not implemented");
    }

    function ADDRESSES_PROVIDER() external view returns (IPoolAddressesProvider) {
        revert("not implemented");
    }

    function setAssetSources(address[] calldata assets, address[] calldata sources) external {
        revert("not implemented");
    }

    function setFallbackOracle(address fallbackOracle) external {
        revert("not implemented");
    }

    function getSourceOfAsset(address asset) external view returns (address) {
        revert("not implemented");
    }

    function getFallbackOracle() external view returns (address) {
        revert("not implemented");
    }
}
