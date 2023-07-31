// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Create1} from "@clober/library/contracts/Create1.sol";

import {CouponManager} from "../../../contracts/CouponManager.sol";
import {BondPosition, BondPositionManager} from "../../../contracts/BondPositionManager.sol";
import {IAssetPool} from "../../../contracts/interfaces/IAssetPool.sol";
import {IBondPositionManager, IBondPositionManagerTypes} from "../../../contracts/interfaces/IBondPositionManager.sol";
import {IBondPositionCallbackReceiver} from "../../../contracts/interfaces/IBondPositionCallbackReceiver.sol";
import {ICouponManager} from "../../../contracts/interfaces/ICouponManager.sol";
import {Coupon, CouponLibrary} from "../../../contracts/libraries/Coupon.sol";
import {Epoch, EpochLibrary} from "../../../contracts/libraries/Epoch.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockAssetPool} from "../mocks/MockAssetPool.sol";
import {Constants} from "../Constants.sol";
import {Utils} from "../Utils.sol";

contract BondPositionManagerUnitTest is
    Test,
    IBondPositionManagerTypes,
    ERC1155Holder,
    ERC721Holder,
    IBondPositionCallbackReceiver
{
    using CouponLibrary for Coupon;
    using EpochLibrary for Epoch;

    MockERC20 public usdc;

    MockAssetPool public assetPool;
    ICouponManager public couponManager;
    IBondPositionManager public bondPositionManager;

    Epoch public startEpoch;
    uint256 public initialAmount;

    function setUp() public {
        usdc = new MockERC20("USD coin", "USDC", 6);

        usdc.mint(address(this), usdc.amount(1_000_000_000));

        vm.warp(EpochLibrary.wrap(10).startTime());
        startEpoch = EpochLibrary.current();

        initialAmount = usdc.amount(100);
        assetPool = new MockAssetPool();
        uint64 thisNonce = vm.getNonce(address(this));
        couponManager = new CouponManager(Create1.computeAddress(address(this), thisNonce + 1), "URI/");
        bondPositionManager = new BondPositionManager(
            address(couponManager),
            address(assetPool),
            "bond/position/uri/",
            Utils.toArr(address(usdc))
        );

        usdc.approve(address(bondPositionManager), type(uint256).max);
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
            address(couponManager),
            abi.encodeCall(ICouponManager.mintBatch, (Constants.USER1, coupons, new bytes(0))),
            1
        );
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(nextId, amount, expectedExpiredWith);
        uint256 tokenId = bondPositionManager.mint(address(usdc), amount, 2, Constants.USER1, new bytes(0));

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

    function bondPositionAdjustCallback(
        uint256,
        BondPosition memory oldPosition,
        BondPosition memory newPosition,
        Coupon[] memory couponsMinted,
        Coupon[] memory,
        bytes calldata data
    ) external {
        address asset = oldPosition.asset;
        (uint256 approveAmount, uint256 beforeBalance, uint256[] memory beforeCouponBalance) =
            abi.decode(data, (uint256, uint256, uint256[]));
        if (newPosition.amount < oldPosition.amount) {
            assertEq(
                IERC20(asset).balanceOf(address(this)) - beforeBalance,
                oldPosition.amount - newPosition.amount,
                "ASSET_BALANCE"
            );
        }
        uint256 length = couponsMinted.length;
        for (uint256 i = 0; i < length; ++i) {
            assertEq(
                couponManager.balanceOf(address(this), couponsMinted[i].id()) - beforeCouponBalance[i],
                couponsMinted[i].amount,
                "COUPON_BALANCE"
            );
        }
        IERC20(oldPosition.asset).approve(address(bondPositionManager), approveAmount);
    }

    function testFlashMint() public {
        uint256 amount = initialAmount;
        Epoch expectedExpiredWith = startEpoch.add(2);

        Coupon[] memory coupons = new Coupon[](3);
        coupons[0] = CouponLibrary.from(address(usdc), startEpoch, amount);
        coupons[1] = CouponLibrary.from(address(usdc), startEpoch.add(1), amount);
        coupons[2] = CouponLibrary.from(address(usdc), startEpoch.add(2), amount);

        uint256[] memory beforeCouponBalance = new uint256[](3);
        beforeCouponBalance[0] = couponManager.balanceOf(address(this), coupons[0].id());
        beforeCouponBalance[1] = couponManager.balanceOf(address(this), coupons[1].id());
        beforeCouponBalance[2] = couponManager.balanceOf(address(this), coupons[2].id());

        vm.expectRevert("ERC20: insufficient allowance");
        bondPositionManager.mint(address(usdc), amount, 3, address(this), abi.encode(0, 0, beforeCouponBalance));

        uint256 tokenId = bondPositionManager.mint(
            address(usdc),
            amount,
            3,
            address(this),
            abi.encode(amount, usdc.balanceOf(address(this)), beforeCouponBalance)
        );

        beforeCouponBalance[0] = couponManager.balanceOf(address(this), coupons[0].id());
        beforeCouponBalance[1] = couponManager.balanceOf(address(this), coupons[1].id());
        beforeCouponBalance[2] = couponManager.balanceOf(address(this), coupons[2].id());

        bondPositionManager.adjustPosition(
            tokenId, amount / 3, expectedExpiredWith, abi.encode(0, usdc.balanceOf(address(this)), beforeCouponBalance)
        );

        beforeCouponBalance[0] = couponManager.balanceOf(address(this), coupons[0].id());
        beforeCouponBalance[1] = couponManager.balanceOf(address(this), coupons[1].id());
        beforeCouponBalance[2] = couponManager.balanceOf(address(this), coupons[2].id());

        uint256 balance = usdc.balanceOf(address(this));
        vm.expectRevert("ERC20: insufficient allowance");
        bondPositionManager.adjustPosition(
            tokenId, amount, expectedExpiredWith, abi.encode(0, balance, beforeCouponBalance)
        );

        bondPositionManager.adjustPosition(
            tokenId,
            amount,
            expectedExpiredWith,
            abi.encode(amount - amount / 3, usdc.balanceOf(address(this)), beforeCouponBalance)
        );
    }

    function testMintWithUnregisteredAsset() public {
        vm.expectRevert(abi.encodeWithSelector(UnregisteredAsset.selector));
        bondPositionManager.mint(address(0x123), initialAmount, 2, Constants.USER1, new bytes(0));
    }

    function _beforeAdjustPosition() internal returns (uint256 tokenId) {
        tokenId = bondPositionManager.mint(address(usdc), initialAmount, 3, address(this), new bytes(0));
        vm.warp(startEpoch.add(1).startTime());
    }

    function testAdjustPositionIncreaseAmountAndEpochs() public {
        uint256 tokenId = _beforeAdjustPosition();

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
            address(couponManager), abi.encodeCall(ICouponManager.burnBatch, (address(this), new Coupon[](0))), 0
        );
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, initialAmount + increaseAmount, expiredWith);
        bondPositionManager.adjustPosition(tokenId, initialAmount + increaseAmount, expiredWith, new bytes(0));

        BondPosition memory afterPosition = bondPositionManager.getPosition(tokenId);

        assertEq(usdc.balanceOf(address(this)), beforeThisBalance - increaseAmount, "THIS_BALANCE");
        assertEq(afterPosition.amount, beforePosition.amount + increaseAmount, "LOCKED_AMOUNT");
        assertEq(afterPosition.expiredWith, expiredWith, "EXPIRED_WITH");
    }

    function testAdjustPositionIncreaseAmountAndDecreaseEpochs() public {
        uint256 tokenId = _beforeAdjustPosition();

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
            address(couponManager), abi.encodeCall(ICouponManager.burnBatch, (address(this), couponsToBurn)), 1
        );
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, initialAmount + increaseAmount, expiredWith);
        bondPositionManager.adjustPosition(tokenId, initialAmount + increaseAmount, expiredWith, new bytes(0));

        BondPosition memory afterPosition = bondPositionManager.getPosition(tokenId);

        assertEq(usdc.balanceOf(address(this)), beforeThisBalance - increaseAmount, "THIS_BALANCE");
        assertEq(afterPosition.amount, beforePosition.amount + increaseAmount, "LOCKED_AMOUNT");
        assertEq(afterPosition.expiredWith, expiredWith, "EXPIRED_WITH");
    }

    function testAdjustPositionDecreaseAmountAndIncreaseEpochs() public {
        uint256 tokenId = _beforeAdjustPosition();

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
            address(couponManager), abi.encodeCall(ICouponManager.burnBatch, (address(this), couponsToBurn)), 1
        );
        vm.expectCall(
            address(assetPool), abi.encodeCall(IAssetPool.withdraw, (address(usdc), decreaseAmount, address(this))), 1
        );
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, amount, expiredWith);
        bondPositionManager.adjustPosition(tokenId, amount, expiredWith, new bytes(0));

        BondPosition memory afterPosition = bondPositionManager.getPosition(tokenId);

        assertEq(afterPosition.amount, beforePosition.amount - decreaseAmount, "LOCKED_AMOUNT");
        assertEq(afterPosition.expiredWith, expiredWith, "EXPIRED_WITH");
    }

    function testAdjustPositionDecreaseAmountAndEpochs() public {
        uint256 tokenId = _beforeAdjustPosition();

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
        vm.expectCall(address(couponManager), abi.encodeCall(ICouponManager.burnBatch, (address(this), coupons)), 1);
        vm.expectCall(
            address(assetPool), abi.encodeCall(IAssetPool.withdraw, (address(usdc), decreaseAmount, address(this))), 1
        );
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, amount, expiredWith);
        bondPositionManager.adjustPosition(tokenId, amount, expiredWith, new bytes(0));

        BondPosition memory afterPosition = bondPositionManager.getPosition(tokenId);

        assertEq(afterPosition.amount, beforePosition.amount - decreaseAmount, "LOCKED_AMOUNT");
        assertEq(afterPosition.expiredWith, expiredWith, "EXPIRED_WITH");
    }

    function testAdjustPositionDecreaseAmountToZero() public {
        uint256 tokenId = _beforeAdjustPosition();

        uint256 beforeBondPositionBalance = bondPositionManager.balanceOf(address(this));

        Coupon[] memory coupons = new Coupon[](2);
        coupons[0] = CouponLibrary.from(address(usdc), startEpoch.add(1), initialAmount);
        coupons[1] = CouponLibrary.from(address(usdc), startEpoch.add(2), initialAmount);
        vm.expectCall(
            address(couponManager),
            abi.encodeCall(ICouponManager.mintBatch, (address(this), new Coupon[](0), new bytes(0))),
            0
        );
        vm.expectCall(address(couponManager), abi.encodeCall(ICouponManager.burnBatch, (address(this), coupons)), 1);
        vm.expectCall(
            address(assetPool), abi.encodeCall(IAssetPool.withdraw, (address(usdc), initialAmount, address(this))), 1
        );
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, 0, startEpoch);
        bondPositionManager.adjustPosition(tokenId, 0, startEpoch, new bytes(0));

        BondPosition memory afterPosition = bondPositionManager.getPosition(tokenId);

        assertEq(bondPositionManager.balanceOf(address(this)), beforeBondPositionBalance - 1, "BOND_POSITION_BALANCE");
        assertEq(afterPosition.amount, 0, "LOCKED_AMOUNT");
        assertEq(afterPosition.expiredWith, startEpoch, "EXPIRED_WITH");
        vm.expectRevert("ERC721: invalid token ID");
        bondPositionManager.ownerOf(tokenId);
    }

    function testAdjustPositionDecreaseEpochsToPastEpoch() public {
        uint256 tokenId = _beforeAdjustPosition();

        Epoch epoch = startEpoch;
        uint256 beforeBondPositionBalance = bondPositionManager.balanceOf(address(this));

        Coupon[] memory coupons = new Coupon[](2);
        coupons[0] = CouponLibrary.from(address(usdc), startEpoch.add(1), initialAmount);
        coupons[1] = CouponLibrary.from(address(usdc), startEpoch.add(2), initialAmount);
        vm.expectCall(
            address(couponManager),
            abi.encodeCall(ICouponManager.mintBatch, (address(this), new Coupon[](0), new bytes(0))),
            0
        );
        vm.expectCall(address(couponManager), abi.encodeCall(ICouponManager.burnBatch, (address(this), coupons)), 1);
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, initialAmount, epoch);
        bondPositionManager.adjustPosition(tokenId, initialAmount, epoch, new bytes(0));

        BondPosition memory afterPosition = bondPositionManager.getPosition(tokenId);

        assertEq(bondPositionManager.balanceOf(address(this)), beforeBondPositionBalance, "BOND_POSITION_BALANCE");
        assertEq(afterPosition.amount, initialAmount, "LOCKED_AMOUNT");
        assertEq(afterPosition.expiredWith, epoch, "EXPIRED_WITH");
        assertEq(bondPositionManager.ownerOf(tokenId), address(this), "OWNER");
    }

    function testAdjustPositionWithExpiredPosition() public {
        uint256 tokenId = _beforeAdjustPosition();
        vm.warp(startEpoch.add(10).startTime());

        vm.expectRevert(abi.encodeWithSelector(InvalidEpoch.selector));
        bondPositionManager.adjustPosition(tokenId, initialAmount - 100, startEpoch.add(2), new bytes(0));
    }

    function testAdjustPositionOwnership() public {
        uint256 tokenId = _beforeAdjustPosition();
        vm.startPrank(address(0x123));
        vm.expectRevert(abi.encodeWithSelector(InvalidAccess.selector));
        bondPositionManager.adjustPosition(tokenId, initialAmount + 12342, startEpoch.add(3), new bytes(0));
        vm.stopPrank();
    }

    function testAdjustPositionWithInvalidTokenId() public {
        vm.expectRevert("ERC721: invalid token ID");
        bondPositionManager.adjustPosition(123, initialAmount + 12342, startEpoch.add(3), new bytes(0));
    }

    function testBurnExpiredPosition() public {
        uint256 tokenId = _beforeAdjustPosition();
        vm.warp(startEpoch.add(10).startTime());

        uint256 beforeUserPositionBalance = bondPositionManager.balanceOf(address(this));

        vm.expectCall(
            address(assetPool), abi.encodeCall(IAssetPool.withdraw, (address(usdc), initialAmount, address(this))), 1
        );
        bondPositionManager.burnExpiredPosition(tokenId);

        uint256 afterUserPositionBalance = bondPositionManager.balanceOf(address(this));

        assertEq(afterUserPositionBalance, beforeUserPositionBalance - 1, "POSITION_BALANCE");
        vm.expectRevert("ERC721: invalid token ID");
        bondPositionManager.ownerOf(tokenId);
    }

    function testBurnExpiredPositionWhenPositionNotExpired() public {
        uint256 tokenId = _beforeAdjustPosition();

        vm.expectRevert(abi.encodeWithSelector(InvalidEpoch.selector));
        bondPositionManager.burnExpiredPosition(tokenId);
    }

    function testBurnExpiredPositionOwnership() public {
        uint256 tokenId = _beforeAdjustPosition();
        vm.warp(startEpoch.add(10).startTime());

        vm.expectRevert(abi.encodeWithSelector(InvalidAccess.selector));
        vm.prank(address(0x123));
        bondPositionManager.burnExpiredPosition(tokenId);
    }

    function testRegisterAsset() public {
        MockERC20 newToken = new MockERC20("New", "NEW", 18);
        assertTrue(!bondPositionManager.isAssetRegistered(address(newToken)), "NEW_TOKEN_IS_REGISTERED");
        vm.expectEmit(true, true, true, true);
        emit AssetRegistered(address(newToken));
        bondPositionManager.registerAsset(address(newToken));
        assertTrue(bondPositionManager.isAssetRegistered(address(newToken)), "NEW_TOKEN_IS_NOT_REGISTERED");
        assertEq(newToken.allowance(address(bondPositionManager), address(assetPool)), type(uint256).max, "ALLOWANCE");
    }

    function testRegisterAssetOwnership() public {
        MockERC20 newToken = new MockERC20("New", "NEW", 18);
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(address(0x123));
        bondPositionManager.registerAsset(address(newToken));
    }

    function assertEq(Epoch e1, Epoch e2, string memory err) internal {
        assertEq(e1.unwrap(), e2.unwrap(), err);
    }
}
