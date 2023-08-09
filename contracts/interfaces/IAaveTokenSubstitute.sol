// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IAaveTokenSubstitute {
    function mint(uint256 amount, address to) external;

    function burn(uint256 amount, address to) external;
}
