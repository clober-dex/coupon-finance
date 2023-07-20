// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {Types} from "../Types.sol";
import {Epoch} from "./Epoch.sol";

library LoanPositionLibrary {
    using Epoch for Types.Epoch;

    function from(
        Types.Epoch expiredWith,
        address collateralToken,
        address debtToken,
        uint256 collateralAmount,
        uint256 debtAmount
    ) internal pure returns (Types.LoanPosition memory position) {
        position = Types.LoanPosition({
            nonce: 0,
            expiredWith: expiredWith,
            collateralToken: collateralToken,
            debtToken: debtToken,
            collateralAmount: collateralAmount,
            debtAmount: debtAmount
        });
    }

    function getAndIncrementNonce(Types.LoanPosition storage positionStorage) internal returns (uint64 nonce) {
        nonce = positionStorage.nonce++;
    }

    function adjustPosition(
        Types.LoanPosition memory position,
        uint256 collateralAmount,
        uint256 debtAmount,
        Types.Epoch expiredWith,
        Types.Epoch minEpoch
    ) internal pure returns (Types.LoanPosition memory adjustedPosition) {
        adjustedPosition = clone(position);

        adjustedPosition.collateralAmount = collateralAmount;
        adjustedPosition.debtAmount = debtAmount;

        if (debtAmount == 0) {
            adjustedPosition.expiredWith = minEpoch;
        } else {
            if (minEpoch.compare(expiredWith) >= 0) {
                expiredWith = minEpoch;
            }
            adjustedPosition.expiredWith = expiredWith;
        }
    }

    function clone(Types.LoanPosition memory position) internal pure returns (Types.LoanPosition memory) {
        return
            Types.LoanPosition({
                nonce: position.nonce,
                expiredWith: position.expiredWith,
                collateralToken: position.collateralToken,
                debtToken: position.debtToken,
                collateralAmount: position.collateralAmount,
                debtAmount: position.debtAmount
            });
    }

    function compareEpoch(
        Types.LoanPosition memory position1,
        Types.LoanPosition memory position2
    ) internal pure returns (int256) {
        return position1.expiredWith.compare(position2.expiredWith);
    }
}
