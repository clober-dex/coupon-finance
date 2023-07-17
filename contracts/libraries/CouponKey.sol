// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {Types} from "../Types.sol";

library CouponKey {
    function toId(Types.CouponKey memory key) internal pure returns (uint256) {
        return uint256(bytes32(keccak256(abi.encode(key))));
    }
}
