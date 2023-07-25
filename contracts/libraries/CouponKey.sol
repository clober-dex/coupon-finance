// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {Epoch} from "./Epoch.sol";

struct CouponKey {
    Epoch epoch;
    address asset;
}

library CouponKeyLibrary {
    function toId(CouponKey memory key) internal pure returns (uint256 id) {
        uint16 epoch = Epoch.unwrap(key.epoch);
        uint160 asset = uint160(key.asset);
        assembly {
            id := add(asset, shl(160, epoch))
        }
    }
}
