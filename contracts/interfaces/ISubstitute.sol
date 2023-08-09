// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface ISubstitute {
    function treasury() external view returns (address);

    function mint(uint256 amount, address to) external;

    function burn(uint256 amount, address to) external;

    function mintableAmount() external view returns (uint256);

    function burnableAmount() external view returns (uint256);
}
