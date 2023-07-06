// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {Types} from "../Types.sol";

library CouponKeyLibrary {
    function toId(Types.CouponKey memory key) internal pure returns (uint256) {
        return uint256(bytes32(keccak256(abi.encode(key))));
    }
}

library LoanKeyLibrary {
    function toId(Types.LoanKey memory key) internal pure returns (Types.LoanId) {
        return Types.LoanId.wrap(bytes32(keccak256(abi.encode(key))));
    }
}

library VaultKeyLibrary {
    function toId(Types.VaultKey memory key) internal pure returns (Types.VaultId) {
        return Types.VaultId.wrap(bytes32(keccak256(abi.encode(key))));
    }
}
