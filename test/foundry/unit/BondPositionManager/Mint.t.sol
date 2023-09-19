// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {
    IBondPositionManager, IBondPositionManagerTypes
} from "../../../../contracts/interfaces/IBondPositionManager.sol";
import {ICouponManager} from "../../../../contracts/interfaces/ICouponManager.sol";
import {BondPosition} from "../../../../contracts/libraries/BondPosition.sol";
import {Coupon, CouponLibrary} from "../../../../contracts/libraries/Coupon.sol";
import {Epoch, EpochLibrary} from "../../../../contracts/libraries/Epoch.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";
import {TestInitializer} from "./helpers/TestInitializer.sol";
import {BondPositionMintHelper} from "./helpers/MintHelper.sol";
import {Constants} from "../../Constants.sol";

contract BondPositionManagerMintUnitTest is Test, IBondPositionManagerTypes {
    using EpochLibrary for Epoch;

    MockERC20 public usdc;

    ICouponManager public couponManager;
    IBondPositionManager public bondPositionManager;

    Epoch public startEpoch;
    uint256 public initialAmount;

    BondPositionMintHelper public helper;

    function setUp() public {
        TestInitializer.Params memory p = TestInitializer.init(vm);
        usdc = p.usdc;
        couponManager = p.couponManager;
        bondPositionManager = p.bondPositionManager;
        startEpoch = p.startEpoch;
        initialAmount = p.initialAmount;

        helper = new BondPositionMintHelper(address(bondPositionManager));
        vm.startPrank(address(helper));
        usdc.approve(address(bondPositionManager), type(uint256).max);
        vm.stopPrank();

        usdc.approve(address(helper), type(uint256).max);
    }

    function testMint() public {
        uint256 amount = initialAmount;
        uint256 beforeThisBalance = usdc.balanceOf(address(this));
        uint256 beforeUserPositionBalance = bondPositionManager.balanceOf(Constants.USER1);
        uint256 nextId = bondPositionManager.nextId();
        Epoch expectedExpiredWith = startEpoch.add(1);

        Coupon[] memory coupons = new Coupon[](2);
        coupons[0] = CouponLibrary.from(address(usdc), startEpoch, amount);
        coupons[1] = CouponLibrary.from(address(usdc), startEpoch.add(1), amount);
        vm.expectCall(
            address(couponManager), abi.encodeCall(ICouponManager.mintBatch, (Constants.USER1, coupons, "")), 1
        );
        vm.expectEmit(true, true, true, true);
        emit UpdatePosition(nextId, amount, expectedExpiredWith);
        uint256 tokenId = helper.mint(address(usdc), amount, startEpoch.add(1), Constants.USER1);

        BondPosition memory position = bondPositionManager.getPosition(tokenId);

        assertEq(tokenId, nextId, "TOKEN_ID");
        assertEq(usdc.balanceOf(address(this)), beforeThisBalance - amount, "THIS_BALANCE");
        assertEq(bondPositionManager.balanceOf(Constants.USER1), beforeUserPositionBalance + 1, "USER_BALANCE");
        assertEq(bondPositionManager.nextId(), nextId + 1, "NEXT_ID");
        assertEq(bondPositionManager.ownerOf(tokenId), Constants.USER1, "OWNER");
        assertEq(position.asset, address(usdc), "ASSET");
        assertEq(position.amount, amount, "LOCKED_AMOUNT");
        assertEq(position.expiredWith, expectedExpiredWith, "EXPIRED_WITH");
    }

    function testMintWithUnregisteredAsset() public {
        vm.expectRevert(abi.encodeWithSelector(UnregisteredAsset.selector));
        helper.mint(address(0x123), initialAmount, startEpoch.add(1), Constants.USER1);
    }

    function testMintZeroAmountPosition() public {
        uint256 beforeThisBalance = usdc.balanceOf(address(this));
        uint256 beforeUserPositionBalance = bondPositionManager.balanceOf(Constants.USER1);
        uint256 nextId = bondPositionManager.nextId();
        Epoch expectedExpiredWith = EpochLibrary.lastExpiredEpoch();

        vm.expectEmit(true, true, true, true);
        emit UpdatePosition(nextId, 0, expectedExpiredWith);
        uint256 tokenId = helper.mint(address(usdc), 0, startEpoch.add(1), Constants.USER1);

        BondPosition memory position = bondPositionManager.getPosition(tokenId);

        assertEq(tokenId, nextId, "TOKEN_ID");
        assertEq(usdc.balanceOf(address(this)), beforeThisBalance, "THIS_BALANCE");
        assertEq(bondPositionManager.balanceOf(Constants.USER1), beforeUserPositionBalance, "USER_BALANCE");
        assertEq(bondPositionManager.nextId(), nextId + 1, "NEXT_ID");
        vm.expectRevert("ERC721: invalid token ID");
        bondPositionManager.ownerOf(tokenId);
        assertEq(position.asset, address(usdc), "ASSET");
        assertEq(position.amount, 0, "LOCKED_AMOUNT");
        assertEq(position.expiredWith, expectedExpiredWith, "EXPIRED_WITH");
    }

    function testMintWithExpiredEpoch() public {
        Epoch epoch = EpochLibrary.current().sub(1);
        vm.expectRevert(abi.encodeWithSelector(InvalidEpoch.selector));
        helper.mint(address(usdc), initialAmount, epoch, Constants.USER1);
    }

    function assertEq(Epoch e1, Epoch e2, string memory err) internal {
        assertEq(Epoch.unwrap(e1), Epoch.unwrap(e2), err);
    }
}
