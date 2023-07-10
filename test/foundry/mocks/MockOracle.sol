// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "../../../contracts/external/aave-v3/IPriceOracleGetter.sol";

contract MockOracle is IPriceOracleGetter {
    mapping(address => uint256) private _priceMap;

    function BASE_CURRENCY() external view returns (address) {
        return address(0);
    }

    function BASE_CURRENCY_UNIT() external view returns (uint256) {
        return 100000000;
    }

    function getAssetPrice(address asset) external view override returns (uint256) {
        return _priceMap[asset];
    }

    function setAssetPrice(address asset, uint256 price) external {
        _priceMap[asset] = price;
    }
}
