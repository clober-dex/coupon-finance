// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {Errors} from "../../../contracts/Errors.sol";
import {Types} from "../../../contracts/Types.sol";
import {ICouponManager} from "../../../contracts/interfaces/ICouponManager.sol";
import {Coupon} from "../../../contracts/libraries/Coupon.sol";
import {Epoch} from "../../../contracts/libraries/Epoch.sol";
import {Constants} from "../Constants.sol";

contract CouponManagerUnitTest is Test, ERC1155Holder {
    using Coupon for Types.Coupon;
    using Epoch for Types.Epoch;

    ICouponManager public couponManager;

    function setUp() public {
        // couponManager = new CouponManager();
    }

    function testMintBatch() public {
        Types.Coupon[] memory coupons = new Types.Coupon[](2);
        coupons[0] = Coupon.from(Constants.USDC, 1, 100);
        coupons[1] = Coupon.from(Constants.USDC, 2, 70);

        couponManager.mintBatch(Constants.USER1, coupons, new bytes(0));

        assertEq(couponManager.totalSupply(coupons[0].id()), 100);
        assertEq(couponManager.totalSupply(coupons[1].id()), 70);
        assertEq(couponManager.balanceOf(Constants.USER1, coupons[0].id()), 100);
        assertEq(couponManager.balanceOf(Constants.USER1, coupons[1].id()), 70);
    }

    function testMintBatchWithInvalidEpochs() public {
        Types.Coupon[] memory coupons = new Types.Coupon[](1);
        coupons[0] = Coupon.from(Constants.USDC, 0, 100);

        vm.expectRevert(Errors.EXPIRED_EPOCH);
        couponManager.mintBatch(Constants.USER1, coupons, new bytes(0));

        vm.warp(Epoch.current().add(2).startTime());
        coupons = new Types.Coupon[](2);
        coupons[0] = Coupon.from(Constants.USDC, 1, 100);
        coupons[1] = Coupon.from(Constants.USDC, 2, 70);

        vm.expectRevert(Errors.EXPIRED_EPOCH);
        couponManager.mintBatch(Constants.USER1, coupons, new bytes(0));

        coupons = new Types.Coupon[](2);
        coupons[0] = Coupon.from(Constants.USDC, 0, 100);
        coupons[1] = Coupon.from(Constants.USDC, 4, 70);

        vm.expectRevert(Errors.EXPIRED_EPOCH);
        couponManager.mintBatch(Constants.USER1, coupons, new bytes(0));
    }

    function testMintBatchOwnership() public {
        Types.Coupon[] memory coupons = new Types.Coupon[](2);
        coupons[0] = Coupon.from(Constants.USDC, 1, 100);
        coupons[1] = Coupon.from(Constants.USDC, 2, 70);

        vm.expectRevert(Errors.ACCESS);
        couponManager.mintBatch(Constants.USER1, coupons, new bytes(0));
    }

    function testSafeBatchTransferFrom() public {
        Types.Coupon[] memory coupons = new Types.Coupon[](2);
        coupons[0] = Coupon.from(Constants.USDC, 1, 100);
        coupons[1] = Coupon.from(Constants.USDC, 2, 70);
        couponManager.mintBatch(Constants.USER1, coupons, new bytes(0));

        vm.prank(Constants.USER1);
        couponManager.safeBatchTransferFrom(Constants.USER1, Constants.USER2, coupons, new bytes(0));

        assertEq(couponManager.balanceOf(Constants.USER1, coupons[0].id()), 0, "BALANCE_USER1_0");
        assertEq(couponManager.balanceOf(Constants.USER1, coupons[1].id()), 0, "BALANCE_USER1_1");
        assertEq(couponManager.balanceOf(Constants.USER2, coupons[0].id()), 100, "BALANCE_USER2_0");
        assertEq(couponManager.balanceOf(Constants.USER2, coupons[1].id()), 70, "BALANCE_USER2_1");
    }

    function testBurnExpiredCoupons() public {
        Types.Coupon[] memory coupons = new Types.Coupon[](2);
        coupons[0] = Coupon.from(Constants.USDC, 1, 100);
        coupons[1] = Coupon.from(Constants.USDC, 2, 70);

        couponManager.mintBatch(Constants.USER1, coupons, new bytes(0));

        vm.warp(Epoch.current().add(1).startTime());

        Types.CouponKey[] memory couponKeys = new Types.CouponKey[](2);
        couponKeys[0] = coupons[0].key;
        couponKeys[1] = coupons[1].key;
        vm.prank(Constants.USER1);
        couponManager.burnExpiredCoupons(couponKeys);

        assertEq(couponManager.totalSupply(coupons[0].id()), 0);
        assertEq(couponManager.totalSupply(coupons[1].id()), 70);
        assertEq(couponManager.balanceOf(Constants.USER1, coupons[0].id()), 0);
        assertEq(couponManager.balanceOf(Constants.USER1, coupons[1].id()), 70);
    }

    function testBurnExpiredCouponsOwnership() public {
        Types.Coupon[] memory coupons = new Types.Coupon[](2);
        coupons[0] = Coupon.from(Constants.USDC, 1, 100);
        coupons[1] = Coupon.from(Constants.USDC, 2, 70);

        couponManager.mintBatch(Constants.USER1, coupons, new bytes(0));

        vm.warp(Epoch.current().add(1).startTime());

        Types.CouponKey[] memory couponKeys = new Types.CouponKey[](2);
        couponKeys[0] = coupons[0].key;
        couponKeys[1] = coupons[1].key;
        vm.expectRevert(Errors.ACCESS);
        couponManager.burnExpiredCoupons(couponKeys);
    }

    function testBurnBatch() public {
        Types.Coupon[] memory coupons = new Types.Coupon[](2);
        coupons[0] = Coupon.from(Constants.USDC, 1, 100);
        coupons[1] = Coupon.from(Constants.USDC, 2, 70);

        couponManager.mintBatch(Constants.USER1, coupons, new bytes(0));

        Types.Coupon[] memory couponsToBurn = new Types.Coupon[](2);
        couponsToBurn[0] = Coupon.from(Constants.USDC, 1, 50);
        couponsToBurn[1] = Coupon.from(Constants.USDC, 2, 30);
        couponManager.burnBatch(Constants.USER1, couponsToBurn);

        assertEq(couponManager.totalSupply(coupons[0].id()), 50);
        assertEq(couponManager.totalSupply(coupons[1].id()), 40);
        assertEq(couponManager.balanceOf(Constants.USER1, coupons[0].id()), 50);
        assertEq(couponManager.balanceOf(Constants.USER1, coupons[1].id()), 40);

        couponsToBurn[0] = Coupon.from(Constants.USDC, 1, 10);
        couponsToBurn[1] = Coupon.from(Constants.USDC, 2, 5);
        vm.prank(Constants.USER1);
        couponManager.burnBatch(Constants.USER1, couponsToBurn);

        assertEq(couponManager.totalSupply(coupons[0].id()), 40);
        assertEq(couponManager.totalSupply(coupons[1].id()), 35);
        assertEq(couponManager.balanceOf(Constants.USER1, coupons[0].id()), 40);
        assertEq(couponManager.balanceOf(Constants.USER1, coupons[1].id()), 35);
    }

    function testBurnBatchOwnership() public {
        Types.Coupon[] memory coupons = new Types.Coupon[](2);
        coupons[0] = Coupon.from(Constants.USDC, 1, 100);
        coupons[1] = Coupon.from(Constants.USDC, 2, 70);

        couponManager.mintBatch(Constants.USER1, coupons, new bytes(0));

        Types.Coupon[] memory couponsToBurn = new Types.Coupon[](2);
        couponsToBurn[0] = Coupon.from(Constants.USDC, 1, 50);
        couponsToBurn[1] = Coupon.from(Constants.USDC, 2, 30);
        vm.expectRevert(Errors.ACCESS);
        vm.prank(Constants.USER2);
        couponManager.burnBatch(Constants.USER1, couponsToBurn);
    }
}
