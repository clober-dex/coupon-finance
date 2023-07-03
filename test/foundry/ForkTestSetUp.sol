pragma solidity ^0.8.0;

import "forge-std/Test.sol";

contract ForkTestSetUp is Test {
    function fork(uint256 blockNumber) public {
        uint256 fork = vm.createFork(vm.envString("FORK_TEST_NODE_URL"));
        vm.selectFork(fork);
        vm.rollFork(blockNumber);
        assertEq(vm.activeFork(), fork);
        assertEq(block.number, blockNumber);
    }
}
