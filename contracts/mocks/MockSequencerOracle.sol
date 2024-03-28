// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {AggregatorV3Interface} from "../external/chainlink/AggregatorV3Interface.sol";

contract MockSequencerOracle is AggregatorV3Interface {
    uint8 public decimals;
    string public description;
    uint256 public version;

    function getRoundData(uint80) external pure returns (uint80, int256, uint256, uint256, uint80) {
        return (0, 0, 0, 0, 0);
    }

    function latestRoundData() external pure returns (uint80, int256, uint256, uint256, uint80) {
        return (0, 0, 0, 0, 0);
    }
}
