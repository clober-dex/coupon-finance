// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {Types} from "../Types.sol";
import {BokkyPooBahsDateTimeLibrary} from "./BokkyPooBahsDateTimeLibrary.sol";

library Epoch {
    function fromMonths(uint256 months) internal pure returns (Types.Epoch) {
        if (months > type(uint16).max) revert("Epoch: Overflow");
        return Types.Epoch.wrap(uint16(months));
    }

    function fromTimestamp(uint256 timestamp) internal pure returns (Types.Epoch) {
        return fromMonths(BokkyPooBahsDateTimeLibrary.diffMonths(0, timestamp));
    }

    function current() internal view returns (Types.Epoch) {
        return fromTimestamp(block.timestamp);
    }

    function startTime(Types.Epoch epoch) internal pure returns (uint256) {
        return BokkyPooBahsDateTimeLibrary.addMonths(0, Types.Epoch.unwrap(epoch));
    }

    function endTime(Types.Epoch epoch) internal pure returns (uint256) {
        unchecked {
            uint256 nextEpoch = Types.Epoch.unwrap(epoch) + 1;
            return BokkyPooBahsDateTimeLibrary.addMonths(0, nextEpoch);
        }
    }

    function long(Types.Epoch epoch) internal pure returns (uint256) {
        unchecked {
            return endTime(epoch) - startTime(epoch);
        }
    }

    function add(Types.Epoch epoch, uint256 months) internal pure returns (Types.Epoch) {
        unchecked {
            return fromMonths(months + Types.Epoch.unwrap(epoch));
        }
    }

    function sub(Types.Epoch epoch, uint256 months) internal pure returns (Types.Epoch) {
        return fromMonths(Types.Epoch.unwrap(epoch) - months);
    }

    function unwrap(Types.Epoch epoch) internal pure returns (uint16) {
        return Types.Epoch.unwrap(epoch);
    }

    function compare(Types.Epoch a, Types.Epoch b) internal pure returns (int256) {
        unchecked {
            return
                Types.Epoch.unwrap(a) > Types.Epoch.unwrap(b)
                    ? int256(1)
                    : Types.Epoch.unwrap(a) < Types.Epoch.unwrap(b)
                    ? int256(-1)
                    : int256(0);
        }
    }
}
