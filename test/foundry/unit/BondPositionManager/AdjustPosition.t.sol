// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {
    IBondPositionManager, IBondPositionManagerTypes
} from "../../../../contracts/interfaces/IBondPositionManager.sol";
import {IAssetPool} from "../../../../contracts/interfaces/IAssetPool.sol";
import {ICouponManager} from "../../../../contracts/interfaces/ICouponManager.sol";
import {Coupon, CouponLibrary} from "../../../../contracts/libraries/Coupon.sol";
import {Epoch, EpochLibrary} from "../../../../contracts/libraries/Epoch.sol";
import {BondPosition} from "../../../../contracts/libraries/BondPosition.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";
import {MockAssetPool} from "../../mocks/MockAssetPool.sol";
import {TestInitializer} from "./helpers/TestInitializer.sol";
import {BondPositionMintHelper} from "./helpers/MintHelper.sol";
import {BondPositionAdjustPositionHelper} from "./helpers/AdjustPositionHelper.sol";

contract BondPositionManagerAdjustPositionUnitTest is Test, IBondPositionManagerTypes, ERC1155Holder {
    using EpochLibrary for Epoch;

    MockERC20 public usdc;

    MockAssetPool public assetPool;
    ICouponManager public couponManager;
    IBondPositionManager public bondPositionManager;

    Epoch public startEpoch;
    uint256 public initialAmount;

    BondPositionAdjustPositionHelper public helper;

    uint256 public tokenId;

    function setUp() public {
        TestInitializer.Params memory p = TestInitializer.init(vm);
        usdc = p.usdc;
        assetPool = p.assetPool;
        couponManager = p.couponManager;
        bondPositionManager = p.bondPositionManager;
        startEpoch = p.startEpoch;
        initialAmount = p.initialAmount;

        helper = new BondPositionAdjustPositionHelper(address(bondPositionManager), address(couponManager));
        vm.startPrank(address(helper));
        usdc.approve(address(bondPositionManager), type(uint256).max);
        vm.stopPrank();
        bondPositionManager.setApprovalForAll(address(helper), true);

        couponManager.setApprovalForAll(address(helper), true);
        usdc.approve(address(helper), type(uint256).max);

        BondPositionMintHelper minter = new BondPositionMintHelper(address(bondPositionManager));
        usdc.approve(address(minter), type(uint256).max);
        tokenId = minter.mint(address(usdc), initialAmount, startEpoch.add(2), address(this));
        vm.warp(startEpoch.add(1).startTime());
    }

    function testAdjustPositionIncreaseAmountAndEpochs() public {
        uint256 increaseAmount = usdc.amount(70);
        Epoch expiredWith = startEpoch.add(5);

        uint256 beforeThisBalance = usdc.balanceOf(address(this));
        BondPosition memory beforePosition = bondPositionManager.getPosition(tokenId);

        Coupon[] memory coupons = new Coupon[](5);
        coupons[0] = CouponLibrary.from(address(usdc), startEpoch.add(1), increaseAmount);
        coupons[1] = CouponLibrary.from(address(usdc), startEpoch.add(2), increaseAmount);
        coupons[2] = CouponLibrary.from(address(usdc), startEpoch.add(3), usdc.amount(170));
        coupons[3] = CouponLibrary.from(address(usdc), startEpoch.add(4), usdc.amount(170));
        coupons[4] = CouponLibrary.from(address(usdc), startEpoch.add(5), usdc.amount(170));
        vm.expectCall(
            address(couponManager), abi.encodeCall(ICouponManager.mintBatch, (address(this), coupons, new bytes(0))), 1
        );
        vm.expectCall(
            address(couponManager), abi.encodeCall(ICouponManager.burnBatch, (address(helper), new Coupon[](0))), 0
        );
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, initialAmount + increaseAmount, expiredWith);
        helper.adjustPosition(tokenId, initialAmount + increaseAmount, expiredWith);

        BondPosition memory afterPosition = bondPositionManager.getPosition(tokenId);

        assertEq(usdc.balanceOf(address(this)), beforeThisBalance - increaseAmount, "THIS_BALANCE");
        assertEq(afterPosition.amount, beforePosition.amount + increaseAmount, "LOCKED_AMOUNT");
        assertEq(afterPosition.expiredWith, expiredWith, "EXPIRED_WITH");
    }

    function testAdjustPositionIncreaseAmountAndDecreaseEpochs() public {
        uint256 increaseAmount = usdc.amount(70);
        Epoch expiredWith = startEpoch.add(1);

        uint256 beforeThisBalance = usdc.balanceOf(address(this));
        BondPosition memory beforePosition = bondPositionManager.getPosition(tokenId);

        Coupon[] memory couponsToMint = new Coupon[](1);
        couponsToMint[0] = CouponLibrary.from(address(usdc), startEpoch.add(1), increaseAmount);
        Coupon[] memory couponsToBurn = new Coupon[](1);
        couponsToBurn[0] = CouponLibrary.from(address(usdc), startEpoch.add(2), initialAmount);
        vm.expectCall(
            address(couponManager),
            abi.encodeCall(ICouponManager.mintBatch, (address(this), couponsToMint, new bytes(0))),
            1
        );
        vm.expectCall(
            address(couponManager), abi.encodeCall(ICouponManager.burnBatch, (address(helper), couponsToBurn)), 1
        );
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, initialAmount + increaseAmount, expiredWith);
        helper.adjustPosition(tokenId, initialAmount + increaseAmount, expiredWith);

        BondPosition memory afterPosition = bondPositionManager.getPosition(tokenId);

        assertEq(usdc.balanceOf(address(this)), beforeThisBalance - increaseAmount, "THIS_BALANCE");
        assertEq(afterPosition.amount, beforePosition.amount + increaseAmount, "LOCKED_AMOUNT");
        assertEq(afterPosition.expiredWith, expiredWith, "EXPIRED_WITH");
    }

    function testAdjustPositionDecreaseAmountAndIncreaseEpochs() public {
        uint256 decreaseAmount = usdc.amount(70);
        uint256 amount = initialAmount - decreaseAmount;
        Epoch expiredWith = startEpoch.add(5);

        BondPosition memory beforePosition = bondPositionManager.getPosition(tokenId);

        Coupon[] memory couponsToMint = new Coupon[](3);
        couponsToMint[0] = CouponLibrary.from(address(usdc), startEpoch.add(3), amount);
        couponsToMint[1] = CouponLibrary.from(address(usdc), startEpoch.add(4), amount);
        couponsToMint[2] = CouponLibrary.from(address(usdc), startEpoch.add(5), amount);
        Coupon[] memory couponsToBurn = new Coupon[](2);
        couponsToBurn[0] = CouponLibrary.from(address(usdc), startEpoch.add(1), decreaseAmount);
        couponsToBurn[1] = CouponLibrary.from(address(usdc), startEpoch.add(2), decreaseAmount);
        vm.expectCall(
            address(couponManager),
            abi.encodeCall(ICouponManager.mintBatch, (address(this), couponsToMint, new bytes(0))),
            1
        );
        vm.expectCall(
            address(couponManager), abi.encodeCall(ICouponManager.burnBatch, (address(helper), couponsToBurn)), 1
        );
        vm.expectCall(
            address(assetPool), abi.encodeCall(IAssetPool.withdraw, (address(usdc), decreaseAmount, address(this))), 1
        );
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, amount, expiredWith);
        helper.adjustPosition(tokenId, amount, expiredWith);

        BondPosition memory afterPosition = bondPositionManager.getPosition(tokenId);

        assertEq(afterPosition.amount, beforePosition.amount - decreaseAmount, "LOCKED_AMOUNT");
        assertEq(afterPosition.expiredWith, expiredWith, "EXPIRED_WITH");
    }

    function testAdjustPositionDecreaseAmountAndEpochs() public {
        uint256 decreaseAmount = usdc.amount(70);
        uint256 amount = initialAmount - decreaseAmount;
        Epoch expiredWith = startEpoch.add(1);

        BondPosition memory beforePosition = bondPositionManager.getPosition(tokenId);

        Coupon[] memory coupons = new Coupon[](2);
        coupons[0] = CouponLibrary.from(address(usdc), startEpoch.add(1), decreaseAmount);
        coupons[1] = CouponLibrary.from(address(usdc), startEpoch.add(2), initialAmount);

        vm.expectCall(
            address(couponManager),
            abi.encodeCall(ICouponManager.mintBatch, (address(this), new Coupon[](0), new bytes(0))),
            0
        );
        vm.expectCall(address(couponManager), abi.encodeCall(ICouponManager.burnBatch, (address(helper), coupons)), 1);
        vm.expectCall(
            address(assetPool), abi.encodeCall(IAssetPool.withdraw, (address(usdc), decreaseAmount, address(this))), 1
        );
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, amount, expiredWith);
        helper.adjustPosition(tokenId, amount, expiredWith);

        BondPosition memory afterPosition = bondPositionManager.getPosition(tokenId);

        assertEq(afterPosition.amount, beforePosition.amount - decreaseAmount, "LOCKED_AMOUNT");
        assertEq(afterPosition.expiredWith, expiredWith, "EXPIRED_WITH");
    }

    function testAdjustPositionDecreaseAmountToZero() public {
        uint256 beforeBondPositionBalance = bondPositionManager.balanceOf(address(this));

        Coupon[] memory coupons = new Coupon[](2);
        coupons[0] = CouponLibrary.from(address(usdc), startEpoch.add(1), initialAmount);
        coupons[1] = CouponLibrary.from(address(usdc), startEpoch.add(2), initialAmount);
        vm.expectCall(
            address(couponManager),
            abi.encodeCall(ICouponManager.mintBatch, (address(this), new Coupon[](0), new bytes(0))),
            0
        );
        vm.expectCall(address(couponManager), abi.encodeCall(ICouponManager.burnBatch, (address(helper), coupons)), 1);
        vm.expectCall(
            address(assetPool), abi.encodeCall(IAssetPool.withdraw, (address(usdc), initialAmount, address(this))), 1
        );
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, 0, startEpoch);
        helper.adjustPosition(tokenId, 0, startEpoch);

        BondPosition memory afterPosition = bondPositionManager.getPosition(tokenId);

        assertEq(bondPositionManager.balanceOf(address(this)), beforeBondPositionBalance - 1, "BOND_POSITION_BALANCE");
        assertEq(afterPosition.amount, 0, "LOCKED_AMOUNT");
        assertEq(afterPosition.expiredWith, startEpoch, "EXPIRED_WITH");
        vm.expectRevert("ERC721: invalid token ID");
        bondPositionManager.ownerOf(tokenId);
    }

    function testAdjustPositionDecreaseEpochsToPastEpochWhenAmountIsNotZero() public {
        Epoch epoch = EpochLibrary.current().sub(1);
        vm.expectRevert(abi.encodeWithSelector(InvalidEpoch.selector));
        helper.adjustPosition(tokenId, initialAmount, epoch);

        epoch = EpochLibrary.current().sub(2);
        vm.expectRevert(abi.encodeWithSelector(InvalidEpoch.selector));
        helper.adjustPosition(tokenId, initialAmount, epoch);
    }

    function testAdjustPositionWithExpiredPosition() public {
        vm.warp(startEpoch.add(10).startTime());

        vm.expectRevert(abi.encodeWithSelector(InvalidEpoch.selector));
        helper.adjustPosition(tokenId, initialAmount - 100, startEpoch.add(2));
    }

    function testAdjustPositionOwnership() public {
        bondPositionManager.setApprovalForAll(address(helper), false);
        vm.expectRevert(abi.encodeWithSelector(InvalidAccess.selector));
        helper.adjustPosition(tokenId, initialAmount + 12342, startEpoch.add(3));
    }

    function testAdjustPositionWithInvalidTokenId() public {
        vm.expectRevert("ERC721: invalid token ID");
        helper.adjustPosition(123, initialAmount + 12342, startEpoch.add(3));
    }

    function testAdjustPositionToOverMaxEpoch() public {
        Epoch epoch = Epoch.wrap(type(uint8).max);
        vm.expectRevert(abi.encodeWithSelector(InvalidEpoch.selector));
        helper.adjustPosition(tokenId, initialAmount, epoch);

        epoch = bondPositionManager.getMaxEpoch().add(1);
        vm.expectRevert(abi.encodeWithSelector(InvalidEpoch.selector));
        helper.adjustPosition(tokenId, initialAmount, epoch);
    }

    function assertEq(Epoch e1, Epoch e2, string memory err) internal {
        assertEq(e1.unwrap(), e2.unwrap(), err);
    }
}
