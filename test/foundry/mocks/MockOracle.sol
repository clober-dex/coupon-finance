// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {Constants} from "../Constants.sol";
import {ICouponOracle} from "../../../contracts/interfaces/ICouponOracle.sol";

contract MockOracle is ICouponOracle {
    uint256 public override gracePeriod;
    address public override sequencerOracle;
    address private _weth;

    mapping(address => uint256) private _priceMap;

    constructor(address weth_) {
        _weth = weth_;
    }

    function decimals() external pure returns (uint8) {
        return 8;
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

    function isSequencerValid() external pure returns (bool) {
        return true;
    }

    function setAssetPrice(address asset, uint256 price) external {
        _priceMap[asset] = price;
    }

    function fallbackOracle() external pure returns (address) {
        return address(0);
    }

    function getFeed(address) external pure returns (address) {
        return address(0);
    }

    function setFallbackOracle(address) external {}

    function setFeeds(address[] memory, address[] memory) external {}

    function setSequencerOracle(address) external {}

    function setGracePeriod(uint256) external {}
}
