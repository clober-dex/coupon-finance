// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC2612} from "@openzeppelin/contracts/interfaces/IERC2612.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {Types} from "../../../../contracts/Types.sol";
import {ILendingPoolEvents} from "../../../../contracts/interfaces/ILendingPool.sol";
import {CouponKeyLibrary, LoanKeyLibrary} from "../../../../contracts/libraries/Keys.sol";
import {ERC20Utils, Utils} from "../../Utils.sol";
import {Constants} from "../Constants.sol";
import {SetUp} from "./SetUp.sol";

contract LendingPoolRepayUnitTest is Test, ILendingPoolEvents, ERC1155Holder {
    using ERC20Utils for IERC20;
    using CouponKeyLibrary for Types.CouponKey;
    using LoanKeyLibrary for Types.LoanKey;

    struct PermitParams {
        uint256 nonce;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    SetUp.Result public r;
    uint256 private _snapshotId;
    PermitParams private _permitParams;

    function setUp() public {
        r = SetUp.run(vm);
    }

    function testRepay() public {
        uint256 unitAmount = r.usdc.amount(1);
        r.lendingPool.deposit(address(r.usdc), unitAmount * 200, address(this));

        Types.Coupon[] memory coupons = new Types.Coupon[](3);
        coupons[0] = Types.Coupon({key: Types.CouponKey({asset: address(r.usdc), epoch: 1}), amount: unitAmount * 100});
        coupons[1] = Types.Coupon({key: Types.CouponKey({asset: address(r.usdc), epoch: 2}), amount: unitAmount * 80});
        coupons[2] = Types.Coupon({key: Types.CouponKey({asset: address(r.usdc), epoch: 3}), amount: unitAmount * 10});

        r.lendingPool.mintCoupons(
            address(r.usdc),
            Utils.toArr(1, 2, 3),
            Utils.toArr(unitAmount * 100, unitAmount * 80, unitAmount * 10),
            Constants.USER1
        );

        Types.LoanKey memory loanKey = Types.LoanKey({
            user: Constants.USER1,
            collateral: address(r.weth),
            asset: address(r.usdc)
        });
        r.lendingPool.convertToCollateral{value: 1 ether}(loanKey, 1 ether);
        vm.startPrank(Constants.USER1);
        r.lendingPool.borrow(coupons, address(r.weth), Constants.USER2);
        vm.stopPrank();

        uint256[] memory beforeCouponBalances = new uint256[](3);
        beforeCouponBalances[0] = r.lendingPool.balanceOf(Constants.USER1, coupons[0].key.toId());
        beforeCouponBalances[1] = r.lendingPool.balanceOf(Constants.USER1, coupons[1].key.toId());
        beforeCouponBalances[2] = r.lendingPool.balanceOf(Constants.USER1, coupons[2].key.toId());
        uint256[] memory beforeCouponTotalSupplies = new uint256[](3);
        beforeCouponTotalSupplies[0] = r.lendingPool.totalSupply(coupons[0].key.toId());
        beforeCouponTotalSupplies[1] = r.lendingPool.totalSupply(coupons[1].key.toId());
        beforeCouponTotalSupplies[2] = r.lendingPool.totalSupply(coupons[2].key.toId());
        Types.LoanStatus memory beforeLoanStatus = r.lendingPool.getLoanStatus(loanKey);
        uint256 beforeSenderBalance = r.usdc.balanceOf(address(this));

        {
            _snapshotId = vm.snapshot();
            // check Repay event
            vm.expectEmit(true, true, true, true);
            emit Repay(loanKey.toId(), address(this), unitAmount * 50);
            r.lendingPool.repay(loanKey, unitAmount * 50);
            // check LoanLimitChanged1 event
            vm.revertTo(_snapshotId);
            vm.expectEmit(true, true, true, true);
            emit LoanLimitChanged(loanKey.toId(), 1, unitAmount * 50);
            r.lendingPool.repay(loanKey, unitAmount * 50);
            // check LoanLimitChanged2 event
            vm.revertTo(_snapshotId);
            vm.expectEmit(true, true, true, true);
            emit LoanLimitChanged(loanKey.toId(), 2, unitAmount * 50);
            r.lendingPool.repay(loanKey, unitAmount * 50);
        }

        uint256[] memory afterCouponBalances = new uint256[](3);
        afterCouponBalances[0] = r.lendingPool.balanceOf(Constants.USER1, coupons[0].key.toId());
        afterCouponBalances[1] = r.lendingPool.balanceOf(Constants.USER1, coupons[1].key.toId());
        afterCouponBalances[2] = r.lendingPool.balanceOf(Constants.USER1, coupons[2].key.toId());
        uint256[] memory afterCouponTotalSupplies = new uint256[](3);
        afterCouponTotalSupplies[0] = r.lendingPool.totalSupply(coupons[0].key.toId());
        afterCouponTotalSupplies[1] = r.lendingPool.totalSupply(coupons[1].key.toId());
        afterCouponTotalSupplies[2] = r.lendingPool.totalSupply(coupons[2].key.toId());
        uint256[] memory afterLoanLimits = new uint256[](3);
        afterLoanLimits[0] = r.lendingPool.getLoanLimit(loanKey, coupons[0].key.epoch);
        afterLoanLimits[1] = r.lendingPool.getLoanLimit(loanKey, coupons[1].key.epoch);
        afterLoanLimits[2] = r.lendingPool.getLoanLimit(loanKey, coupons[2].key.epoch);
        Types.LoanStatus memory afterLoanStatus = r.lendingPool.getLoanStatus(loanKey);
        uint256 afterSenderBalance = r.usdc.balanceOf(address(this));

        assertEq(beforeCouponBalances[0] + unitAmount * 50, afterCouponBalances[0], "COUPON_BALANCE_0");
        assertEq(beforeCouponBalances[1] + unitAmount * 30, afterCouponBalances[1], "COUPON_BALANCE_1");
        assertEq(beforeCouponBalances[2], afterCouponBalances[2], "COUPON_BALANCE_2");
        assertEq(beforeCouponTotalSupplies[0] + unitAmount * 50, afterCouponTotalSupplies[0], "COUPON_TOTAL_SUPPLY_0");
        assertEq(beforeCouponTotalSupplies[1] + unitAmount * 30, afterCouponTotalSupplies[1], "COUPON_TOTAL_SUPPLY_1");
        assertEq(beforeCouponTotalSupplies[2], afterCouponTotalSupplies[2], "COUPON_TOTAL_SUPPLY_2");
        assertEq(afterLoanLimits[0], unitAmount * 50, "LOAN_LIMIT_0");
        assertEq(afterLoanLimits[1], unitAmount * 50, "LOAN_LIMIT_1");
        assertEq(afterLoanLimits[2], unitAmount * 10, "LOAN_LIMIT_2");
        assertEq(beforeLoanStatus.amount, afterLoanStatus.amount + unitAmount * 50, "LOAN_AMOUNT");
        assertEq(beforeLoanStatus.limit, afterLoanStatus.limit + unitAmount * 50, "LOAN_LIMIT");
        assertEq(beforeSenderBalance, afterSenderBalance + unitAmount * 50, "SENDER_BALANCE");
    }

    function testRepayWithUnregisteredToken() public {
        Types.LoanKey memory loanKey1 = Types.LoanKey({
            user: Constants.USER1,
            collateral: address(0x123),
            asset: address(r.usdc)
        });
        vm.expectRevert("Unregistered asset");
        r.lendingPool.repay(loanKey1, 1000);

        Types.LoanKey memory loanKey2 = Types.LoanKey({
            user: Constants.USER1,
            collateral: address(r.weth),
            asset: address(0x231)
        });
        vm.expectRevert("Unregistered asset");
        r.lendingPool.repay(loanKey2, 1000);
    }

    function testRepayWithNativeToken() public {
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
        vm.startPrank(Constants.USER1);
        r.lendingPool.borrow(
            Utils.toArr(Types.Coupon(Types.CouponKey({asset: address(0), epoch: 1}), 1 ether)),
            address(r.usdc),
            Constants.USER2
        );
        vm.stopPrank();

        uint256 beforeCouponBalance = r.lendingPool.balanceOf(Constants.USER1, couponId);
        uint256 beforeCouponTotalSupply = r.lendingPool.totalSupply(couponId);
        Types.LoanStatus memory beforeLoanStatus = r.lendingPool.getLoanStatus(loanKey);
        uint256 beforeSenderBalance = r.weth.balanceOf(address(this));
        uint256 beforeSenderNativeBalance = address(this).balance;

        {
            _snapshotId = vm.snapshot();
            // check Repay event
            vm.expectEmit(true, true, true, true);
            emit Repay(loanKey.toId(), address(this), 1 ether);
            r.lendingPool.repay{value: 0.4 ether}(loanKey, 1 ether);
            // check LoanLimitChanged event
            vm.revertTo(_snapshotId);
            vm.expectEmit(true, true, true, true);
            emit LoanLimitChanged(loanKey.toId(), 1, beforeLoanStatus.limit - 1 ether);
            r.lendingPool.repay{value: 0.4 ether}(loanKey, 1 ether);
        }

        uint256 afterCouponBalance = r.lendingPool.balanceOf(Constants.USER1, couponId);
        uint256 afterCouponTotalSupply = r.lendingPool.totalSupply(couponId);
        Types.LoanStatus memory afterLoanStatus = r.lendingPool.getLoanStatus(loanKey);
        uint256 afterSenderBalance = r.weth.balanceOf(address(this));
        uint256 afterSenderNativeBalance = address(this).balance;

        assertEq(beforeCouponBalance + 1 ether, afterCouponBalance, "COUPON_BALANCE");
        assertEq(beforeCouponTotalSupply + 1 ether, afterCouponTotalSupply, "COUPON_TOTAL_SUPPLY");
        assertEq(beforeLoanStatus.amount, afterLoanStatus.amount + 1 ether, "LOAN_AMOUNT");
        assertEq(beforeLoanStatus.limit, afterLoanStatus.limit + 1 ether, "LOAN_LIMIT");
        assertEq(beforeSenderBalance, afterSenderBalance + 0.6 ether, "SENDER_BALANCE");
        assertEq(beforeSenderNativeBalance, afterSenderNativeBalance + 0.4 ether, "SENDER_NATIVE_BALANCE");
    }

    function testRepayNativeWithWrongToken() public {
        Types.LoanKey memory loanKey = Types.LoanKey({
            user: Constants.USER1,
            collateral: address(r.weth),
            asset: address(r.usdc)
        });
        uint256 unitAmount = r.usdc.amount(1);
        vm.expectRevert("msg.value not allowed");
        r.lendingPool.repay{value: 1000}(loanKey, unitAmount * 50);
    }

    function testRepayWhenLoanAmountAlreadyExceedsLimit() public {
        uint256 unitAmount = r.usdc.amount(1);
        r.lendingPool.deposit(address(r.usdc), unitAmount * 200, address(this));

        Types.Coupon[] memory coupons = new Types.Coupon[](2);
        coupons[0] = Types.Coupon({key: Types.CouponKey({asset: address(r.usdc), epoch: 1}), amount: unitAmount * 100});
        coupons[1] = Types.Coupon({key: Types.CouponKey({asset: address(r.usdc), epoch: 2}), amount: unitAmount * 80});

        r.lendingPool.mintCoupons(
            address(r.usdc),
            Utils.toArr(1, 2),
            Utils.toArr(unitAmount * 100, unitAmount * 80),
            Constants.USER1
        );

        Types.LoanKey memory loanKey = Types.LoanKey({
            user: Constants.USER1,
            collateral: address(r.weth),
            asset: address(r.usdc)
        });
        r.lendingPool.convertToCollateral{value: 1 ether}(loanKey, 1 ether);
        vm.startPrank(Constants.USER1);
        r.lendingPool.borrow(coupons, address(r.weth), Constants.USER2);
        vm.stopPrank();

        uint256[] memory beforeCouponBalances = new uint256[](2);
        beforeCouponBalances[0] = r.lendingPool.balanceOf(Constants.USER1, coupons[0].key.toId());
        beforeCouponBalances[1] = r.lendingPool.balanceOf(Constants.USER1, coupons[1].key.toId());
        uint256[] memory beforeCouponTotalSupplies = new uint256[](2);
        beforeCouponTotalSupplies[0] = r.lendingPool.totalSupply(coupons[0].key.toId());
        beforeCouponTotalSupplies[1] = r.lendingPool.totalSupply(coupons[1].key.toId());
        Types.LoanStatus memory beforeLoanStatus = r.lendingPool.getLoanStatus(loanKey);
        uint256 beforeSenderBalance = r.usdc.balanceOf(address(this));

        vm.warp(block.timestamp + r.lendingPool.epochDuration());

        {
            _snapshotId = vm.snapshot();
            // check Repay event
            vm.expectEmit(true, true, true, true);
            emit Repay(loanKey.toId(), address(this), unitAmount * 50);
            r.lendingPool.repay(loanKey, unitAmount * 50);
            // check LoanLimitChanged event
            vm.revertTo(_snapshotId);
            vm.expectEmit(true, true, true, true);
            emit LoanLimitChanged(loanKey.toId(), 1, unitAmount * 50);
            r.lendingPool.repay(loanKey, unitAmount * 50);
        }

        uint256[] memory afterCouponBalances = new uint256[](2);
        afterCouponBalances[0] = r.lendingPool.balanceOf(Constants.USER1, coupons[0].key.toId());
        afterCouponBalances[1] = r.lendingPool.balanceOf(Constants.USER1, coupons[1].key.toId());
        uint256[] memory afterCouponTotalSupplies = new uint256[](2);
        afterCouponTotalSupplies[0] = r.lendingPool.totalSupply(coupons[0].key.toId());
        afterCouponTotalSupplies[1] = r.lendingPool.totalSupply(coupons[1].key.toId());
        uint256[] memory afterLoanLimits = new uint256[](2);
        afterLoanLimits[0] = r.lendingPool.getLoanLimit(loanKey, coupons[0].key.epoch);
        afterLoanLimits[1] = r.lendingPool.getLoanLimit(loanKey, coupons[1].key.epoch);
        Types.LoanStatus memory afterLoanStatus = r.lendingPool.getLoanStatus(loanKey);
        uint256 afterSenderBalance = r.usdc.balanceOf(address(this));

        assertEq(beforeCouponBalances[0], afterCouponBalances[0], "COUPON_BALANCE_0");
        assertEq(beforeCouponBalances[1] + unitAmount * 30, afterCouponBalances[1], "COUPON_BALANCE_1");
        assertEq(beforeCouponTotalSupplies[0], afterCouponTotalSupplies[0], "COUPON_TOTAL_SUPPLY_0");
        assertEq(beforeCouponTotalSupplies[1] + unitAmount * 30, afterCouponTotalSupplies[1], "COUPON_TOTAL_SUPPLY_1");
        assertEq(afterLoanLimits[0], unitAmount * 100, "LOAN_LIMIT_0");
        assertEq(afterLoanLimits[1], unitAmount * 50, "LOAN_LIMIT_1");
        assertEq(beforeLoanStatus.amount, afterLoanStatus.amount + unitAmount * 50, "LOAN_AMOUNT");
        assertEq(beforeLoanStatus.limit, afterLoanStatus.limit + unitAmount * 50, "LOAN_LIMIT");
        assertEq(beforeSenderBalance, afterSenderBalance + unitAmount * 50, "SENDER_BALANCE");
    }

    function testRepayWithPermit() public {
        IERC2612 permitToken = IERC2612(address(r.usdc));

        uint256 unitAmount = r.usdc.amount(1);
        r.lendingPool.deposit(address(r.usdc), unitAmount * 100, address(this));

        Types.Coupon memory coupon = Types.Coupon({
            key: Types.CouponKey({asset: address(r.usdc), epoch: 1}),
            amount: unitAmount * 100
        });

        r.lendingPool.mintCoupons(address(r.usdc), Utils.toArr(1), Utils.toArr(unitAmount * 100), Constants.USER1);

        Types.LoanKey memory loanKey = Types.LoanKey({
            user: Constants.USER1,
            collateral: address(r.weth),
            asset: address(r.usdc)
        });
        r.lendingPool.convertToCollateral{value: 1 ether}(loanKey, 1 ether);
        vm.startPrank(Constants.USER1);
        r.lendingPool.borrow(Utils.toArr(coupon), address(r.weth), Constants.USER2);
        vm.stopPrank();

        uint256 beforeCouponBalance = r.lendingPool.balanceOf(Constants.USER1, coupon.key.toId());
        uint256 beforeCouponTotalSupply = r.lendingPool.totalSupply(coupon.key.toId());
        Types.LoanStatus memory beforeLoanStatus = r.lendingPool.getLoanStatus(loanKey);
        uint256 beforeSenderBalance = r.usdc.balanceOf(r.permitUser);

        r.usdc.transfer(r.permitUser, unitAmount * 50);
        vm.startPrank(r.permitUser);
        _permitParams.nonce = permitToken.nonces(r.permitUser);
        {
            bytes32 digest = keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    permitToken.DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            Constants.PERMIT_TYPEHASH,
                            r.permitUser,
                            address(r.lendingPool),
                            unitAmount * 50,
                            _permitParams.nonce,
                            type(uint256).max
                        )
                    )
                )
            );
            (_permitParams.v, _permitParams.r, _permitParams.s) = vm.sign(1, digest);

            _snapshotId = vm.snapshot();
            // check Repay event
            vm.expectEmit(true, true, true, true);
            emit Repay(loanKey.toId(), address(this), unitAmount * 50);
            r.lendingPool.repayWithPermit(
                loanKey,
                unitAmount * 50,
                type(uint256).max,
                _permitParams.v,
                _permitParams.r,
                _permitParams.s
            );
            // check LoanLimitChanged event
            vm.revertTo(_snapshotId);
            vm.expectEmit(true, true, true, true);
            emit LoanLimitChanged(loanKey.toId(), 1, unitAmount * 50);
            r.lendingPool.repayWithPermit(
                loanKey,
                unitAmount * 50,
                type(uint256).max,
                _permitParams.v,
                _permitParams.r,
                _permitParams.s
            );
        }

        vm.stopPrank();

        uint256 afterCouponBalance = r.lendingPool.balanceOf(Constants.USER1, coupon.key.toId());
        uint256 afterCouponTotalSupply = r.lendingPool.totalSupply(coupon.key.toId());
        Types.LoanStatus memory afterLoanStatus = r.lendingPool.getLoanStatus(loanKey);
        uint256 afterSenderBalance = r.usdc.balanceOf(r.permitUser);

        assertEq(beforeCouponBalance + unitAmount * 50, afterCouponBalance, "COUPON_BALANCE");
        assertEq(beforeCouponTotalSupply + unitAmount * 50, afterCouponTotalSupply, "COUPON_TOTAL_SUPPLY");
        assertEq(beforeLoanStatus.amount, afterLoanStatus.amount + unitAmount * 50, "LOAN_AMOUNT");
        assertEq(beforeLoanStatus.limit, afterLoanStatus.limit + unitAmount * 50, "LOAN_LIMIT");
        assertEq(beforeSenderBalance, afterSenderBalance + unitAmount * 50, "SENDER_BALANCE");
    }
}
