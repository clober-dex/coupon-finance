// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import "../interfaces/ILendingPool.sol";

library CouponKeyLibrary {
    function toId(ILendingPool.CouponKey memory key) internal pure returns (bytes32) {
        return bytes32(keccak256(abi.encode(key)));
    }
}

library LoanKeyLibrary {
    function toId(ILendingPool.LoanKey memory key) internal pure returns (bytes32) {
        return bytes32(keccak256(abi.encode(key)));
    }
}
