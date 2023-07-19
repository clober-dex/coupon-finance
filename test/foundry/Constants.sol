// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

library Constants {
    uint256 internal constant MAX_EPOCH_DIFF = 10;
    uint256 internal constant EPOCH_DURATION = 180 days;
    uint256 internal constant FORK_BLOCK_NUMBER = 17617512;
    address internal constant TREASURY = address(0xc0f1);
    address internal constant USER1 = address(0x1);
    address internal constant USER2 = address(0x2);
    address internal constant MOCK_WETH = 0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDC_WHALE = 0xcEe284F754E854890e311e3280b767F80797180d;
    bytes32 internal constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
}
