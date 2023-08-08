// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {Create1} from "@clober/library/contracts/Create1.sol";

import {CouponManager} from "../../../../../contracts/CouponManager.sol";
import {BondPositionManager} from "../../../../../contracts/BondPositionManager.sol";
import {IBondPositionManager} from "../../../../../contracts/interfaces/IBondPositionManager.sol";
import {ICouponManager} from "../../../../../contracts/interfaces/ICouponManager.sol";
import {Epoch, EpochLibrary} from "../../../../../contracts/libraries/Epoch.sol";
import {MockERC20} from "../../../mocks/MockERC20.sol";
import {MockAssetPool} from "../../../mocks/MockAssetPool.sol";
import {Utils} from "../../../Utils.sol";

library TestInitializer {
    using EpochLibrary for Epoch;

    struct Params {
        MockERC20 usdc;
        MockAssetPool assetPool;
        ICouponManager couponManager;
        IBondPositionManager bondPositionManager;
        Epoch startEpoch;
        uint256 initialAmount;
    }

    function init(Vm vm) internal returns (Params memory) {
        Params memory p;
        p.usdc = new MockERC20("USD coin", "USDC", 6);

        p.usdc.mint(address(this), p.usdc.amount(1_000_000_000));

        vm.warp(EpochLibrary.wrap(10).startTime());
        p.startEpoch = EpochLibrary.current();

        p.initialAmount = p.usdc.amount(100);
        p.assetPool = new MockAssetPool();
        uint64 thisNonce = vm.getNonce(address(this));
        p.couponManager = new CouponManager(Utils.toArr(Create1.computeAddress(address(this), thisNonce + 1)), "URI/");
        p.bondPositionManager = new BondPositionManager(
            address(p.couponManager),
            address(p.assetPool),
            "bond/position/uri/",
            Utils.toArr(address(p.usdc))
        );

        p.usdc.approve(address(p.bondPositionManager), type(uint256).max);
        return p;
    }
}
