// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {Types} from "../../../contracts/Types.sol";
import {IBondPosition, IBondPositionEvents} from "../../../contracts/interfaces/IBondPosition.sol";
import {INewCoupon} from "../../../contracts/interfaces/INewCoupon.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockYieldFarmer} from "../mocks/MockYieldFarmer.sol";
import {Constants} from "./Constants.sol";

contract BondPositionUnitTest is Test, IBondPositionEvents {
    MockERC20 public usdc;

    MockYieldFarmer public yieldFarmer;
    INewCoupon public coupon;
    IBondPosition public bondPosition;

    uint256 private _snapshotId;
    Types.PermitParams private _permitParams;

    uint256 private _initialAmount;

    function setUp() public {
        usdc = new MockERC20("USD coin", "USDC", 6);

        usdc.mint(address(this), usdc.amount(1_000_000_000));

        _initialAmount = usdc.amount(100);
        yieldFarmer = new MockYieldFarmer();
        // bondPosition = new BondPosition();

        usdc.approve(address(bondPosition), type(uint256).max);
    }

    function testMint() public {
        uint256 amount = _initialAmount;
        uint256 beforeThisBalance = usdc.balanceOf(address(this));
        uint256 beforeUserPositionBalance = bondPosition.balanceOf(Constants.USER1);
        uint256 nextId = bondPosition.nextId();
        uint256 expectedUnlockedAt = coupon.epochEndTime(2);

        _snapshotId = vm.snapshot();
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(nextId + 1, amount, expectedUnlockedAt);
        bondPosition.mint(address(usdc), amount, 2, Constants.USER1, new bytes(0));
        vm.revertTo(_snapshotId);
        Types.Coupon[] memory coupons = new Types.Coupon[](2);
        coupons[0] = Types.Coupon({key: Types.CouponKey({asset: address(usdc), epoch: 1}), amount: amount});
        coupons[1] = Types.Coupon({key: Types.CouponKey({asset: address(usdc), epoch: 2}), amount: amount});
        vm.expectCall(address(coupon), abi.encodeCall(INewCoupon.mintBatch, (Constants.USER1, coupons, new bytes(0))));
        uint256 tokenId = bondPosition.mint(address(usdc), amount, 2, Constants.USER1, new bytes(0));

        Types.Bond memory bond = bondPosition.bonds(tokenId);

        assertEq(tokenId, nextId, "TOKEN_ID");
        assertEq(usdc.balanceOf(address(this)), beforeThisBalance - amount, "THIS_BALANCE");
        assertEq(bondPosition.balanceOf(Constants.USER1), beforeUserPositionBalance + 1, "USER_BALANCE");
        assertEq(bondPosition.nextId(), nextId + 1, "NEXT_ID");
        assertEq(bondPosition.ownerOf(tokenId), Constants.USER1, "OWNER");
        assertEq(bond.asset, address(usdc), "ASSET");
        assertEq(bond.amount, amount, "LOCKED_AMOUNT");
        assertEq(bond.unlockedAt, expectedUnlockedAt, "UNLOCKED_AT");
    }

    function testMintWithUnregisteredToken() public {
        vm.expectRevert("Unregistered asset");
        bondPosition.mint(address(0x123), _initialAmount, 2, Constants.USER1, new bytes(0));
    }

    function _beforeAdjustPosition() internal returns (uint256 tokenId) {
        tokenId = bondPosition.mint(address(usdc), _initialAmount, 3, address(this), new bytes(0));
        vm.warp(block.timestamp + coupon.epochDuration());
    }

    function testAdjustPositionIncreaseAmountAndEpochs() public {
        uint256 tokenId = _beforeAdjustPosition();

        uint256 amount = usdc.amount(70);
        uint256 epochs = 3;
        uint256 expectedUnlockedAt = coupon.epochEndTime(6);

        uint256 beforeThisBalance = usdc.balanceOf(address(this));
        Types.Bond memory beforeBond = bondPosition.bonds(tokenId);

        _snapshotId = vm.snapshot();
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, _initialAmount + amount, expectedUnlockedAt);
        bondPosition.adjustPosition(tokenId, int256(amount), int256(epochs), new bytes(0));
        vm.revertTo(_snapshotId);
        Types.Coupon[] memory coupons = new Types.Coupon[](5);
        coupons[0] = Types.Coupon({key: Types.CouponKey({asset: address(usdc), epoch: 2}), amount: amount});
        coupons[1] = Types.Coupon({key: Types.CouponKey({asset: address(usdc), epoch: 3}), amount: amount});
        coupons[2] = Types.Coupon({key: Types.CouponKey({asset: address(usdc), epoch: 4}), amount: usdc.amount(170)});
        coupons[3] = Types.Coupon({key: Types.CouponKey({asset: address(usdc), epoch: 5}), amount: usdc.amount(170)});
        coupons[4] = Types.Coupon({key: Types.CouponKey({asset: address(usdc), epoch: 6}), amount: usdc.amount(170)});
        vm.expectCall(address(coupon), abi.encodeCall(INewCoupon.mintBatch, (address(this), coupons, new bytes(0))));
        bondPosition.adjustPosition(tokenId, int256(amount), int256(epochs), new bytes(0));

        Types.Bond memory afterBond = bondPosition.bonds(tokenId);

        assertEq(usdc.balanceOf(address(this)), beforeThisBalance - amount, "THIS_BALANCE");
        assertEq(afterBond.amount, beforeBond.amount + amount, "LOCKED_AMOUNT");
        assertEq(afterBond.unlockedAt, expectedUnlockedAt, "UNLOCKED_AT");
    }

    function testAdjustPositionIncreaseAmountAndDecreaseEpochs() public {
        uint256 tokenId = _beforeAdjustPosition();

        uint256 amount = usdc.amount(70);
        uint256 epochs = 1;
        uint256 expectedUnlockedAt = coupon.epochEndTime(2);

        uint256 beforeThisBalance = usdc.balanceOf(address(this));
        Types.Bond memory beforeBond = bondPosition.bonds(tokenId);

        _snapshotId = vm.snapshot();
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, _initialAmount + amount, expectedUnlockedAt);
        bondPosition.adjustPosition(tokenId, int256(amount), -int256(epochs), new bytes(0));
        vm.revertTo(_snapshotId);
        Types.Coupon[] memory coupons = new Types.Coupon[](1);
        coupons[0] = Types.Coupon({key: Types.CouponKey({asset: address(usdc), epoch: 2}), amount: amount});
        vm.expectCall(address(coupon), abi.encodeCall(INewCoupon.mintBatch, (address(this), coupons, new bytes(0))));
        bondPosition.adjustPosition(tokenId, int256(amount), -int256(epochs), new bytes(0));
        vm.revertTo(_snapshotId);
        coupons = new Types.Coupon[](1);
        coupons[0] = Types.Coupon({key: Types.CouponKey({asset: address(usdc), epoch: 3}), amount: _initialAmount});
        vm.expectCall(address(coupon), abi.encodeCall(INewCoupon.burnBatch, (address(this), coupons)));
        bondPosition.adjustPosition(tokenId, int256(amount), -int256(epochs), new bytes(0));

        Types.Bond memory afterBond = bondPosition.bonds(tokenId);

        assertEq(usdc.balanceOf(address(this)), beforeThisBalance - amount, "THIS_BALANCE");
        assertEq(afterBond.amount, beforeBond.amount + amount, "LOCKED_AMOUNT");
        assertEq(afterBond.unlockedAt, expectedUnlockedAt, "UNLOCKED_AT");
    }

    function testAdjustPositionDecreaseAmountAndIncreaseEpochs() public {
        uint256 tokenId = _beforeAdjustPosition();

        uint256 amount = usdc.amount(70);
        uint256 epochs = 3;
        uint256 expectedAmount = _initialAmount - amount;
        uint256 expectedUnlockedAt = coupon.epochEndTime(6);

        uint256 beforeThisBalance = usdc.balanceOf(address(this));
        Types.Bond memory beforeBond = bondPosition.bonds(tokenId);

        _snapshotId = vm.snapshot();
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, expectedAmount, expectedUnlockedAt);
        bondPosition.adjustPosition(tokenId, -int256(amount), int256(epochs), new bytes(0));
        vm.revertTo(_snapshotId);
        Types.Coupon[] memory coupons = new Types.Coupon[](3);
        coupons[0] = Types.Coupon({key: Types.CouponKey({asset: address(usdc), epoch: 4}), amount: expectedAmount});
        coupons[1] = Types.Coupon({key: Types.CouponKey({asset: address(usdc), epoch: 5}), amount: expectedAmount});
        coupons[2] = Types.Coupon({key: Types.CouponKey({asset: address(usdc), epoch: 6}), amount: expectedAmount});
        vm.expectCall(address(coupon), abi.encodeCall(INewCoupon.mintBatch, (address(this), coupons, new bytes(0))));
        bondPosition.adjustPosition(tokenId, -int256(amount), int256(epochs), new bytes(0));
        vm.revertTo(_snapshotId);
        coupons = new Types.Coupon[](2);
        coupons[0] = Types.Coupon({key: Types.CouponKey({asset: address(usdc), epoch: 2}), amount: amount});
        coupons[1] = Types.Coupon({key: Types.CouponKey({asset: address(usdc), epoch: 3}), amount: amount});
        vm.expectCall(address(coupon), abi.encodeCall(INewCoupon.burnBatch, (address(this), coupons)));
        bondPosition.adjustPosition(tokenId, -int256(amount), int256(epochs), new bytes(0));

        Types.Bond memory afterBond = bondPosition.bonds(tokenId);

        assertEq(usdc.balanceOf(address(this)), beforeThisBalance + amount, "THIS_BALANCE");
        assertEq(afterBond.amount, beforeBond.amount - amount, "LOCKED_AMOUNT");
        assertEq(afterBond.unlockedAt, expectedUnlockedAt, "UNLOCKED_AT");
    }

    function testAdjustPositionDecreaseAmountAndEpochs() public {
        uint256 tokenId = _beforeAdjustPosition();

        uint256 amount = usdc.amount(70);
        uint256 epochs = 1;
        uint256 expectedAmount = _initialAmount - amount;
        uint256 expectedUnlockedAt = coupon.epochEndTime(2);

        uint256 beforeThisBalance = usdc.balanceOf(address(this));
        Types.Bond memory beforeBond = bondPosition.bonds(tokenId);

        _snapshotId = vm.snapshot();
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, expectedAmount, expectedUnlockedAt);
        bondPosition.adjustPosition(tokenId, -int256(amount), -int256(epochs), new bytes(0));
        vm.revertTo(_snapshotId);
        Types.Coupon[] memory coupons = new Types.Coupon[](2);
        coupons[0] = Types.Coupon({key: Types.CouponKey({asset: address(usdc), epoch: 2}), amount: amount});
        coupons[1] = Types.Coupon({key: Types.CouponKey({asset: address(usdc), epoch: 3}), amount: _initialAmount});
        vm.expectCall(address(coupon), abi.encodeCall(INewCoupon.burnBatch, (address(this), coupons)));
        bondPosition.adjustPosition(tokenId, -int256(amount), -int256(epochs), new bytes(0));

        Types.Bond memory afterBond = bondPosition.bonds(tokenId);

        assertEq(usdc.balanceOf(address(this)), beforeThisBalance + amount, "THIS_BALANCE");
        assertEq(afterBond.amount, beforeBond.amount - amount, "LOCKED_AMOUNT");
        assertEq(afterBond.unlockedAt, expectedUnlockedAt, "UNLOCKED_AT");
    }

    function testAdjustPositionDecreaseAmountToZero() public {
        uint256 tokenId = _beforeAdjustPosition();

        uint256 beforeThisBalance = usdc.balanceOf(address(this));
        uint256 beforeBondPositionBalance = bondPosition.balanceOf(address(this));
        Types.Bond memory beforeBond = bondPosition.bonds(tokenId);

        _snapshotId = vm.snapshot();
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, 0, 0);
        bondPosition.adjustPosition(tokenId, -int256(_initialAmount), int256(1), new bytes(0));
        vm.revertTo(_snapshotId);
        Types.Coupon[] memory coupons = new Types.Coupon[](2);
        coupons[0] = Types.Coupon({key: Types.CouponKey({asset: address(usdc), epoch: 2}), amount: _initialAmount});
        coupons[1] = Types.Coupon({key: Types.CouponKey({asset: address(usdc), epoch: 3}), amount: _initialAmount});
        vm.expectCall(address(coupon), abi.encodeCall(INewCoupon.burnBatch, (address(this), coupons)));
        bondPosition.adjustPosition(tokenId, -int256(_initialAmount), int256(1), new bytes(0));

        Types.Bond memory afterBond = bondPosition.bonds(tokenId);

        assertEq(usdc.balanceOf(address(this)), beforeThisBalance + _initialAmount, "THIS_BALANCE");
        assertEq(bondPosition.balanceOf(address(this)), beforeBondPositionBalance - 1, "BOND_POSITION_BALANCE");
        assertEq(afterBond.amount, 0, "LOCKED_AMOUNT");
        assertEq(afterBond.unlockedAt, coupon.epochEndTime(1), "UNLOCKED_AT");
        vm.expectRevert("ERC721: invalid token ID");
        bondPosition.ownerOf(tokenId);
    }

    function testAdjustPositionDecreaseEpochsToCurrentEpoch() public {
        uint256 tokenId = _beforeAdjustPosition();

        uint256 beforeThisBalance = usdc.balanceOf(address(this));
        uint256 beforeBondPositionBalance = bondPosition.balanceOf(address(this));
        Types.Bond memory beforeBond = bondPosition.bonds(tokenId);

        _snapshotId = vm.snapshot();
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, 0, 0);
        bondPosition.adjustPosition(tokenId, int256(1231), -int256(2), new bytes(0));
        vm.revertTo(_snapshotId);
        Types.Coupon[] memory coupons = new Types.Coupon[](2);
        coupons[0] = Types.Coupon({key: Types.CouponKey({asset: address(usdc), epoch: 2}), amount: _initialAmount});
        coupons[1] = Types.Coupon({key: Types.CouponKey({asset: address(usdc), epoch: 3}), amount: _initialAmount});
        vm.expectCall(address(coupon), abi.encodeCall(INewCoupon.burnBatch, (address(this), coupons)));
        bondPosition.adjustPosition(tokenId, int256(3242), -int256(2), new bytes(0));

        Types.Bond memory afterBond = bondPosition.bonds(tokenId);

        assertEq(usdc.balanceOf(address(this)), beforeThisBalance, "THIS_BALANCE");
        assertEq(bondPosition.balanceOf(address(this)), beforeBondPositionBalance - 1, "BOND_POSITION_BALANCE");
        assertEq(afterBond.amount, 0, "LOCKED_AMOUNT");
        assertEq(afterBond.unlockedAt, coupon.epochEndTime(1), "UNLOCKED_AT");
        vm.expectRevert("ERC721: invalid token ID");
        bondPosition.ownerOf(tokenId);
    }

    function testAdjustPositionWhenProtocolHasInsufficientAmount() public {
        uint256 tokenId = _beforeAdjustPosition();
        uint256 limitBalance = usdc.amount(20);
        yieldFarmer.setWithdrawLimit(address(usdc), limitBalance);

        uint256 expectedAmount = limitBalance;
        uint256 expectedUnlockedAt = coupon.epochEndTime(2);

        uint256 beforeThisBalance = usdc.balanceOf(address(this));
        Types.Bond memory beforeBond = bondPosition.bonds(tokenId);

        _snapshotId = vm.snapshot();
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, expectedAmount, expectedUnlockedAt);
        bondPosition.adjustPosition(tokenId, -int256(_initialAmount), -int256(2), new bytes(0));
        vm.revertTo(_snapshotId);
        Types.Coupon[] memory coupons = new Types.Coupon[](2);
        coupons[0] = Types.Coupon({
            key: Types.CouponKey({asset: address(usdc), epoch: 2}),
            amount: _initialAmount - limitBalance
        });
        coupons[1] = Types.Coupon({key: Types.CouponKey({asset: address(usdc), epoch: 3}), amount: _initialAmount});
        vm.expectCall(address(coupon), abi.encodeCall(INewCoupon.burnBatch, (address(this), coupons)));
        bondPosition.adjustPosition(tokenId, -int256(_initialAmount), -int256(2), new bytes(0));

        Types.Bond memory afterBond = bondPosition.bonds(tokenId);

        assertEq(usdc.balanceOf(address(this)), beforeThisBalance + (_initialAmount - limitBalance), "THIS_BALANCE");
        assertEq(afterBond.amount, beforeBond.amount - (_initialAmount - limitBalance), "LOCKED_AMOUNT");
        assertEq(afterBond.unlockedAt, expectedUnlockedAt, "UNLOCKED_AT");
    }

    function testAdjustPositionOwnership() public {
        uint256 tokenId = _beforeAdjustPosition();

        vm.expectRevert("ERC721: transfer caller is not owner nor approved");
        bondPosition.adjustPosition(tokenId, int256(12412), int256(2), new bytes(0));
    }

    function testAdjustPositionWithInvalidTokenId() public {
        vm.expectRevert("ERC721: invalid token ID");
        bondPosition.adjustPosition(123, int256(12412), int256(2), new bytes(0));
    }
}
