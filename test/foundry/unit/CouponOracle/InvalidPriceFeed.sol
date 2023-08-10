// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

contract InvalidPriceFeed {
    int256 public price;
    uint8 public decimals = 8;

    function setDecimals(uint8 decimals_) public {
        decimals = decimals_;
    }

    function setPrice(int256 price_) public {
        price = price_;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (0, price, 0, 0, 0);
    }
}
