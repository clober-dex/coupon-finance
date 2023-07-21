// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {Errors} from "../../../contracts/Errors.sol";
import {Types} from "../../../contracts/Types.sol";
import {CouponManager} from "../../../contracts/CouponManager.sol";
import {ICouponManager} from "../../../contracts/interfaces/ICouponManager.sol";
import {CouponKey} from "../../../contracts/libraries/CouponKey.sol";
import {Coupon} from "../../../contracts/libraries/Coupon.sol";
import {Epoch} from "../../../contracts/libraries/Epoch.sol";
import {Constants} from "../Constants.sol";

contract CouponManagerUnitTest is Test, ERC1155Holder {
    using CouponKey for Types.CouponKey;
    using Coupon for Types.Coupon;
    using Epoch for Types.Epoch;

    ICouponManager public couponManager;

    Types.Epoch public startEpoch;

    function setUp() public {
        couponManager = new CouponManager(address(this), "URI/");
        startEpoch = Epoch.current();
    }

    function testBaseURI() public {
        assertEq(couponManager.baseURI(), "URI/");
    }

    function testMintBatch() public {
        Types.Coupon[] memory coupons = new Types.Coupon[](2);
        coupons[0] = Coupon.from(Constants.USDC, startEpoch, 100);
        coupons[1] = Coupon.from(Constants.USDC, startEpoch.add(1), 70);

        couponManager.mintBatch(Constants.USER1, coupons, new bytes(0));

        assertEq(couponManager.totalSupply(coupons[0].id()), 100, "TOTAL_SUPPLY_0");
        assertEq(couponManager.totalSupply(coupons[1].id()), 70, "TOTAL_SUPPLY_1");
        assertEq(couponManager.balanceOf(Constants.USER1, coupons[0].id()), 100, "BALANCE_0");
        assertEq(couponManager.balanceOf(Constants.USER1, coupons[1].id()), 70, "BALANCE_1");
        assertEq(couponManager.uri(coupons[0].id()), "URI/0", "URI_0");
        assertEq(couponManager.uri(coupons[1].id()), "URI/1", "URI_1");
    }

    function testMintBatchOwnership() public {
        Types.Coupon[] memory coupons = new Types.Coupon[](2);
        coupons[0] = Coupon.from(Constants.USDC, startEpoch, 100);
        coupons[1] = Coupon.from(Constants.USDC, startEpoch.add(1), 70);

        vm.expectRevert(bytes(Errors.ACCESS));
        vm.prank(address(0x123));
        couponManager.mintBatch(Constants.USER1, coupons, new bytes(0));
    }

    function testSafeBatchTransferFrom() public {
        Types.Coupon[] memory coupons = new Types.Coupon[](2);
        coupons[0] = Coupon.from(Constants.USDC, startEpoch, 100);
        coupons[1] = Coupon.from(Constants.USDC, startEpoch.add(1), 70);
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
        coupons[0] = Coupon.from(Constants.USDC, startEpoch, 100);
        coupons[1] = Coupon.from(Constants.USDC, startEpoch.add(1), 70);

        couponManager.mintBatch(Constants.USER1, coupons, new bytes(0));

        vm.warp(Epoch.current().add(1).startTime());

        Types.CouponKey[] memory couponKeys = new Types.CouponKey[](3);
        couponKeys[0] = coupons[0].key;
        couponKeys[1] = coupons[1].key;
        couponKeys[2] = Types.CouponKey({asset: Constants.USDC, epoch: Types.Epoch.wrap(1242)});
        vm.prank(Constants.USER1);
        couponManager.burnExpiredCoupons(couponKeys);

        assertEq(couponManager.totalSupply(couponKeys[0].toId()), 0, "TOTAL_SUPPLY_0");
        assertEq(couponManager.totalSupply(couponKeys[1].toId()), 70, "TOTAL_SUPPLY_1");
        assertEq(couponManager.balanceOf(Constants.USER1, couponKeys[0].toId()), 0, "BALANCE_USER1_0");
        assertEq(couponManager.balanceOf(Constants.USER1, couponKeys[1].toId()), 70, "BALANCE_USER1_1");
        assertEq(couponManager.balanceOf(Constants.USER1, couponKeys[2].toId()), 0, "BALANCE_USER1_2");
    }

    function testBurnBatch() public {
        Types.Coupon[] memory coupons = new Types.Coupon[](2);
        coupons[0] = Coupon.from(Constants.USDC, startEpoch, 100);
        coupons[1] = Coupon.from(Constants.USDC, startEpoch.add(1), 70);

        couponManager.mintBatch(Constants.USER1, coupons, new bytes(0));

        Types.Coupon[] memory couponsToBurn = new Types.Coupon[](2);
        couponsToBurn[0] = Coupon.from(Constants.USDC, startEpoch, 50);
        couponsToBurn[1] = Coupon.from(Constants.USDC, startEpoch.add(1), 30);
        couponManager.burnBatch(Constants.USER1, couponsToBurn);

        assertEq(couponManager.totalSupply(coupons[0].id()), 50, "TOTAL_SUPPLY_0");
        assertEq(couponManager.totalSupply(coupons[1].id()), 40, "TOTAL_SUPPLY_1");
        assertEq(couponManager.balanceOf(Constants.USER1, coupons[0].id()), 50, "BALANCE_USER1_0");
        assertEq(couponManager.balanceOf(Constants.USER1, coupons[1].id()), 40, "BALANCE_USER1_1");
    }

    function testBurnBatchOwnership() public {
        Types.Coupon[] memory coupons = new Types.Coupon[](2);
        coupons[0] = Coupon.from(Constants.USDC, startEpoch, 100);
        coupons[1] = Coupon.from(Constants.USDC, startEpoch.add(1), 70);

        couponManager.mintBatch(Constants.USER1, coupons, new bytes(0));

        Types.Coupon[] memory couponsToBurn = new Types.Coupon[](2);
        couponsToBurn[0] = Coupon.from(Constants.USDC, startEpoch, 50);
        couponsToBurn[1] = Coupon.from(Constants.USDC, startEpoch.add(1), 30);

        vm.expectRevert(bytes(Errors.ACCESS));
        vm.prank(Constants.USER2);
        couponManager.burnBatch(Constants.USER1, couponsToBurn);

        vm.expectRevert(bytes(Errors.ACCESS));
        vm.prank(Constants.USER1);
        couponManager.burnBatch(Constants.USER1, couponsToBurn);
    }
}
