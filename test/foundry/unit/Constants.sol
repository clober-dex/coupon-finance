// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

library Constants {
    uint256 internal constant FORK_BLOCK_NUMBER = 17617512;
    address internal constant USER1 = address(0x1);
    address internal constant USER2 = address(0x2);
    address internal constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDC_WHALE = 0xcEe284F754E854890e311e3280b767F80797180d;
    bytes32 internal constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
}
