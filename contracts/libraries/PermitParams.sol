// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

struct PermitParams {
    uint256 deadline;
    uint8 v;
    bytes32 r;
    bytes32 s;
}

library PermitParamsLibrary {
    function isEmpty(PermitParams memory params) internal pure returns (bool) {
        return params.deadline == 0;
    }
}
