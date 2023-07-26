// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {Epoch} from "./Epoch.sol";

struct CouponKey {
    address asset;
    Epoch epoch;
}

library CouponKeyLibrary {
    function toId(CouponKey memory key) internal pure returns (uint256 id) {
        uint16 epoch = Epoch.unwrap(key.epoch);
        address asset = key.asset;
        assembly {
            id := add(epoch, shl(96, asset))
        }
    }
}
