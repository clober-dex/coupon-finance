// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "../../../contracts/interfaces/IOracle.sol";

contract MockOracle is IOracle {
    mapping(address => uint256) private _priceMap;

    function getPrice() external view returns (uint256, bool) {
        return (_priceMap[msg.sender], true);
    }

    function setPrice(address token, uint256 price) external {
        _priceMap[token] = price;
    }
}
