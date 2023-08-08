// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {Create1} from "@clober/library/contracts/Create1.sol";

import {Epoch, EpochLibrary} from "../../../../../contracts/libraries/Epoch.sol";
import {ILoanPositionManager} from "../../../../../contracts/interfaces/ILoanPositionManager.sol";
import {ICouponManager} from "../../../../../contracts/interfaces/ICouponManager.sol";
import {MockAssetPool} from "../../../mocks/MockAssetPool.sol";
import {MockOracle} from "../../../mocks/MockOracle.sol";
import {MockERC20} from "../../../mocks/MockERC20.sol";
import {Constants} from "../../../Constants.sol";
import {CouponManager} from "../../../../../contracts/CouponManager.sol";
import {LoanPositionManager} from "../../../../../contracts/LoanPositionManager.sol";
import {Utils} from "../../../Utils.sol";

library TestInitializer {
    using EpochLibrary for Epoch;

    struct Params {
        MockERC20 weth;
        MockERC20 usdc;
        MockOracle oracle;
        MockAssetPool assetPool;
        ICouponManager couponManager;
        ILoanPositionManager loanPositionManager;
        Epoch startEpoch;
        uint256 initialCollateralAmount;
        uint256 initialDebtAmount;
    }

    function init(Vm vm) internal returns (Params memory) {
        Params memory p;
        p.weth = new MockERC20("Collateral Token", "COL", 18);
        p.usdc = new MockERC20("USD coin", "USDC", 6);

        p.weth.mint(address(this), p.weth.amount(2_000_000_000));
        p.usdc.mint(address(this), p.usdc.amount(2_000_000_000));

        p.assetPool = new MockAssetPool();
        p.oracle = new MockOracle(address(p.weth));
        uint64 thisNonce = vm.getNonce(address(this));
        p.couponManager =
            new CouponManager(Utils.toArr(address(this), Create1.computeAddress(address(this), thisNonce + 1)), "URI/");
        p.loanPositionManager = new LoanPositionManager(
            address(p.couponManager),
            address(p.assetPool),
            address(p.oracle),
            Constants.TREASURY,
            10 ** 16,
            ""
        );
        p.loanPositionManager.setLoanConfiguration(address(p.usdc), address(p.weth), 800000, 20000, 5000, 700000);
        p.loanPositionManager.setLoanConfiguration(address(p.weth), address(p.usdc), 800000, 20000, 5000, 700000);

        p.weth.approve(address(p.loanPositionManager), type(uint256).max);
        p.usdc.approve(address(p.loanPositionManager), type(uint256).max);
        p.weth.transfer(address(p.assetPool), p.weth.amount(1_000_000_000));
        p.usdc.transfer(address(p.assetPool), p.usdc.amount(1_000_000_000));
        p.assetPool.deposit(address(p.weth), p.weth.amount(1_000_000_000));
        p.assetPool.deposit(address(p.usdc), p.usdc.amount(1_000_000_000));

        p.oracle.setAssetPrice(address(p.weth), 1800 * 10 ** 8);
        p.oracle.setAssetPrice(address(p.usdc), 10 ** 8);

        p.startEpoch = EpochLibrary.current();

        p.initialCollateralAmount = p.weth.amount(10);
        p.initialDebtAmount = p.usdc.amount(100);

        return p;
    }
}
