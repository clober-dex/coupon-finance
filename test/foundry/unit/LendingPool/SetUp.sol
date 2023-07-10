// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Types} from "../../../../contracts/Types.sol";
import {Constants} from "../Constants.sol";
import {IWETH9} from "../../../../contracts/external/weth/IWETH9.sol";
import {ILendingPool} from "../../../../contracts/interfaces/ILendingPool.sol";
import {MockYieldFarmer} from "../../mocks/MockYieldFarmer.sol";
import {MockOracle} from "../../mocks/MockOracle.sol";
import {ForkUtils, ERC20Utils} from "../../Utils.sol";
import {LendingPool} from "../../../../contracts/LendingPool.sol";

library SetUp {
    using ERC20Utils for IERC20;

    struct Result {
        address permitUser;
        IERC20 usdc;
        IWETH9 weth;
        ILendingPool lendingPool;
        MockYieldFarmer yieldFarmer;
        MockOracle oracle;
    }

    function run(Vm vm) internal returns (Result memory) {
        ForkUtils.fork(vm, Constants.FORK_BLOCK_NUMBER);

        Result memory res;
        res.permitUser = vm.addr(1);

        res.weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        res.usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

        res.yieldFarmer = new MockYieldFarmer();
        res.oracle = new MockOracle();
        res.lendingPool = new LendingPool(
            Constants.MAX_EPOCH_DIFF,
            block.timestamp,
            Constants.EPOCH_DURATION,
            address(res.oracle),
            Constants.TREASURY,
            Constants.WETH_ADDRESS,
            address(res.yieldFarmer),
            "baseURI/"
        );

        vm.startPrank(Constants.USDC_WHALE);
        res.usdc.transfer(address(this), res.usdc.amount(1_000_000_000));
        vm.stopPrank();
        vm.deal(address(this), 2_000_000_000 ether);
        res.weth.deposit{value: 1_000_000_000 ether}();

        res.usdc.approve(address(res.lendingPool), type(uint256).max);
        res.weth.approve(address(res.lendingPool), type(uint256).max);

        res.lendingPool.openReserve(
            address(res.usdc),
            Types.AssetConfiguration({
                liquidationThreshold: 800000,
                liquidationBonus: 10000,
                liquidationProtocolFee: 5000
            })
        );
        res.lendingPool.openReserve(
            address(res.weth),
            Types.AssetConfiguration({
                liquidationThreshold: 800000,
                liquidationBonus: 10000,
                liquidationProtocolFee: 5000
            })
        );
        // set oracle
        res.oracle.setAssetPrice(address(res.usdc), 10 ** 8);
        res.oracle.setAssetPrice(address(res.weth), 2000 * 10 ** 8);
        return res;
    }
}
