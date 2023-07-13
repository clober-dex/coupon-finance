// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

library Errors {
    bytes internal constant UNREGISTERED_ASSET = "UNREGISTERED_ASSET";
    bytes internal constant TOO_SMALL_DEBT = "TOO_SMALL_DEBT";
    bytes internal constant LIQUIDATION_THRESHOLD = "LIQUIDATION_THRESHOLD";
}