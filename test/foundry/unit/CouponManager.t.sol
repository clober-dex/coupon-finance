// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {CouponManager} from "../../../contracts/CouponManager.sol";
import {ICouponManager} from "../../../contracts/interfaces/ICouponManager.sol";
import {CouponKey, CouponKeyLibrary} from "../../../contracts/libraries/CouponKey.sol";
import {Coupon, CouponLibrary} from "../../../contracts/libraries/Coupon.sol";
import {Epoch, EpochLibrary} from "../../../contracts/libraries/Epoch.sol";
import {Constants} from "../Constants.sol";
import {Utils} from "../Utils.sol";

contract CouponManagerUnitTest is Test, ERC1155Holder {
    using CouponKeyLibrary for CouponKey;
    using CouponLibrary for Coupon;
    using EpochLibrary for Epoch;

    ICouponManager public couponManager;

    Epoch public startEpoch;

    function setUp() public {
        couponManager = new CouponManager(Utils.toArr(address(this)), "URI/");
        startEpoch = EpochLibrary.current();
    }

    function testBaseURI() public {
        assertEq(couponManager.baseURI(), "URI/");
    }

    function testMintBatch() public {
        vm.warp(EpochLibrary.wrap(20).startTime());
        Coupon[] memory coupons = new Coupon[](2);
        coupons[0] = CouponLibrary.from(Constants.USDC, EpochLibrary.wrap(20), 100);
        coupons[1] = CouponLibrary.from(Constants.USDC, EpochLibrary.wrap(20).add(1), 70);

        couponManager.mintBatch(Constants.USER1, coupons, new bytes(0));

        assertEq(couponManager.totalSupply(coupons[0].id()), 100, "TOTAL_SUPPLY_0");
        assertEq(couponManager.totalSupply(coupons[1].id()), 70, "TOTAL_SUPPLY_1");
        assertEq(couponManager.balanceOf(Constants.USER1, coupons[0].id()), 100, "BALANCE_0");
        assertEq(couponManager.balanceOf(Constants.USER1, coupons[1].id()), 70, "BALANCE_1");
        assertEq(
            couponManager.uri(coupons[0].id()),
            "URI/0x000000000000000000000014af88d065e77c8cc2239327c5edb3a432268e5831",
            "URI_0"
        );
        assertEq(
            couponManager.uri(coupons[1].id()),
            "URI/0x000000000000000000000015af88d065e77c8cc2239327c5edb3a432268e5831",
            "URI_1"
        );
    }

    function testMintBatchOwnership() public {
        Coupon[] memory coupons = new Coupon[](2);
        coupons[0] = CouponLibrary.from(Constants.USDC, startEpoch, 100);
        coupons[1] = CouponLibrary.from(Constants.USDC, startEpoch.add(1), 70);

        vm.expectRevert(abi.encodeWithSelector(ICouponManager.InvalidAccess.selector));
        vm.prank(address(0x123));
        couponManager.mintBatch(Constants.USER1, coupons, new bytes(0));
    }

    function testSafeBatchTransferFrom() public {
        Coupon[] memory coupons = new Coupon[](2);
        coupons[0] = CouponLibrary.from(Constants.USDC, startEpoch, 100);
        coupons[1] = CouponLibrary.from(Constants.USDC, startEpoch.add(1), 70);
        couponManager.mintBatch(Constants.USER1, coupons, new bytes(0));

        vm.prank(Constants.USER1);
        couponManager.safeBatchTransferFrom(Constants.USER1, Constants.USER2, coupons, new bytes(0));

        assertEq(couponManager.balanceOf(Constants.USER1, coupons[0].id()), 0, "BALANCE_USER1_0");
        assertEq(couponManager.balanceOf(Constants.USER1, coupons[1].id()), 0, "BALANCE_USER1_1");
        assertEq(couponManager.balanceOf(Constants.USER2, coupons[0].id()), 100, "BALANCE_USER2_0");
        assertEq(couponManager.balanceOf(Constants.USER2, coupons[1].id()), 70, "BALANCE_USER2_1");
    }

    function testBurnExpiredCoupons() public {
        Coupon[] memory coupons = new Coupon[](2);
        coupons[0] = CouponLibrary.from(Constants.USDC, startEpoch, 100);
        coupons[1] = CouponLibrary.from(Constants.USDC, startEpoch.add(1), 70);

        couponManager.mintBatch(Constants.USER1, coupons, new bytes(0));

        vm.warp(EpochLibrary.current().add(1).startTime());

        CouponKey[] memory couponKeys = new CouponKey[](3);
        couponKeys[0] = coupons[0].key;
        couponKeys[1] = coupons[1].key;
        couponKeys[2] = CouponKey({asset: Constants.USDC, epoch: Epoch.wrap(124)});
        vm.prank(Constants.USER1);
        couponManager.burnExpiredCoupons(couponKeys);

        assertEq(couponManager.totalSupply(couponKeys[0].toId()), 0, "TOTAL_SUPPLY_0");
        assertEq(couponManager.totalSupply(couponKeys[1].toId()), 70, "TOTAL_SUPPLY_1");
        assertEq(couponManager.balanceOf(Constants.USER1, couponKeys[0].toId()), 0, "BALANCE_USER1_0");
        assertEq(couponManager.balanceOf(Constants.USER1, couponKeys[1].toId()), 70, "BALANCE_USER1_1");
        assertEq(couponManager.balanceOf(Constants.USER1, couponKeys[2].toId()), 0, "BALANCE_USER1_2");
    }

    function testBurnBatch() public {
        Coupon[] memory coupons = new Coupon[](2);
        coupons[0] = CouponLibrary.from(Constants.USDC, startEpoch, 100);
        coupons[1] = CouponLibrary.from(Constants.USDC, startEpoch.add(1), 70);

        couponManager.mintBatch(Constants.USER1, coupons, new bytes(0));

        Coupon[] memory couponsToBurn = new Coupon[](2);
        couponsToBurn[0] = CouponLibrary.from(Constants.USDC, startEpoch, 50);
        couponsToBurn[1] = CouponLibrary.from(Constants.USDC, startEpoch.add(1), 30);
        couponManager.burnBatch(Constants.USER1, couponsToBurn);

        assertEq(couponManager.totalSupply(coupons[0].id()), 50, "TOTAL_SUPPLY_0");
        assertEq(couponManager.totalSupply(coupons[1].id()), 40, "TOTAL_SUPPLY_1");
        assertEq(couponManager.balanceOf(Constants.USER1, coupons[0].id()), 50, "BALANCE_USER1_0");
        assertEq(couponManager.balanceOf(Constants.USER1, coupons[1].id()), 40, "BALANCE_USER1_1");
    }

    function testBurnBatchOwnership() public {
        Coupon[] memory coupons = new Coupon[](2);
        coupons[0] = CouponLibrary.from(Constants.USDC, startEpoch, 100);
        coupons[1] = CouponLibrary.from(Constants.USDC, startEpoch.add(1), 70);

        couponManager.mintBatch(Constants.USER1, coupons, new bytes(0));

        Coupon[] memory couponsToBurn = new Coupon[](2);
        couponsToBurn[0] = CouponLibrary.from(Constants.USDC, startEpoch, 50);
        couponsToBurn[1] = CouponLibrary.from(Constants.USDC, startEpoch.add(1), 30);

        vm.expectRevert(abi.encodeWithSelector(ICouponManager.InvalidAccess.selector));
        vm.prank(Constants.USER2);
        couponManager.burnBatch(Constants.USER1, couponsToBurn);

        vm.expectRevert(abi.encodeWithSelector(ICouponManager.InvalidAccess.selector));
        vm.prank(Constants.USER1);
        couponManager.burnBatch(Constants.USER1, couponsToBurn);
    }
}
