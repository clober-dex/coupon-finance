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

contract LendingPoolDepositUnitTest is Test, ILendingPoolEvents, ERC1155Holder {
    using ERC20Utils for IERC20;
    using CouponKeyLibrary for Types.CouponKey;

    SetUp.Result public r;

    function setUp() public {
        r = SetUp.run(vm);
    }

    function testBurnCoupons() public {
        uint256 amount = r.usdc.amount(100);
        r.lendingPool.deposit(address(r.usdc), amount, address(this));

        Types.CouponKey memory couponKey = Types.CouponKey({asset: address(r.usdc), epoch: 1});
        uint256 couponId = couponKey.toId();
        r.lendingPool.mintCoupons(Utils.toArray(Types.Coupon(couponKey, amount)), Constants.USER1);

        uint256 burnAmount = amount / 3;
        Types.ReserveStatus memory beforeReserve = r.lendingPool.getReserveStatus(address(r.usdc));
        Types.VaultStatus memory beforeVault = r.lendingPool.getVaultStatus(
            Types.VaultKey(address(r.usdc), address(this))
        );
        uint256 beforeCouponBalance = r.lendingPool.balanceOf(Constants.USER1, couponId);
        uint256 beforeCouponTotalSupply = r.lendingPool.totalSupply(couponId);

        vm.startPrank(Constants.USER1);
        r.lendingPool.burnCoupons(Utils.toArray(Types.Coupon(couponKey, burnAmount)), address(this));
        vm.stopPrank();

        Types.ReserveStatus memory afterReserve = r.lendingPool.getReserveStatus(address(r.usdc));
        Types.VaultStatus memory afterVault = r.lendingPool.getVaultStatus(
            Types.VaultKey(address(r.usdc), address(this))
        );
        uint256 afterCouponBalance = r.lendingPool.balanceOf(Constants.USER1, couponId);
        uint256 afterCouponTotalSupply = r.lendingPool.totalSupply(couponId);

        assertEq(beforeReserve.lockedAmount, afterReserve.lockedAmount + burnAmount, "RESERVE_LOCKED");
        assertEq(beforeReserve.spendableAmount + burnAmount, afterReserve.spendableAmount, "RESERVE_SPENDABLE");
        assertEq(beforeVault.lockedAmount, afterVault.lockedAmount + burnAmount, "VAULT_LOCKED");
        assertEq(beforeVault.spendableAmount + burnAmount, afterVault.spendableAmount, "VAULT_SPENDABLE");
        assertEq(beforeCouponBalance, afterCouponBalance + burnAmount, "COUPON_BALANCE");
        assertEq(beforeCouponTotalSupply, afterCouponTotalSupply + burnAmount, "COUPON_TOTAL_SUPPLY");
    }

    function testBurnCouponsWhenTheAmountExceedsLockedAmount() public {
        uint256 amount = r.usdc.amount(100);
        r.lendingPool.deposit(address(r.usdc), amount, address(this));

        Types.CouponKey memory couponKey = Types.CouponKey({asset: address(r.usdc), epoch: 1});
        uint256 couponId = couponKey.toId();
        r.lendingPool.mintCoupons(Utils.toArray(Types.Coupon(couponKey, amount)), Constants.USER1);

        uint256 burnAmount = amount / 3;
        r.lendingPool.deposit(address(r.usdc), burnAmount - 1, Constants.USER1);
        vm.startPrank(Constants.USER1);
        r.lendingPool.mintCoupons(Utils.toArray(Types.Coupon(couponKey, burnAmount - 1)), Constants.USER2);

        Types.ReserveStatus memory beforeReserve = r.lendingPool.getReserveStatus(address(r.usdc));
        Types.VaultStatus memory beforeVault = r.lendingPool.getVaultStatus(
            Types.VaultKey(address(r.usdc), address(this))
        );
        uint256 beforeCouponBalance = r.lendingPool.balanceOf(Constants.USER1, couponId);
        uint256 beforeCouponTotalSupply = r.lendingPool.totalSupply(couponId);

        r.lendingPool.burnCoupons(Utils.toArray(Types.Coupon(couponKey, burnAmount)), Constants.USER1);
        vm.stopPrank();

        Types.ReserveStatus memory afterReserve = r.lendingPool.getReserveStatus(address(r.usdc));
        Types.VaultStatus memory afterVault = r.lendingPool.getVaultStatus(
            Types.VaultKey(address(r.usdc), Constants.USER1)
        );
        uint256 afterCouponBalance = r.lendingPool.balanceOf(Constants.USER1, couponId);
        uint256 afterCouponTotalSupply = r.lendingPool.totalSupply(couponId);

        assertEq(beforeReserve.lockedAmount, afterReserve.lockedAmount + burnAmount - 1, "RESERVE_LOCKED");
        assertEq(beforeReserve.spendableAmount + burnAmount - 1, afterReserve.spendableAmount, "RESERVE_SPENDABLE");
        assertEq(afterVault.lockedAmount, 0, "VAULT_LOCKED");
        assertEq(beforeVault.spendableAmount + burnAmount - 1, afterVault.spendableAmount, "VAULT_SPENDABLE");
        assertEq(beforeCouponBalance, afterCouponBalance + burnAmount - 1, "COUPON_BALANCE");
        assertEq(beforeCouponTotalSupply, afterCouponTotalSupply + burnAmount - 1, "COUPON_TOTAL_SUPPLY");
    }

    function testBurnCouponsWithExpiredCoupon() public {
        uint256 amount = r.usdc.amount(100);
        r.lendingPool.deposit(address(r.usdc), amount, address(this));

        Types.CouponKey memory couponKey = Types.CouponKey({asset: address(r.usdc), epoch: 1});
        uint256 couponId = couponKey.toId();
        r.lendingPool.mintCoupons(Utils.toArray(Types.Coupon(couponKey, amount)), Constants.USER1);

        uint256 couponBalance = r.lendingPool.balanceOf(Constants.USER1, couponId);
        vm.startPrank(Constants.USER1);
        r.lendingPool.burnCoupons(Utils.toArray(Types.Coupon(couponKey, amount)), Constants.USER1);
        assertEq(r.lendingPool.balanceOf(Constants.USER1, couponId), couponBalance, "COUPON_BALANCE_0");

        vm.warp(block.timestamp + r.lendingPool.epochDuration());

        r.lendingPool.burnCoupons(Utils.toArray(Types.Coupon(couponKey, amount / 2)), Constants.USER1);
        assertEq(r.lendingPool.balanceOf(Constants.USER1, couponId), amount / 2, "COUPON_BALANCE_1");
        vm.stopPrank();

        assertEq(r.lendingPool.getReserveLockedAmount(address(r.usdc), 1), amount, "RESERVE_LOCKED_0");
        assertEq(
            r.lendingPool.getVaultLockedAmount(Types.VaultKey(address(r.usdc), address(this)), 1),
            amount,
            "VAULT_LOCKED_0"
        );
        r.lendingPool.burnCoupons(Utils.toArray(Types.Coupon(couponKey, amount / 2)), address(this));
        // expect no change
        assertEq(r.lendingPool.getReserveLockedAmount(address(r.usdc), 1), amount, "RESERVE_LOCKED_1");
        assertEq(
            r.lendingPool.getVaultLockedAmount(Types.VaultKey(address(r.usdc), address(this)), 1),
            amount,
            "VAULT_LOCKED_1"
        );
    }
}
