// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

library Errors {
    string internal constant ACCESS = "ACCESS";
    string internal constant EMPTY_INPUT = "EMPTY_INPUT";
    string internal constant INVALID_INPUT = "INVALID_INPUT";
    string internal constant INVALID_EPOCH = "INVALID_EPOCH";
    string internal constant UNREGISTERED_ASSET = "UNREGISTERED_ASSET";
    string internal constant UNREGISTERED_PAIR = "UNREGISTERED_PAIR";
    string internal constant TOO_SMALL_DEBT = "TOO_SMALL_DEBT";
    string internal constant LIQUIDATION_THRESHOLD = "LIQUIDATION_THRESHOLD";
    string internal constant UNPAID_DEBT = "UNPAID_DEBT";
}
