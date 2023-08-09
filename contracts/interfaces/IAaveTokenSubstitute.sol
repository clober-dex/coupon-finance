// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ISubstitute} from "./ISubstitute.sol";

interface IAaveTokenSubstitute is ISubstitute {
    function mintByAToken(uint256 amount, address to) external;

    function burnToAToken(uint256 amount, address to) external;
}