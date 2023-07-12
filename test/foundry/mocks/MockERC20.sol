// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    uint8 private immutable _decimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _decimals = decimals_;
    }

    function mint(address account, uint256 value) external {
        _mint(account, value);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function amount(uint256 value) external view returns (uint256) {
        return value * (10 ** _decimals);
    }
}
