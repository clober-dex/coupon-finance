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

contract LendingPoolBorrowUnitTest is Test, ILendingPoolEvents, ERC1155Holder {
    using ERC20Utils for IERC20;
    using CouponKeyLibrary for Types.CouponKey;
    using LoanKeyLibrary for Types.LoanKey;

    SetUp.Result public r;
    uint256 private _snapshotId;

    receive() external payable {}

    function setUp() public {
        r = SetUp.run(vm);
    }

    function testBorrow() public {
        uint256 amount = r.usdc.amount(100);
        r.lendingPool.deposit(address(r.usdc), amount, address(this));

        Types.CouponKey memory couponKey = Types.CouponKey({asset: address(r.usdc), epoch: 1});
        uint256 couponId = couponKey.toId();
        r.lendingPool.mintCoupons(couponKey.asset, Utils.toArr(couponKey.epoch), Utils.toArr(amount), Constants.USER1);

        Types.LoanKey memory loanKey = Types.LoanKey({
            user: Constants.USER1,
            collateral: address(r.weth),
            asset: address(r.usdc)
        });
        r.lendingPool.convertToCollateral{value: 1 ether}(loanKey, 1 ether);

        Types.LoanStatus memory beforeLoanStatus = r.lendingPool.getLoanStatus(loanKey);
        uint256 beforeUserCouponBalance = r.lendingPool.balanceOf(Constants.USER1, couponId);
        uint256 beforeCouponTotalSupply = r.lendingPool.totalSupply(couponId);
        uint256 beforeRecipientBalance = r.usdc.balanceOf(Constants.USER2);

        vm.startPrank(Constants.USER1);
        Types.Coupon[] memory coupons = Utils.toArr(Types.Coupon(couponKey, amount));
        _snapshotId = vm.snapshot();
        // check Borrow event
        vm.expectEmit(true, true, true, true);
        emit Borrow(loanKey.toId(), Constants.USER2, amount);
        r.lendingPool.borrow(coupons, address(r.weth), Constants.USER2);
        // check LoanLimitChanged event
        vm.revertTo(_snapshotId);
        vm.expectEmit(true, true, true, true);
        emit LoanLimitChanged(loanKey.toId(), 1, beforeLoanStatus.limit + amount);
        r.lendingPool.borrow(coupons, address(r.weth), Constants.USER2);
        vm.stopPrank();

        Types.LoanStatus memory afterLoanStatus = r.lendingPool.getLoanStatus(loanKey);
        uint256 afterUserCouponBalance = r.lendingPool.balanceOf(Constants.USER1, couponId);
        uint256 afterCouponTotalSupply = r.lendingPool.totalSupply(couponId);
        uint256 afterRecipientBalance = r.usdc.balanceOf(Constants.USER2);

        assertEq(beforeLoanStatus.amount + amount, afterLoanStatus.amount, "LOAN_AMOUNT");
        assertEq(beforeLoanStatus.limit + amount, afterLoanStatus.limit, "LOAN_LIMIT");
        assertEq(beforeUserCouponBalance, afterUserCouponBalance + amount, "USER_COUPON_BALANCE");
        assertEq(beforeCouponTotalSupply, afterCouponTotalSupply + amount, "COUPON_TOTAL_SUPPLY");
        assertEq(beforeRecipientBalance + amount, afterRecipientBalance, "RECIPIENT_BALANCE");
    }

    function testBorrowNative() public {
        r.lendingPool.deposit(address(r.weth), 1 ether, address(this));

        Types.CouponKey memory couponKey = Types.CouponKey({asset: address(r.weth), epoch: 1});
        uint256 couponId = couponKey.toId();
        r.lendingPool.mintCoupons(couponKey.asset, Utils.toArr(couponKey.epoch), Utils.toArr(1 ether), Constants.USER1);

        Types.LoanKey memory loanKey = Types.LoanKey({
            user: Constants.USER1,
            collateral: address(r.usdc),
            asset: address(r.weth)
        });
        r.lendingPool.convertToCollateral(loanKey, r.usdc.amount(10000));

        Types.LoanStatus memory beforeLoanStatus = r.lendingPool.getLoanStatus(loanKey);
        uint256 beforeUserCouponBalance = r.lendingPool.balanceOf(Constants.USER1, couponId);
        uint256 beforeCouponTotalSupply = r.lendingPool.totalSupply(couponId);
        uint256 beforeRecipientBalance = r.weth.balanceOf(Constants.USER2);
        uint256 beforeRecipientNativeBalance = Constants.USER2.balance;

        vm.startPrank(Constants.USER1);
        Types.Coupon[] memory coupons = Utils.toArr(
            Types.Coupon(Types.CouponKey({asset: address(0), epoch: 1}), 1 ether)
        );
        _snapshotId = vm.snapshot();
        // check Borrow event
        vm.expectEmit(true, true, true, true);
        emit Borrow(loanKey.toId(), Constants.USER2, 1 ether);
        r.lendingPool.borrow(coupons, address(r.usdc), Constants.USER2);
        // check LoanLimitChanged event
        vm.revertTo(_snapshotId);
        vm.expectEmit(true, true, true, true);
        emit LoanLimitChanged(loanKey.toId(), 1, beforeLoanStatus.limit + 1 ether);
        r.lendingPool.borrow(coupons, address(r.usdc), Constants.USER2);
        vm.stopPrank();

        Types.LoanStatus memory afterLoanStatus = r.lendingPool.getLoanStatus(loanKey);
        uint256 afterUserCouponBalance = r.lendingPool.balanceOf(Constants.USER1, couponId);
        uint256 afterCouponTotalSupply = r.lendingPool.totalSupply(couponId);
        uint256 afterRecipientBalance = r.weth.balanceOf(Constants.USER2);
        uint256 afterRecipientNativeBalance = Constants.USER2.balance;

        assertEq(beforeLoanStatus.amount + 1 ether, afterLoanStatus.amount, "LOAN_AMOUNT");
        assertEq(beforeLoanStatus.limit + 1 ether, afterLoanStatus.limit, "LOAN_LIMIT");
        assertEq(beforeUserCouponBalance, afterUserCouponBalance + 1 ether, "USER_COUPON_BALANCE");
        assertEq(beforeCouponTotalSupply, afterCouponTotalSupply + 1 ether, "COUPON_TOTAL_SUPPLY");
        assertEq(beforeRecipientBalance, afterRecipientBalance, "RECIPIENT_BALANCE");
        assertEq(beforeRecipientNativeBalance + 1 ether, afterRecipientNativeBalance, "RECIPIENT_NATIVE_BALANCE");
    }

    function testBorrowTooMuchToken() public {
        uint256 amount = r.usdc.amount(2000);
        r.lendingPool.deposit(address(r.usdc), amount, address(this));

        Types.CouponKey memory couponKey = Types.CouponKey({asset: address(r.usdc), epoch: 1});
        r.lendingPool.mintCoupons(couponKey.asset, Utils.toArr(couponKey.epoch), Utils.toArr(amount), Constants.USER1);

        Types.LoanKey memory loanKey = Types.LoanKey({
            user: Constants.USER1,
            collateral: address(r.weth),
            asset: address(r.usdc)
        });
        r.lendingPool.convertToCollateral{value: 1 ether}(loanKey, 1 ether);

        vm.startPrank(Constants.USER1);
        Types.Coupon[] memory coupons = Utils.toArr(Types.Coupon(couponKey, amount));
        vm.expectRevert("Insufficient collateral");
        r.lendingPool.borrow(coupons, address(r.weth), Constants.USER2);
        vm.stopPrank();
    }

    function testBorrowWithExpiredCoupon() public {
        uint256 amount = r.usdc.amount(100);
        r.lendingPool.deposit(address(r.usdc), amount, address(this));

        Types.CouponKey memory couponKey = Types.CouponKey({asset: address(r.usdc), epoch: 1});
        r.lendingPool.mintCoupons(couponKey.asset, Utils.toArr(couponKey.epoch), Utils.toArr(amount), Constants.USER1);

        Types.LoanKey memory loanKey = Types.LoanKey({
            user: Constants.USER1,
            collateral: address(r.weth),
            asset: address(r.usdc)
        });
        r.lendingPool.convertToCollateral{value: 1 ether}(loanKey, 1 ether);

        vm.warp(block.timestamp + r.lendingPool.epochDuration());

        Types.Coupon[] memory coupons = Utils.toArr(Types.Coupon(couponKey, amount));
        vm.startPrank(Constants.USER1);
        vm.expectRevert("Coupon expired");
        r.lendingPool.borrow(coupons, address(r.weth), Constants.USER2);
        vm.stopPrank();
    }

    function testBorrowWithFutureEpochCoupon() public {
        uint256 amount = r.usdc.amount(100);
        r.lendingPool.deposit(address(r.usdc), amount * 4, address(this));

        Types.Coupon[] memory coupons = new Types.Coupon[](3);
        coupons[0] = Types.Coupon({key: Types.CouponKey({asset: address(r.usdc), epoch: 1}), amount: amount});
        coupons[1] = Types.Coupon({key: Types.CouponKey({asset: address(r.usdc), epoch: 2}), amount: amount * 2});
        coupons[2] = Types.Coupon({key: Types.CouponKey({asset: address(r.usdc), epoch: 4}), amount: amount});

        r.lendingPool.mintCoupons(
            address(r.usdc),
            Utils.toArr(1, 2, 4),
            Utils.toArr(amount, amount * 2, amount),
            Constants.USER1
        );

        vm.startPrank(Constants.USER1);

        Types.LoanKey memory loanKey = Types.LoanKey({
            user: Constants.USER1,
            collateral: address(r.weth),
            asset: address(r.usdc)
        });
        r.lendingPool.convertToCollateral{value: 1 ether}(loanKey, 1 ether);

        r.lendingPool.borrow(Utils.toArr(coupons[0]), address(r.weth), Constants.USER2);

        uint256 couponId = coupons[1].key.toId();
        Types.LoanStatus memory beforeLoanStatus = r.lendingPool.getLoanStatus(loanKey);
        uint256 beforeFutureEpochLoanLimit = r.lendingPool.getLoanLimit(loanKey, coupons[1].key.epoch);
        uint256 beforeUserCouponBalance = r.lendingPool.balanceOf(Constants.USER1, couponId);
        uint256 beforeCouponTotalSupply = r.lendingPool.totalSupply(couponId);
        uint256 beforeRecipientBalance = r.usdc.balanceOf(Constants.USER2);

        {
            Types.Coupon[] memory inputCoupons = new Types.Coupon[](1);
            inputCoupons[0] = coupons[1];
            vm.expectEmit(true, true, true, true);
            emit LoanLimitChanged(loanKey.toId(), 2, beforeLoanStatus.limit + amount);
            r.lendingPool.borrow(inputCoupons, address(r.weth), Constants.USER2);
        }

        Types.LoanStatus memory afterLoanStatus = r.lendingPool.getLoanStatus(loanKey);
        uint256 afterFutureEpochLoanLimit = r.lendingPool.getLoanLimit(loanKey, coupons[1].key.epoch);
        uint256 afterUserCouponBalance = r.lendingPool.balanceOf(Constants.USER1, couponId);
        uint256 afterCouponTotalSupply = r.lendingPool.totalSupply(couponId);
        uint256 afterRecipientBalance = r.usdc.balanceOf(Constants.USER2);

        assertEq(beforeLoanStatus.amount, afterLoanStatus.amount, "LOAN_AMOUNT_0");
        assertEq(beforeLoanStatus.limit, afterLoanStatus.limit, "LOAN_LIMIT_0");
        assertEq(beforeFutureEpochLoanLimit + amount, afterFutureEpochLoanLimit, "FUTURE_EPOCH_LOAN_LIMIT_0");
        assertEq(beforeUserCouponBalance, afterUserCouponBalance + amount, "USER_COUPON_BALANCE_0");
        assertEq(beforeCouponTotalSupply, afterCouponTotalSupply + amount, "COUPON_TOTAL_SUPPLY_0");
        assertEq(beforeRecipientBalance, afterRecipientBalance, "RECIPIENT_BALANCE_0");

        couponId = coupons[2].key.toId();
        beforeLoanStatus = r.lendingPool.getLoanStatus(loanKey);
        beforeFutureEpochLoanLimit = r.lendingPool.getLoanLimit(loanKey, coupons[2].key.epoch);
        beforeUserCouponBalance = r.lendingPool.balanceOf(Constants.USER1, couponId);
        beforeCouponTotalSupply = r.lendingPool.totalSupply(couponId);
        beforeRecipientBalance = r.usdc.balanceOf(Constants.USER2);

        r.lendingPool.borrow(Utils.toArr(coupons[2]), address(r.weth), Constants.USER2);

        afterLoanStatus = r.lendingPool.getLoanStatus(loanKey);
        afterFutureEpochLoanLimit = r.lendingPool.getLoanLimit(loanKey, coupons[2].key.epoch);
        afterUserCouponBalance = r.lendingPool.balanceOf(Constants.USER1, couponId);
        afterCouponTotalSupply = r.lendingPool.totalSupply(couponId);
        afterRecipientBalance = r.usdc.balanceOf(Constants.USER2);

        assertEq(beforeLoanStatus.amount, afterLoanStatus.amount, "LOAN_AMOUNT_1");
        assertEq(beforeLoanStatus.limit, afterLoanStatus.limit, "LOAN_LIMIT_1");
        assertEq(beforeFutureEpochLoanLimit, afterFutureEpochLoanLimit, "FUTURE_EPOCH_LOAN_LIMIT_1");
        assertEq(beforeUserCouponBalance, afterUserCouponBalance, "USER_COUPON_BALANCE_1");
        assertEq(beforeCouponTotalSupply, afterCouponTotalSupply, "COUPON_TOTAL_SUPPLY_1");
        assertEq(beforeRecipientBalance, afterRecipientBalance, "RECIPIENT_BALANCE_1");

        vm.stopPrank();
    }

    function testBorrowWhenLoanedAmountAlreadyExceedsLimit() public {
        uint256 amount = r.usdc.amount(100);
        r.lendingPool.deposit(address(r.usdc), amount * 3, address(this));

        Types.Coupon[] memory coupons = new Types.Coupon[](2);
        coupons[0] = Types.Coupon({key: Types.CouponKey({asset: address(r.usdc), epoch: 1}), amount: amount});
        coupons[1] = Types.Coupon({key: Types.CouponKey({asset: address(r.usdc), epoch: 2}), amount: amount * 2});

        r.lendingPool.mintCoupons(address(r.usdc), Utils.toArr(1, 2), Utils.toArr(amount, amount * 2), Constants.USER1);

        vm.startPrank(Constants.USER1);

        Types.LoanKey memory loanKey = Types.LoanKey({
            user: Constants.USER1,
            collateral: address(r.weth),
            asset: address(r.usdc)
        });
        r.lendingPool.convertToCollateral{value: 1 ether}(loanKey, 1 ether);

        r.lendingPool.borrow(Utils.toArr(coupons[0]), address(r.weth), Constants.USER2);

        vm.warp(block.timestamp + r.lendingPool.epochDuration());

        uint256 couponId = coupons[1].key.toId();
        Types.LoanStatus memory beforeLoanStatus = r.lendingPool.getLoanStatus(loanKey);
        uint256 beforeUserCouponBalance = r.lendingPool.balanceOf(Constants.USER1, couponId);
        uint256 beforeCouponTotalSupply = r.lendingPool.totalSupply(couponId);
        uint256 beforeRecipientBalance = r.usdc.balanceOf(Constants.USER2);

        Types.Coupon[] memory inputCoupons = new Types.Coupon[](1);
        inputCoupons[0] = coupons[1];
        _snapshotId = vm.snapshot();
        // check Borrow event
        vm.expectEmit(true, true, true, true);
        emit Borrow(loanKey.toId(), Constants.USER2, amount);
        r.lendingPool.borrow(inputCoupons, address(r.weth), Constants.USER2);
        // check LoanLimitChanged event
        vm.revertTo(_snapshotId);
        vm.expectEmit(true, true, true, true);
        emit LoanLimitChanged(loanKey.toId(), 2, beforeLoanStatus.limit + amount * 2);
        r.lendingPool.borrow(inputCoupons, address(r.weth), Constants.USER2);

        Types.LoanStatus memory afterLoanStatus = r.lendingPool.getLoanStatus(loanKey);
        uint256 afterUserCouponBalance = r.lendingPool.balanceOf(Constants.USER1, couponId);
        uint256 afterCouponTotalSupply = r.lendingPool.totalSupply(couponId);
        uint256 afterRecipientBalance = r.usdc.balanceOf(Constants.USER2);

        assertEq(beforeLoanStatus.amount + amount, afterLoanStatus.amount, "LOAN_AMOUNT");
        assertEq(beforeLoanStatus.limit + amount * 2, afterLoanStatus.limit, "LOAN_LIMIT");
        assertEq(beforeUserCouponBalance, afterUserCouponBalance + amount * 2, "USER_COUPON_BALANCE");
        assertEq(beforeCouponTotalSupply, afterCouponTotalSupply + amount * 2, "COUPON_TOTAL_SUPPLY");
        assertEq(beforeRecipientBalance + amount, afterRecipientBalance, "RECIPIENT_BALANCE");
        vm.stopPrank();
    }
}
