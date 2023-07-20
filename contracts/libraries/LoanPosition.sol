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
}
