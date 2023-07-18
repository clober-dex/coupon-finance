// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {Types} from "../Types.sol";
import {Epoch} from "./Epoch.sol";

library Bond {
    using Epoch for Types.Epoch;

    function from(
        address asset,
        Types.Epoch expiredWith,
        uint256 amount
    ) internal pure returns (Types.Bond memory bond) {
        bond = Types.Bond({asset: asset, nonce: 0, expiredWith: expiredWith, amount: amount});
    }

    function getAndIncrementNonce(Types.Bond storage bondStorage) internal returns (uint64 nonce) {
        nonce = bondStorage.nonce++;
    }

    function adjustPosition(
        Types.Bond memory bond,
        int256 amount,
        int16 lockEpochs,
        Types.Epoch minEpoch
    ) internal pure returns (Types.Bond memory adjustedBond) {
        adjustedBond = clone(bond);

        adjustedBond.amount = amount > 0
            ? adjustedBond.amount + uint256(amount)
            : adjustedBond.amount - uint256(-amount);

        if (adjustedBond.amount == 0) {
            adjustedBond.expiredWith = minEpoch;
        } else {
            adjustedBond.expiredWith = lockEpochs > 0
                ? adjustedBond.expiredWith.add(uint16(lockEpochs))
                : adjustedBond.expiredWith.sub(uint16(-lockEpochs));
            if (minEpoch.compare(adjustedBond.expiredWith) >= 0) {
                adjustedBond.expiredWith = minEpoch;
            }
        }
    }

    function clone(Types.Bond memory bond) internal pure returns (Types.Bond memory) {
        return Types.Bond({asset: bond.asset, nonce: bond.nonce, expiredWith: bond.expiredWith, amount: bond.amount});
    }

    function compareEpoch(Types.Bond memory bond1, Types.Bond memory bond2) internal pure returns (int256) {
        return bond1.expiredWith.compare(bond2.expiredWith);
    }
}
