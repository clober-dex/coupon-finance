// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

library Constants {
    uint256 internal constant FORK_BLOCK_NUMBER = 115711526;
    address internal constant TREASURY = address(0xc0f1);
    address internal constant USER1 = address(0x1);
    address internal constant USER2 = address(0x2);
    address internal constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address internal constant WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
    address internal constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address internal constant USDC_WHALE = 0xB38e8c17e38363aF6EbdCb3dAE12e0243582891D;
    address internal constant AAVE_V3_POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address internal constant WRAPPED1155_FACTORY = 0xfcBE16BfD991E4949244E59d9b524e6964b8BB75;
    address internal constant CLOBER_FACTORY = 0x24aC0938C010Fb520F1068e96d78E0458855111D;
    bytes32 internal constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
}
