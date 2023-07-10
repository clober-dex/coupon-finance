// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {Types} from "../../../../contracts/Types.sol";
import {ILendingPoolEvents} from "../../../../contracts/interfaces/ILendingPool.sol";
import {CouponKeyLibrary} from "../../../../contracts/libraries/Keys.sol";
import {ERC20Utils, Utils} from "../../Utils.sol";
import {Constants} from "../Constants.sol";
import {SetUp} from "./SetUp.sol";

contract LendingPoolMintCouponsUnitTest is Test, ILendingPoolEvents, ERC1155Holder {
    using ERC20Utils for IERC20;
    using CouponKeyLibrary for Types.CouponKey;

    SetUp.Result public r;

    function setUp() public {
        r = SetUp.run(vm);
    }

    function testMintCoupons() public {
        uint256 amount = r.usdc.amount(100);
        r.lendingPool.deposit(address(r.usdc), amount, address(this));
        amount /= 2;

        Types.CouponKey memory couponKey = Types.CouponKey({asset: address(r.usdc), epoch: 1});
        uint256 couponId = couponKey.toId();

        Types.ReserveStatus memory beforeReserve = r.lendingPool.getReserveStatus(address(r.usdc));
        Types.VaultStatus memory beforeVault = r.lendingPool.getVaultStatus(
            Types.VaultKey(address(r.usdc), address(this))
        );
        uint256 beforeCouponBalance = r.lendingPool.balanceOf(Constants.USER1, couponId);
        uint256 beforeCouponTotalSupply = r.lendingPool.totalSupply(couponId);

        r.lendingPool.mintCoupons(Utils.toArray(Types.Coupon(couponKey, amount)), Constants.USER1);

        Types.ReserveStatus memory afterReserve = r.lendingPool.getReserveStatus(address(r.usdc));
        Types.VaultStatus memory afterVault = r.lendingPool.getVaultStatus(
            Types.VaultKey(address(r.usdc), address(this))
        );
        uint256 afterCouponBalance = r.lendingPool.balanceOf(Constants.USER1, couponId);
        uint256 afterCouponTotalSupply = r.lendingPool.totalSupply(couponId);

        assertEq(beforeReserve.lockedAmount + amount, afterReserve.lockedAmount, "RESERVE_LOCKED");
        assertEq(beforeReserve.spendableAmount, afterReserve.spendableAmount + amount, "RESERVE_SPENDABLE");
        assertEq(beforeVault.lockedAmount + amount, afterVault.lockedAmount, "VAULT_LOCKED");
        assertEq(beforeVault.spendableAmount, afterVault.spendableAmount + amount, "VAULT_SPENDABLE");
        assertEq(beforeCouponBalance + amount, afterCouponBalance, "COUPON_BALANCE");
        assertEq(beforeCouponTotalSupply + amount, afterCouponTotalSupply, "COUPON_TOTAL_SUPPLY");
    }

    function testWithdrawWithUnregisteredToken() public {
        vm.expectRevert("Unregistered asset");
        r.lendingPool.mintCoupons(
            Utils.toArray(Types.Coupon(Types.CouponKey({asset: address(0x123), epoch: 1}), 10000)),
            Constants.USER1
        );
    }

    function testMintCouponsWhenAmountExceedsDepositedAmount() public {
        uint256 amount = r.usdc.amount(100);
        r.lendingPool.deposit(address(r.usdc), amount, address(this));

        Types.CouponKey memory couponKey = Types.CouponKey({asset: address(r.usdc), epoch: 1});
        uint256 couponId = couponKey.toId();

        Types.ReserveStatus memory beforeReserve = r.lendingPool.getReserveStatus(address(r.usdc));
        Types.VaultStatus memory beforeVault = r.lendingPool.getVaultStatus(
            Types.VaultKey(address(r.usdc), address(this))
        );
        uint256 beforeCouponBalance = r.lendingPool.balanceOf(Constants.USER1, couponId);
        uint256 beforeCouponTotalSupply = r.lendingPool.totalSupply(couponId);

        r.lendingPool.mintCoupons(Utils.toArray(Types.Coupon(couponKey, amount * 2)), Constants.USER1);

        Types.ReserveStatus memory afterReserve = r.lendingPool.getReserveStatus(address(r.usdc));
        Types.VaultStatus memory afterVault = r.lendingPool.getVaultStatus(
            Types.VaultKey(address(r.usdc), address(this))
        );
        uint256 afterCouponBalance = r.lendingPool.balanceOf(Constants.USER1, couponId);
        uint256 afterCouponTotalSupply = r.lendingPool.totalSupply(couponId);

        assertEq(beforeReserve.lockedAmount + amount, afterReserve.lockedAmount, "RESERVE_LOCKED");
        assertEq(beforeReserve.spendableAmount, afterReserve.spendableAmount + amount, "RESERVE_SPENDABLE");
        assertEq(beforeVault.lockedAmount + amount, afterVault.lockedAmount, "VAULT_LOCKED");
        assertEq(beforeVault.spendableAmount, afterVault.spendableAmount + amount, "VAULT_SPENDABLE");
        assertEq(beforeCouponBalance + amount, afterCouponBalance, "COUPON_BALANCE");
        assertEq(beforeCouponTotalSupply + amount, afterCouponTotalSupply, "COUPON_TOTAL_SUPPLY");
    }

    function testMintCouponsWhenEpochTooBig() public {
        uint256 amount = r.usdc.amount(100);
        r.lendingPool.deposit(address(r.usdc), amount, address(this));

        Types.CouponKey memory couponKey = Types.CouponKey({
            asset: address(r.usdc),
            epoch: r.lendingPool.maxEpoch() + 1
        });

        vm.expectRevert("Epoch too big");
        r.lendingPool.mintCoupons(Utils.toArray(Types.Coupon(couponKey, amount)), Constants.USER1);
    }

    function testMintCouponsLockedAmountChanges() public {
        uint256 amount0 = r.usdc.amount(50);
        uint256 amount1 = r.usdc.amount(70);
        uint256 amount2 = r.usdc.amount(100);
        r.lendingPool.deposit(address(r.usdc), amount0 + amount1 + amount2, address(this));

        Types.CouponKey memory couponKey1 = Types.CouponKey({asset: address(r.usdc), epoch: 1});
        Types.CouponKey memory couponKey2 = Types.CouponKey({asset: address(r.usdc), epoch: 2});

        r.lendingPool.mintCoupons(Utils.toArray(Types.Coupon(couponKey1, amount1)), address(this));
        r.lendingPool.mintCoupons(Utils.toArray(Types.Coupon(couponKey2, amount2)), address(this));

        // epoch 1
        Types.ReserveStatus memory reserve = r.lendingPool.getReserveStatus(address(r.usdc));
        Types.VaultStatus memory vault = r.lendingPool.getVaultStatus(Types.VaultKey(address(r.usdc), address(this)));
        assertEq(reserve.lockedAmount, amount1 + amount2, "RESERVE_LOCKED");
        assertEq(reserve.spendableAmount, amount0, "RESERVE_SPENDABLE");
        assertEq(vault.lockedAmount, amount1 + amount2, "VAULT_LOCKED");
        assertEq(vault.spendableAmount, amount0, "VAULT_SPENDABLE");

        vm.warp(block.timestamp + r.lendingPool.epochDuration());

        // epoch 2
        reserve = r.lendingPool.getReserveStatus(address(r.usdc));
        vault = r.lendingPool.getVaultStatus(Types.VaultKey(address(r.usdc), address(this)));
        assertEq(reserve.lockedAmount, amount2, "RESERVE_LOCKED");
        assertEq(reserve.spendableAmount, amount0 + amount1, "RESERVE_SPENDABLE");
        assertEq(vault.lockedAmount, amount2, "VAULT_LOCKED");
        assertEq(vault.spendableAmount, amount0 + amount1, "VAULT_SPENDABLE");

        vm.warp(block.timestamp + r.lendingPool.epochDuration());

        // epoch 3
        reserve = r.lendingPool.getReserveStatus(address(r.usdc));
        vault = r.lendingPool.getVaultStatus(Types.VaultKey(address(r.usdc), address(this)));
        assertEq(reserve.lockedAmount, 0, "RESERVE_LOCKED");
        assertEq(reserve.spendableAmount, amount0 + amount1 + amount2, "RESERVE_SPENDABLE");
        assertEq(vault.lockedAmount, 0, "VAULT_LOCKED");
        assertEq(vault.spendableAmount, amount0 + amount1 + amount2, "VAULT_SPENDABLE");

        assertEq(r.lendingPool.getReserveLockedAmount(address(r.usdc), 1), amount1 + amount2, "RESERVE_LOCKED_1");
        assertEq(r.lendingPool.getReserveLockedAmount(address(r.usdc), 2), amount2, "RESERVE_LOCKED_2");
        assertEq(r.lendingPool.getReserveLockedAmount(address(r.usdc), 3), 0, "RESERVE_LOCKED_3");
        assertEq(
            r.lendingPool.getVaultLockedAmount(Types.VaultKey(address(r.usdc), address(this)), 1),
            amount1 + amount2,
            "VAULT_LOCKED_1"
        );
        assertEq(
            r.lendingPool.getVaultLockedAmount(Types.VaultKey(address(r.usdc), address(this)), 2),
            amount2,
            "VAULT_LOCKED_2"
        );
        assertEq(
            r.lendingPool.getVaultLockedAmount(Types.VaultKey(address(r.usdc), address(this)), 3),
            0,
            "VAULT_LOCKED_3"
        );
    }
}
