// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {IFallbackOracle} from "../../../../contracts/interfaces/IFallbackOracle.sol";

contract MockFallbackOracle is IFallbackOracle {
    uint256 public constant FALLBACK_PRICE = 123 * 1e8;

    function getAssetPrice(address) external pure returns (uint256) {
        return FALLBACK_PRICE;
    }
}
