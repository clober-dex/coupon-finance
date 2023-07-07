// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "../Constants.sol";
import "../../ForkTestSetUp.sol";
import "../../../../contracts/external/weth/IWETH9.sol";
import "../../../../contracts/interfaces/ILendingPool.sol";
import "../../mocks/MockYieldFarmer.sol";
import "../../mocks/MockOracle.sol";
import "../../Utils.sol";

library SetUp {
    using ERC20Utils for IERC20;

    struct Result {
        address unapprovedUser;
        IERC20 usdc;
        IWETH9 weth;
        ILendingPool lendingPool;
        MockYieldFarmer yieldFarmer;
        MockOracle oracle;
    }

    function run(Vm vm) internal returns (Result memory) {
        ForkTestSetUp forkSetUp = new ForkTestSetUp();
        forkSetUp.fork(Constants.FORK_BLOCK_NUMBER);

        Result memory res;
        res.unapprovedUser = vm.addr(1);

        res.weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        res.usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

        res.yieldFarmer = new MockYieldFarmer();
        res.oracle = new MockOracle();
        // res.lendingPool = new LendingPool();

        vm.prank(Constants.USDC_WHALE);
        res.usdc.transfer(address(this), res.usdc.amount(1_000_000_000));
        vm.deal(address(this), 2_000_000_000 ether);
        res.weth.deposit{value: 1_000_000_000 ether}();

        res.usdc.approve(address(res.lendingPool), type(uint256).max);
        res.weth.approve(address(res.lendingPool), type(uint256).max);

        // set oracle
        res.oracle.setPrice(address(res.usdc), 10 ** 18);
        res.oracle.setPrice(address(res.weth), 2000 * 10 ** 18);
        return res;
    }
}
