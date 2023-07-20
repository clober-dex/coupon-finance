// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {Types} from "../Types.sol";
import {Epoch} from "./Epoch.sol";

library BondPositionLibrary {
    using Epoch for Types.Epoch;

    function from(
        address asset,
        Types.Epoch expiredWith,
        uint256 amount
    ) internal pure returns (Types.BondPosition memory position) {
        position = Types.BondPosition({asset: asset, nonce: 0, expiredWith: expiredWith, amount: amount});
    }

    function getAndIncrementNonce(Types.BondPosition storage positionStorage) internal returns (uint64 nonce) {
        nonce = positionStorage.nonce++;
    }

    function adjustPosition(
        Types.BondPosition memory position,
        uint256 amount,
        Types.Epoch expiredWith,
        Types.Epoch minEpoch
    ) internal pure returns (Types.BondPosition memory adjustedPosition) {
        adjustedPosition = clone(position);

        adjustedPosition.amount = amount;

        if (amount == 0) {
            adjustedPosition.expiredWith = minEpoch;
        } else {
            if (minEpoch.compare(expiredWith) >= 0) {
                expiredWith = minEpoch;
            }
            adjustedPosition.expiredWith = expiredWith;
        }
    }

    function clone(Types.BondPosition memory position) internal pure returns (Types.BondPosition memory) {
        return
            Types.BondPosition({
                asset: position.asset,
                nonce: position.nonce,
                expiredWith: position.expiredWith,
                amount: position.amount
            });
    }

    function compareEpoch(
        Types.BondPosition memory position1,
        Types.BondPosition memory position2
    ) internal pure returns (int256) {
        return position1.expiredWith.compare(position2.expiredWith);
    }
}
