// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {BokkyPooBahsDateTimeLibrary} from "./BokkyPooBahsDateTimeLibrary.sol";

type Epoch is uint16;

library EpochLibrary {
    error EpochOverflow();

    uint256 internal constant MONTHS_PER_EPOCH = 1;

    function wrap(uint16 epoch) internal pure returns (Epoch) {
        return Epoch.wrap(epoch);
    }

    function fromMonths(uint256 months) internal pure returns (Epoch) {
        unchecked {
            months /= MONTHS_PER_EPOCH;
        }
        if (months > type(uint16).max) revert EpochOverflow();
        return Epoch.wrap(uint16(months));
    }

    function fromTimestamp(uint256 timestamp) internal pure returns (Epoch) {
        return fromMonths(BokkyPooBahsDateTimeLibrary.diffMonths(0, timestamp));
    }

    function current() internal view returns (Epoch) {
        return fromTimestamp(block.timestamp);
    }

    function isExpired(Epoch epoch) internal view returns (bool) {
        return endTime(epoch) <= block.timestamp;
    }

    function startTime(Epoch epoch) internal pure returns (uint256) {
        unchecked {
            return BokkyPooBahsDateTimeLibrary.addMonths(0, MONTHS_PER_EPOCH * Epoch.unwrap(epoch));
        }
    }

    function endTime(Epoch epoch) internal pure returns (uint256) {
        unchecked {
            uint256 nextEpoch = uint256(Epoch.unwrap(epoch)) + 1;
            return BokkyPooBahsDateTimeLibrary.addMonths(0, MONTHS_PER_EPOCH * nextEpoch);
        }
    }

    function long(Epoch epoch) internal pure returns (uint256) {
        unchecked {
            return endTime(epoch) - startTime(epoch);
        }
    }

    function add(Epoch epoch, uint16 epochs) internal pure returns (Epoch) {
        return Epoch.wrap(Epoch.unwrap(epoch) + epochs);
    }

    function sub(Epoch epoch, uint16 epochs) internal pure returns (Epoch) {
        return Epoch.wrap(Epoch.unwrap(epoch) - epochs);
    }

    function sub(Epoch e1, Epoch e2) internal pure returns (uint16) {
        return Epoch.unwrap(e1) - Epoch.unwrap(e2);
    }

    function unwrap(Epoch epoch) internal pure returns (uint16) {
        return Epoch.unwrap(epoch);
    }

    function compare(Epoch a, Epoch b) internal pure returns (int256) {
        unchecked {
            return
                Epoch.unwrap(a) > Epoch.unwrap(b) ? int256(1) : Epoch.unwrap(a) < Epoch.unwrap(b)
                    ? int256(-1)
                    : int256(0);
        }
    }

    function max(Epoch a, Epoch b) internal pure returns (Epoch) {
        return compare(a, b) > 0 ? a : b;
    }
}
