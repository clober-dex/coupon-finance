// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {AggregatorV3Interface} from "./external/chainlink/AggregatorV3Interface.sol";
import {ICouponOracle} from "./interfaces/ICouponOracle.sol";
import {IFallbackOracle} from "./interfaces/IFallbackOracle.sol";

contract CouponOracle is ICouponOracle, Ownable {
    address public override fallbackOracle;
    mapping(address => address) private _assetFeedMap;

    constructor(address[] memory assets, address[] memory feeds) {
        _setFeeds(assets, feeds);
    }

    function decimals() external pure returns (uint8) {
        return 8;
    }

    function getFeed(address asset) external view returns (address) {
        return _assetFeedMap[asset];
    }

    function getAssetPrice(address asset) public view returns (uint256) {
        address feed = _assetFeedMap[asset];

        if (feed != address(0)) {
            (, int256 price,,,) = AggregatorV3Interface(feed).latestRoundData();
            if (price > 0) {
                return uint256(price);
            }
        }
        return _fallback(asset);
    }

    function _fallback(address asset) internal view returns (uint256) {
        return IFallbackOracle(fallbackOracle).getAssetPrice(asset);
    }

    function getAssetsPrices(address[] memory assets) external view returns (uint256[] memory prices) {
        prices = new uint256[](assets.length);
        unchecked {
            for (uint256 i = 0; i < assets.length; ++i) {
                prices[i] = getAssetPrice(assets[i]);
            }
        }
    }

    function setFallbackOracle(address newFallbackOracle) external onlyOwner {
        fallbackOracle = newFallbackOracle;
    }

    function setFeeds(address[] memory assets, address[] memory feeds) external onlyOwner {
        _setFeeds(assets, feeds);
    }

    function _setFeeds(address[] memory assets, address[] memory feeds) internal {
        if (assets.length != feeds.length) revert LengthMismatch();
        unchecked {
            for (uint256 i = 0; i < assets.length; ++i) {
                if (AggregatorV3Interface(feeds[i]).decimals() != 8) revert InvalidDecimals();
                if (_assetFeedMap[assets[i]] != address(0)) revert AssetFeedAlreadySet();
                _assetFeedMap[assets[i]] = feeds[i];
            }
        }
    }
}
