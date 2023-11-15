// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

library Constants {
    uint256 internal constant FORK_BLOCK_NUMBER = 120322223;
    address internal constant TREASURY = address(0xc0f1);
    address internal constant USER1 = address(0x1);
    address internal constant USER2 = address(0x2);
    address internal constant CHAINLINK_SEQUENCER_ORACLE = 0xFdB631F5EE196F0ed6FAa767959853A9F217697D;
    address internal constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address internal constant WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
    address internal constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    // https://docs.chain.link/data-feeds/price-feeds/addresses?network=arbitrum
    address internal constant ETH_CHAINLINK_FEED = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
    address internal constant USDC_CHAINLINK_FEED = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
}
