// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {Constants} from "../Constants.sol";
import {ICouponOracle} from "../../../contracts/interfaces/ICouponOracle.sol";

contract MockOracle is ICouponOracle {
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
}
