// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {Types} from "../../../../contracts/Types.sol";
import {ILendingPoolEvents} from "../../../../contracts/interfaces/ILendingPool.sol";
import {CouponKeyLibrary, LoanKeyLibrary} from "../../../../contracts/libraries/Keys.sol";
import {ERC20Utils, Utils} from "../../Utils.sol";
import {Constants} from "../Constants.sol";
import {SetUp} from "./SetUp.sol";

contract LendingPoolLiquidationUnitTest is Test, ILendingPoolEvents, ERC1155Holder {
    using ERC20Utils for IERC20;
    using CouponKeyLibrary for Types.CouponKey;
    using LoanKeyLibrary for Types.LoanKey;

    SetUp.Result public r;
    uint256 private _snapshotId;

    receive() external payable {}

    function setUp() public {
        r = SetUp.run(vm);
    }

    function testLiquidationWhenPriceChanges() public {
        uint256 amount = r.usdc.amount(1380);
        r.lendingPool.deposit(address(r.usdc), amount, address(this));

        Types.CouponKey memory couponKey = Types.CouponKey({asset: address(r.usdc), epoch: 1});
        uint256 couponId = couponKey.toId();
        r.lendingPool.mintCoupons(couponKey.asset, Utils.toArr(couponKey.epoch), Utils.toArr(1 ether), Constants.USER1);

        Types.LoanKey memory loanKey = Types.LoanKey({
            user: Constants.USER1,
            collateral: address(r.weth),
            asset: address(r.usdc)
        });
        r.lendingPool.convertToCollateral{value: 1 ether}(loanKey, 1 ether);

        Types.Coupon[] memory coupons = Utils.toArr(Types.Coupon(couponKey, amount));
        vm.prank(Constants.USER1);
        r.lendingPool.borrow(coupons, address(r.weth), Constants.USER1);

        r.oracle.setAssetPrice(address(r.weth), 1600 * 10 ** 8);

        Types.LiquidationStatus memory liquidationStatus = r.lendingPool.getLiquidationStatus(loanKey, 0);

        assertEq(liquidationStatus.available, true, "LIQUIDATION_AVAILABLE");
        assertEq(liquidationStatus.liquidationAmount, 1 ether / 2, "LIQUIDATION_AMOUNT");

        uint256 beforeUserCouponBalance = r.lendingPool.balanceOf(Constants.USER1, couponId);
        Types.LoanStatus memory beforeUserLoanStatus = r.lendingPool.getLoanStatus(loanKey);
        uint256 beforeLiquidatorBalance = r.usdc.balanceOf(address(this));
        uint256 beforeTreasuryBalance = r.usdc.balanceOf(r.lendingPool.treasury());

        r.lendingPool.liquidate(address(r.weth), address(r.usdc), Constants.USER1, 1 ether, new bytes(0));

        uint256 afterUserCouponBalance = r.lendingPool.balanceOf(Constants.USER1, couponId);
        Types.LoanStatus memory afterUserLoanStatus = r.lendingPool.getLoanStatus(loanKey);
        uint256 afterLiquidatorBalance = r.usdc.balanceOf(address(this));
        uint256 afterTreasuryBalance = r.usdc.balanceOf(r.lendingPool.treasury());

        assertEq(afterUserCouponBalance - beforeUserCouponBalance, 820 * 10 ** 18, "USER_COUPON_BALANCE");
        assertEq(beforeUserLoanStatus.amount - afterUserLoanStatus.amount, r.usdc.amount(820), "LOAN_AMOUNT");
        assertEq(
            beforeUserLoanStatus.collateralAmount - afterUserLoanStatus.collateralAmount,
            1 ether / 2,
            "COLLATERAL_AMOUNT"
        );
        assertEq(beforeUserLoanStatus.limit - afterUserLoanStatus.limit, r.usdc.amount(800), "LOAN_LIMIT");
        assertEq(afterLiquidatorBalance - beforeLiquidatorBalance, r.usdc.amount(16), "LIQUIDATOR_BALANCE");
        assertEq(afterTreasuryBalance - beforeTreasuryBalance, r.usdc.amount(4), "TREASURY_BALANCE");
    }

    function testLiquidationEpochEnds() public {
        uint256 amount = r.usdc.amount(1000);
        r.lendingPool.deposit(address(r.usdc), amount, address(this));

        Types.CouponKey memory couponKey = Types.CouponKey({asset: address(r.usdc), epoch: 1});
        uint256 couponId = couponKey.toId();
        r.lendingPool.mintCoupons(couponKey.asset, Utils.toArr(couponKey.epoch), Utils.toArr(1 ether), Constants.USER1);

        Types.LoanKey memory loanKey = Types.LoanKey({
            user: Constants.USER1,
            collateral: address(r.weth),
            asset: address(r.usdc)
        });
        r.lendingPool.convertToCollateral{value: 1 ether}(loanKey, 1 ether);

        Types.Coupon[] memory coupons = Utils.toArr(Types.Coupon(couponKey, amount));
        vm.prank(Constants.USER1);
        r.lendingPool.borrow(coupons, address(r.weth), Constants.USER1);

        vm.warp(block.timestamp + r.lendingPool.epochDuration());

        Types.LiquidationStatus memory liquidationStatus = r.lendingPool.getLiquidationStatus(loanKey, 0);

        assertEq(liquidationStatus.available, true, "LIQUIDATION_AVAILABLE");
        assertEq(liquidationStatus.liquidationAmount, 1 ether, "LIQUIDATION_AMOUNT");

        uint256 beforeUserCouponBalance = r.lendingPool.balanceOf(Constants.USER1, couponId);
        Types.LoanStatus memory beforeUserLoanStatus = r.lendingPool.getLoanStatus(loanKey);
        uint256 beforeLiquidatorBalance = r.usdc.balanceOf(address(this));
        uint256 beforeTreasuryBalance = r.usdc.balanceOf(r.lendingPool.treasury());

        r.lendingPool.liquidate(address(r.weth), address(r.usdc), Constants.USER1, 1 ether, new bytes(0));

        uint256 afterUserCouponBalance = r.lendingPool.balanceOf(Constants.USER1, couponId);
        Types.LoanStatus memory afterUserLoanStatus = r.lendingPool.getLoanStatus(loanKey);
        uint256 afterLiquidatorBalance = r.usdc.balanceOf(address(this));
        uint256 afterTreasuryBalance = r.usdc.balanceOf(r.lendingPool.treasury());

        assertEq(beforeUserCouponBalance - afterUserCouponBalance, 0, "USER_COUPON_BALANCE");
        assertEq(beforeUserLoanStatus.amount - afterUserLoanStatus.amount, r.usdc.amount(1000), "LOAN_AMOUNT");
        assertEq(
            beforeUserLoanStatus.collateralAmount - afterUserLoanStatus.collateralAmount,
            1 ether,
            "COLLATERAL_AMOUNT"
        );
        assertEq(beforeUserLoanStatus.limit - afterUserLoanStatus.limit, r.usdc.amount(1600), "LOAN_LIMIT");
        assertEq(afterLiquidatorBalance - beforeLiquidatorBalance, r.usdc.amount(20), "LIQUIDATOR_BALANCE");
        assertEq(afterTreasuryBalance - beforeTreasuryBalance, r.usdc.amount(5), "TREASURY_BALANCE");
    }
}
