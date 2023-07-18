// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {Create1} from "@clober/library/contracts/Create1.sol";

import {Errors} from "../../../contracts/Errors.sol";
import {Types} from "../../../contracts/Types.sol";
import {CouponManager} from "../../../contracts/CouponManager.sol";
import {BondPosition} from "../../../contracts/BondPosition.sol";
import {IBondPosition, IBondPositionEvents} from "../../../contracts/interfaces/IBondPosition.sol";
import {ICouponManager} from "../../../contracts/interfaces/ICouponManager.sol";
import {Coupon} from "../../../contracts/libraries/Coupon.sol";
import {Epoch} from "../../../contracts/libraries/Epoch.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockAssetPool} from "../mocks/MockAssetPool.sol";
import {Constants} from "../Constants.sol";
import {Utils} from "../Utils.sol";

contract BondPositionUnitTest is Test, IBondPositionEvents, ERC1155Holder, ERC721Holder {
    using Coupon for Types.Coupon;
    using Epoch for Types.Epoch;

    MockERC20 public usdc;

    MockAssetPool public assetPool;
    ICouponManager public coupon;
    IBondPosition public bondPosition;

    Types.Epoch public startEpoch;
    uint256 public initialAmount;

    function setUp() public {
        usdc = new MockERC20("USD coin", "USDC", 6);

        usdc.mint(address(this), usdc.amount(1_000_000_000));

        vm.warp(Epoch.fromMonths(10).startTime());
        startEpoch = Epoch.current();

        initialAmount = usdc.amount(100);
        assetPool = new MockAssetPool();
        uint64 thisNonce = vm.getNonce(address(this));
        coupon = new CouponManager(Create1.computeAddress(address(this), thisNonce + 1), "URI/");
        bondPosition = new BondPosition(
            address(coupon),
            address(assetPool),
            "bond/position/uri/",
            Utils.toArr(address(usdc))
        );

        usdc.approve(address(bondPosition), type(uint256).max);
    }

    function testMint() public {
        uint256 amount = initialAmount;
        uint256 beforeThisBalance = usdc.balanceOf(address(this));
        uint256 beforeUserPositionBalance = bondPosition.balanceOf(Constants.USER1);
        uint256 nextId = bondPosition.nextId();
        Types.Epoch expectedExpiredWith = startEpoch.add(1);

        Types.Coupon[] memory coupons = new Types.Coupon[](2);
        coupons[0] = Coupon.from(address(usdc), startEpoch, amount);
        coupons[1] = Coupon.from(address(usdc), startEpoch.add(1), amount);
        vm.expectCall(
            address(coupon),
            abi.encodeCall(ICouponManager.mintBatch, (Constants.USER1, coupons, new bytes(0)))
        );
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(nextId, amount, expectedExpiredWith);
        uint256 tokenId = bondPosition.mint(address(usdc), amount, 2, Constants.USER1, new bytes(0));

        Types.Bond memory bond = bondPosition.bonds(tokenId);

        assertEq(tokenId, nextId, "TOKEN_ID");
        assertEq(usdc.balanceOf(address(this)), beforeThisBalance - amount, "THIS_BALANCE");
        assertEq(bondPosition.balanceOf(Constants.USER1), beforeUserPositionBalance + 1, "USER_BALANCE");
        assertEq(bondPosition.nextId(), nextId + 1, "NEXT_ID");
        assertEq(bondPosition.ownerOf(tokenId), Constants.USER1, "OWNER");
        assertEq(bond.asset, address(usdc), "ASSET");
        assertEq(bond.amount, amount, "LOCKED_AMOUNT");
        assertEq(bond.expiredWith, expectedExpiredWith, "EXPIRED_WITH");
    }

    function testMintWithUnregisteredToken() public {
        vm.expectRevert(bytes(Errors.UNREGISTERED_ASSET));
        bondPosition.mint(address(0x123), initialAmount, 2, Constants.USER1, new bytes(0));
    }

    function _beforeAdjustPosition() internal returns (uint256 tokenId) {
        tokenId = bondPosition.mint(address(usdc), initialAmount, 3, address(this), new bytes(0));
        vm.warp(startEpoch.add(1).startTime());
    }

    function testAdjustPositionIncreaseAmountAndEpochs() public {
        uint256 tokenId = _beforeAdjustPosition();

        uint256 amount = usdc.amount(70);
        uint16 epochs = 3;
        Types.Epoch expectedExpiredWith = startEpoch.add(5);

        uint256 beforeThisBalance = usdc.balanceOf(address(this));
        Types.Bond memory beforeBond = bondPosition.bonds(tokenId);

        Types.Coupon[] memory coupons = new Types.Coupon[](5);
        coupons[0] = Coupon.from(address(usdc), startEpoch.add(1), amount);
        coupons[1] = Coupon.from(address(usdc), startEpoch.add(2), amount);
        coupons[2] = Coupon.from(address(usdc), startEpoch.add(3), usdc.amount(170));
        coupons[3] = Coupon.from(address(usdc), startEpoch.add(4), usdc.amount(170));
        coupons[4] = Coupon.from(address(usdc), startEpoch.add(5), usdc.amount(170));
        vm.expectCall(
            address(coupon),
            abi.encodeCall(ICouponManager.mintBatch, (address(this), coupons, new bytes(0)))
        );
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, initialAmount + amount, expectedExpiredWith);
        bondPosition.adjustPosition(tokenId, int256(amount), int16(epochs), new bytes(0));

        Types.Bond memory afterBond = bondPosition.bonds(tokenId);

        assertEq(usdc.balanceOf(address(this)), beforeThisBalance - amount, "THIS_BALANCE");
        assertEq(afterBond.amount, beforeBond.amount + amount, "LOCKED_AMOUNT");
        assertEq(afterBond.expiredWith, expectedExpiredWith, "EXPIRED_WITH");
    }

    function testAdjustPositionIncreaseAmountAndDecreaseEpochs() public {
        uint256 tokenId = _beforeAdjustPosition();

        uint256 amount = usdc.amount(70);
        uint16 epochs = 1;
        Types.Epoch expectedExpiredWith = startEpoch.add(1);

        uint256 beforeThisBalance = usdc.balanceOf(address(this));
        Types.Bond memory beforeBond = bondPosition.bonds(tokenId);

        Types.Coupon[] memory couponsToMint = new Types.Coupon[](1);
        couponsToMint[0] = Coupon.from(address(usdc), startEpoch.add(1), amount);
        Types.Coupon[] memory couponsToBurn = new Types.Coupon[](1);
        couponsToBurn[0] = Coupon.from(address(usdc), startEpoch.add(2), initialAmount);
        vm.expectCall(
            address(coupon),
            abi.encodeCall(ICouponManager.mintBatch, (address(this), couponsToMint, new bytes(0)))
        );
        vm.expectCall(address(coupon), abi.encodeCall(ICouponManager.burnBatch, (address(this), couponsToBurn)));
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, initialAmount + amount, expectedExpiredWith);
        bondPosition.adjustPosition(tokenId, int256(amount), -int16(epochs), new bytes(0));

        Types.Bond memory afterBond = bondPosition.bonds(tokenId);

        assertEq(usdc.balanceOf(address(this)), beforeThisBalance - amount, "THIS_BALANCE");
        assertEq(afterBond.amount, beforeBond.amount + amount, "LOCKED_AMOUNT");
        assertEq(afterBond.expiredWith, expectedExpiredWith, "EXPIRED_WITH");
    }

    function testAdjustPositionDecreaseAmountAndIncreaseEpochs() public {
        uint256 tokenId = _beforeAdjustPosition();

        uint256 amount = usdc.amount(70);
        uint16 epochs = 3;
        uint256 expectedAmount = initialAmount - amount;
        Types.Epoch expectedExpiredWith = startEpoch.add(5);

        uint256 beforeThisBalance = usdc.balanceOf(address(this));
        Types.Bond memory beforeBond = bondPosition.bonds(tokenId);

        Types.Coupon[] memory couponsToMint = new Types.Coupon[](3);
        couponsToMint[0] = Coupon.from(address(usdc), startEpoch.add(3), expectedAmount);
        couponsToMint[1] = Coupon.from(address(usdc), startEpoch.add(4), expectedAmount);
        couponsToMint[2] = Coupon.from(address(usdc), startEpoch.add(5), expectedAmount);
        Types.Coupon[] memory couponsToBurn = new Types.Coupon[](2);
        couponsToBurn[0] = Coupon.from(address(usdc), startEpoch.add(1), amount);
        couponsToBurn[1] = Coupon.from(address(usdc), startEpoch.add(2), amount);
        vm.expectCall(
            address(coupon),
            abi.encodeCall(ICouponManager.mintBatch, (address(this), couponsToMint, new bytes(0)))
        );
        vm.expectCall(address(coupon), abi.encodeCall(ICouponManager.burnBatch, (address(this), couponsToBurn)));
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, expectedAmount, expectedExpiredWith);
        bondPosition.adjustPosition(tokenId, -int256(amount), int16(epochs), new bytes(0));

        Types.Bond memory afterBond = bondPosition.bonds(tokenId);

        assertEq(usdc.balanceOf(address(this)), beforeThisBalance + amount, "THIS_BALANCE");
        assertEq(afterBond.amount, beforeBond.amount - amount, "LOCKED_AMOUNT");
        assertEq(afterBond.expiredWith, expectedExpiredWith, "EXPIRED_WITH");
    }

    function testAdjustPositionDecreaseAmountAndEpochs() public {
        uint256 tokenId = _beforeAdjustPosition();

        uint256 amount = usdc.amount(70);
        uint16 epochs = 1;
        uint256 expectedAmount = initialAmount - amount;
        Types.Epoch expectedExpiredWith = startEpoch.add(1);

        uint256 beforeThisBalance = usdc.balanceOf(address(this));
        Types.Bond memory beforeBond = bondPosition.bonds(tokenId);

        Types.Coupon[] memory coupons = new Types.Coupon[](2);
        coupons[0] = Coupon.from(address(usdc), startEpoch.add(1), amount);
        coupons[1] = Coupon.from(address(usdc), startEpoch.add(2), initialAmount);
        vm.expectCall(address(coupon), abi.encodeCall(ICouponManager.burnBatch, (address(this), coupons)));
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, expectedAmount, expectedExpiredWith);
        bondPosition.adjustPosition(tokenId, -int256(amount), -int16(epochs), new bytes(0));

        Types.Bond memory afterBond = bondPosition.bonds(tokenId);

        assertEq(usdc.balanceOf(address(this)), beforeThisBalance + amount, "THIS_BALANCE");
        assertEq(afterBond.amount, beforeBond.amount - amount, "LOCKED_AMOUNT");
        assertEq(afterBond.expiredWith, expectedExpiredWith, "EXPIRED_WITH");
    }

    function testAdjustPositionDecreaseAmountToZero() public {
        uint256 tokenId = _beforeAdjustPosition();

        uint256 beforeThisBalance = usdc.balanceOf(address(this));
        uint256 beforeBondPositionBalance = bondPosition.balanceOf(address(this));

        Types.Coupon[] memory coupons = new Types.Coupon[](2);
        coupons[0] = Coupon.from(address(usdc), startEpoch.add(1), initialAmount);
        coupons[1] = Coupon.from(address(usdc), startEpoch.add(2), initialAmount);
        vm.expectCall(address(coupon), abi.encodeCall(ICouponManager.burnBatch, (address(this), coupons)));
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, 0, startEpoch);
        bondPosition.adjustPosition(tokenId, -int256(initialAmount), int16(1), new bytes(0));

        Types.Bond memory afterBond = bondPosition.bonds(tokenId);

        assertEq(usdc.balanceOf(address(this)), beforeThisBalance + initialAmount, "THIS_BALANCE");
        assertEq(bondPosition.balanceOf(address(this)), beforeBondPositionBalance - 1, "BOND_POSITION_BALANCE");
        assertEq(afterBond.amount, 0, "LOCKED_AMOUNT");
        assertEq(afterBond.expiredWith, startEpoch, "EXPIRED_WITH");
        vm.expectRevert("ERC721: invalid token ID");
        bondPosition.ownerOf(tokenId);
    }

    function testAdjustPositionDecreaseEpochsToPastEpoch() public {
        uint256 tokenId = _beforeAdjustPosition();

        Types.Epoch expectedExpiredWith = startEpoch;
        uint256 beforeThisBalance = usdc.balanceOf(address(this));
        uint256 beforeBondPositionBalance = bondPosition.balanceOf(address(this));

        Types.Coupon[] memory coupons = new Types.Coupon[](2);
        coupons[0] = Coupon.from(address(usdc), startEpoch.add(1), initialAmount);
        coupons[1] = Coupon.from(address(usdc), startEpoch.add(2), initialAmount);
        vm.expectCall(address(coupon), abi.encodeCall(ICouponManager.burnBatch, (address(this), coupons)));
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, initialAmount, expectedExpiredWith);
        bondPosition.adjustPosition(tokenId, 0, -int16(4), new bytes(0));

        Types.Bond memory afterBond = bondPosition.bonds(tokenId);

        assertEq(usdc.balanceOf(address(this)), beforeThisBalance, "THIS_BALANCE");
        assertEq(bondPosition.balanceOf(address(this)), beforeBondPositionBalance, "BOND_POSITION_BALANCE");
        assertEq(afterBond.amount, initialAmount, "LOCKED_AMOUNT");
        assertEq(afterBond.expiredWith, expectedExpiredWith, "EXPIRED_WITH");
        assertEq(bondPosition.ownerOf(tokenId), address(this), "OWNER");
    }

    function testAdjustPositionWhenProtocolHasInsufficientAmount() public {
        uint256 tokenId = _beforeAdjustPosition();
        uint256 limitBalance = usdc.amount(20);
        assetPool.setWithdrawLimit(address(usdc), limitBalance);

        Types.Epoch expectedExpiredWith = startEpoch.add(1);

        uint256 beforeThisBalance = usdc.balanceOf(address(this));
        Types.Bond memory beforeBond = bondPosition.bonds(tokenId);

        Types.Coupon[] memory coupons = new Types.Coupon[](2);
        coupons[0] = Coupon.from(address(usdc), startEpoch.add(1), limitBalance);
        coupons[1] = Coupon.from(address(usdc), startEpoch.add(2), initialAmount);
        vm.expectCall(address(coupon), abi.encodeCall(ICouponManager.burnBatch, (address(this), coupons)));
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, initialAmount - limitBalance, expectedExpiredWith);
        bondPosition.adjustPosition(tokenId, -int256(initialAmount), -int16(1), new bytes(0));

        Types.Bond memory afterBond = bondPosition.bonds(tokenId);

        assertEq(usdc.balanceOf(address(this)), beforeThisBalance + limitBalance, "THIS_BALANCE");
        assertEq(afterBond.amount, beforeBond.amount - limitBalance, "LOCKED_AMOUNT");
        assertEq(afterBond.expiredWith, expectedExpiredWith, "EXPIRED_WITH");
    }

    function testAdjustPositionWithExpiredPosition() public {
        uint256 tokenId = _beforeAdjustPosition();
        vm.warp(startEpoch.add(10).startTime());

        vm.expectRevert(bytes(Errors.INVALID_EPOCH));
        bondPosition.adjustPosition(tokenId, int256(100), int16(1), new bytes(0));
    }

    function testAdjustPositionOwnership() public {
        uint256 tokenId = _beforeAdjustPosition();
        vm.startPrank(address(0x123));
        vm.expectRevert(bytes(Errors.ACCESS));
        bondPosition.adjustPosition(tokenId, int256(12412), int16(2), new bytes(0));
        vm.stopPrank();
    }

    function testAdjustPositionWithInvalidTokenId() public {
        vm.expectRevert("ERC721: invalid token ID");
        bondPosition.adjustPosition(123, int256(12412), int16(2), new bytes(0));
    }

    function testBurnExpiredPosition() public {
        uint256 tokenId = _beforeAdjustPosition();
        vm.warp(startEpoch.add(10).startTime());

        uint256 beforeThisBalance = usdc.balanceOf(address(this));
        uint256 beforeUserPositionBalance = bondPosition.balanceOf(address(this));

        bondPosition.burnExpiredPosition(tokenId);

        uint256 afterThisBalance = usdc.balanceOf(address(this));
        uint256 afterUserPositionBalance = bondPosition.balanceOf(address(this));

        assertEq(afterThisBalance, beforeThisBalance + initialAmount, "BALANCE");
        assertEq(afterUserPositionBalance, beforeUserPositionBalance - 1, "POSITION_BALANCE");
        vm.expectRevert("ERC721: invalid token ID");
        bondPosition.ownerOf(tokenId);
    }

    function testBurnExpiredPositionWhenProtocolHasInsufficientAmount() public {
        uint256 tokenId = _beforeAdjustPosition();
        vm.warp(startEpoch.add(10).startTime());
        uint256 limitBalance = usdc.amount(20);
        assetPool.setWithdrawLimit(address(usdc), limitBalance);

        uint256 beforeThisBalance = usdc.balanceOf(address(this));
        uint256 beforeUserPositionBalance = bondPosition.balanceOf(address(this));
        Types.Bond memory beforeBond = bondPosition.bonds(tokenId);

        bondPosition.burnExpiredPosition(tokenId);

        uint256 afterThisBalance = usdc.balanceOf(address(this));
        uint256 afterUserPositionBalance = bondPosition.balanceOf(address(this));
        Types.Bond memory afterBond = bondPosition.bonds(tokenId);

        assertEq(afterThisBalance, beforeThisBalance + limitBalance, "BALANCE");
        assertEq(afterUserPositionBalance, beforeUserPositionBalance, "POSITION_BALANCE");
        assertEq(bondPosition.ownerOf(tokenId), address(this), "OWNER");
        assertEq(afterBond.amount, beforeBond.amount - limitBalance, "LOCKED_AMOUNT");
        assertEq(afterBond.expiredWith, beforeBond.expiredWith, "EXPIRED_WITH");
    }

    function testBurnExpiredPositionWhenPositionNotExpired() public {
        uint256 tokenId = _beforeAdjustPosition();

        vm.expectRevert(bytes(Errors.INVALID_EPOCH));
        bondPosition.burnExpiredPosition(tokenId);
    }

    function testBurnExpiredPositionOwnership() public {
        uint256 tokenId = _beforeAdjustPosition();
        vm.warp(startEpoch.add(10).startTime());

        vm.expectRevert(bytes(Errors.ACCESS));
        vm.prank(address(0x123));
        bondPosition.burnExpiredPosition(tokenId);
    }

    function testRegisterAsset() public {
        MockERC20 newToken = new MockERC20("New", "NEW", 18);
        assertTrue(!bondPosition.isAssetRegistered(address(newToken)), "NEW_TOKEN_IS_REGISTERED");
        vm.expectEmit(true, true, true, true);
        emit AssetRegistered(address(newToken));
        bondPosition.registerAsset(address(newToken));
        assertTrue(bondPosition.isAssetRegistered(address(newToken)), "NEW_TOKEN_IS_NOT_REGISTERED");
        assertEq(newToken.allowance(address(bondPosition), address(assetPool)), type(uint256).max, "ALLOWANCE");
    }

    function testRegisterAssetOwnership() public {
        MockERC20 newToken = new MockERC20("New", "NEW", 18);
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(address(0x123));
        bondPosition.registerAsset(address(newToken));
    }

    function assertEq(Types.Epoch e1, Types.Epoch e2, string memory err) internal {
        assertEq(e1.unwrap(), e2.unwrap(), err);
    }
}
