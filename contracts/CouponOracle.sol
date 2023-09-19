// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {AggregatorV3Interface} from "./external/chainlink/AggregatorV3Interface.sol";
import {ICouponOracle} from "./interfaces/ICouponOracle.sol";
import {IFallbackOracle} from "./interfaces/IFallbackOracle.sol";

contract CouponOracle is ICouponOracle, Ownable {
    uint256 private constant _MAX_TIMEOUT = 1 days;
    uint256 private constant _MIN_TIMEOUT = 1 minutes;
    uint256 private constant _MAX_GRACE_PERIOD = 1 days;
    uint256 private constant _MIN_GRACE_PERIOD = 1 minutes;

    uint256 public override timeout;
    address public override sequencerOracle;
    uint256 public override gracePeriod;
    address public override fallbackOracle;
    mapping(address => address) public override getFeed;

    constructor(address sequencerOracle_, uint256 timeout_, uint256 gracePeriod_) {
        _setSequencerOracle(sequencerOracle_);
        _setTimeout(timeout_);
        _setGracePeriod(gracePeriod_);
    }

    function decimals() external pure returns (uint8) {
        return 8;
    }

    function getAssetPrice(address asset) public view returns (uint256) {
        address feed = getFeed[asset];

        if (feed != address(0)) {
            try AggregatorV3Interface(feed).latestRoundData() returns (
                uint80 roundId, int256 answer, uint256, /* startedAt */ uint256 updatedAt, uint80 /* answeredInRound */
            ) {
                // Check Sanity, Staleness and the Sequencer
                if (
                    roundId != 0 && answer >= 0 && updatedAt <= block.timestamp
                        && block.timestamp <= updatedAt + timeout && _isSequencerValid()
                ) {
                    return uint256(answer);
                }
            } catch {}
        }
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

    function isSequencerValid() external view returns (bool) {
        return _isSequencerValid();
    }

    function setFallbackOracle(address newFallbackOracle) external onlyOwner {
        fallbackOracle = newFallbackOracle;
        emit SetFallbackOracle(newFallbackOracle);
    }

    function setFeeds(address[] memory assets, address[] memory feeds) external onlyOwner {
        if (assets.length != feeds.length) revert LengthMismatch();
        unchecked {
            for (uint256 i = 0; i < assets.length; ++i) {
                if (AggregatorV3Interface(feeds[i]).decimals() != 8) revert InvalidDecimals();
                if (getFeed[assets[i]] != address(0)) revert AssetFeedAlreadySet();
                getFeed[assets[i]] = feeds[i];
                emit SetFeed(assets[i], feeds[i]);
            }
        }
    }

    function setSequencerOracle(address newSequencerOracle) external onlyOwner {
        _setSequencerOracle(newSequencerOracle);
    }

    function _setSequencerOracle(address newSequencerOracle) internal {
        sequencerOracle = newSequencerOracle;
        emit SetSequencerOracle(newSequencerOracle);
    }

    function setTimeout(uint256 newTimeout) external onlyOwner {
        _setTimeout(newTimeout);
    }

    function _setTimeout(uint256 newTimeout) internal {
        if (newTimeout < _MIN_TIMEOUT || newTimeout > _MAX_TIMEOUT) revert InvalidTimeout();
        timeout = newTimeout;
        emit SetTimeout(newTimeout);
    }

    function setGracePeriod(uint256 newGracePeriod) external onlyOwner {
        _setGracePeriod(newGracePeriod);
    }

    function _setGracePeriod(uint256 newGracePeriod) internal {
        if (newGracePeriod < _MIN_GRACE_PERIOD || newGracePeriod > _MAX_GRACE_PERIOD) revert InvalidGracePeriod();
        gracePeriod = newGracePeriod;
        emit SetGracePeriod(newGracePeriod);
    }

    function _isSequencerValid() internal view returns (bool) {
        (, int256 answer,, uint256 updatedAt,) = AggregatorV3Interface(sequencerOracle).latestRoundData();
        return answer == 0 && block.timestamp - updatedAt > gracePeriod;
    }
}
