// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {ILendingPool} from "../interfaces/ILendingPool.sol";

library CouponKeyLibrary {
    function toId(ILendingPool.CouponKey memory key) internal pure returns (uint256) {
        return uint256(bytes32(keccak256(abi.encode(key))));
    }
}

type LoanId is bytes32;

library LoanKeyLibrary {
    function toId(ILendingPool.LoanKey memory key) internal pure returns (LoanId) {
        return LoanId.wrap(bytes32(keccak256(abi.encode(key))));
    }
}

type VaultId is bytes32;

library VaultKeyLibrary {
    function toId(ILendingPool.VaultKey memory key) internal pure returns (VaultId) {
        return VaultId.wrap(bytes32(keccak256(abi.encode(key))));
    }
}
