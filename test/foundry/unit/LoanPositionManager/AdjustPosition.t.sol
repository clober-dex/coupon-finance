// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IAssetPool} from "../../../../contracts/interfaces/IAssetPool.sol";
import {ICouponManager} from "../../../../contracts/interfaces/ICouponManager.sol";
import {
    ILoanPositionManager, ILoanPositionManagerTypes
} from "../../../../contracts/interfaces/ILoanPositionManager.sol";
import {Coupon, CouponLibrary} from "../../../../contracts/libraries/Coupon.sol";
import {Epoch, EpochLibrary} from "../../../../contracts/libraries/Epoch.sol";
import {LoanPosition} from "../../../../contracts/libraries/LoanPosition.sol";

import {MockERC20} from "../../mocks/MockERC20.sol";
import {MockOracle} from "../../mocks/MockOracle.sol";
import {MockAssetPool} from "../../mocks/MockAssetPool.sol";

import {LoanPositionAdjustPositionHelper} from "./helpers/AdjustPositionHelper.sol";
import {LoanPositionMintHelper} from "./helpers/MintHelper.sol";
import {TestInitHelper} from "./helpers/TestInitHelper.sol";

contract LoanPositionManagerAdjustPositionUnitTest is Test, ILoanPositionManagerTypes {
    using CouponLibrary for Coupon;
    using EpochLibrary for Epoch;

    MockERC20 public weth;
    MockERC20 public usdc;

    MockOracle public oracle;
    MockAssetPool public assetPool;
    ICouponManager public couponManager;
    ILoanPositionManager public loanPositionManager;

    Epoch public startEpoch;
    uint256 public initialCollateralAmount;
    uint256 public initialDebtAmount;

    LoanPositionAdjustPositionHelper public helper;

    uint256 public tokenId;

    function setUp() public {
        vm.warp(EpochLibrary.wrap(10).startTime());

        TestInitHelper.TestParams memory p = TestInitHelper.init();
        weth = p.weth;
        usdc = p.usdc;
        oracle = p.oracle;
        assetPool = p.assetPool;
        couponManager = p.couponManager;
        loanPositionManager = p.loanPositionManager;
        startEpoch = p.startEpoch;
        initialCollateralAmount = p.initialCollateralAmount;
        initialDebtAmount = p.initialDebtAmount;

        helper = new LoanPositionAdjustPositionHelper(address(loanPositionManager));
        vm.startPrank(address(helper));
        weth.approve(address(loanPositionManager), type(uint256).max);
        usdc.approve(address(loanPositionManager), type(uint256).max);
        couponManager.setApprovalForAll(address(loanPositionManager), true);
        vm.stopPrank();

        Coupon[] memory coupons = new Coupon[](8);
        for (uint256 i = 0; i < 8; i++) {
            coupons[i] = CouponLibrary.from(address(usdc), startEpoch.add(uint8(i)), initialDebtAmount * 1000);
        }
        _mintCoupons(address(helper), coupons);

        LoanPositionMintHelper minter = new LoanPositionMintHelper(address(loanPositionManager));
        _mintCoupons(address(minter), coupons);
        vm.startPrank(address(minter));
        weth.approve(address(loanPositionManager), type(uint256).max);
        usdc.approve(address(loanPositionManager), type(uint256).max);
        couponManager.setApprovalForAll(address(loanPositionManager), true);
        vm.stopPrank();

        weth.transfer(address(minter), initialCollateralAmount);
        tokenId = minter.mint(
            address(weth), address(usdc), initialCollateralAmount, initialDebtAmount, startEpoch.add(2), address(helper)
        );
        vm.warp(startEpoch.add(1).startTime());

        weth.transfer(address(helper), weth.balanceOf(address(this)));
        usdc.transfer(address(helper), usdc.balanceOf(address(this)));
    }

    function _mintCoupons(address to, Coupon[] memory coupons) internal {
        couponManager.mintBatch(to, coupons, new bytes(0));
    }

    function testAdjustPositionIncreaseDebtAndEpochs() public {
        uint256 increaseAmount = usdc.amount(70);
        uint256 debtAmount = initialDebtAmount + increaseAmount;
        Epoch epoch = startEpoch.add(4);

        Coupon[] memory couponsToPay = new Coupon[](4);
        couponsToPay[0] = CouponLibrary.from(address(usdc), startEpoch.add(1), increaseAmount);
        couponsToPay[1] = CouponLibrary.from(address(usdc), startEpoch.add(2), increaseAmount);
        couponsToPay[2] = CouponLibrary.from(address(usdc), startEpoch.add(3), debtAmount);
        couponsToPay[3] = CouponLibrary.from(address(usdc), startEpoch.add(4), debtAmount);
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, initialCollateralAmount, debtAmount, epoch);
        vm.expectCall(
            address(couponManager),
            abi.encodeCall(
                ICouponManager.safeBatchTransferFrom,
                (address(helper), address(loanPositionManager), couponsToPay, new bytes(0))
            ),
            1
        );
        vm.expectCall(
            address(assetPool), abi.encodeCall(IAssetPool.withdraw, (address(usdc), increaseAmount, address(helper))), 1
        );
        helper.adjustPosition(tokenId, initialCollateralAmount, debtAmount, epoch);

        LoanPosition memory position = loanPositionManager.getPosition(tokenId);

        assertEq(position.debtAmount, debtAmount, "DEBT_AMOUNT");
        assertEq(position.expiredWith, epoch, "EXPIRED_WITH");
    }

    function testAdjustPositionIncreaseDebtAndDecreaseEpochs() public {
        uint256 increaseAmount = usdc.amount(70);
        uint256 debtAmount = initialDebtAmount + increaseAmount;
        Epoch epoch = startEpoch.add(1);

        Coupon[] memory couponsToPay = new Coupon[](1);
        couponsToPay[0] = CouponLibrary.from(address(usdc), startEpoch.add(1), increaseAmount);
        Coupon[] memory couponsToRefund = new Coupon[](1);
        couponsToRefund[0] = CouponLibrary.from(address(usdc), startEpoch.add(2), initialDebtAmount);
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, initialCollateralAmount, debtAmount, epoch);
        vm.expectCall(
            address(couponManager),
            abi.encodeCall(
                ICouponManager.safeBatchTransferFrom,
                (address(loanPositionManager), address(helper), couponsToRefund, new bytes(0))
            ),
            1
        );
        vm.expectCall(
            address(couponManager),
            abi.encodeCall(
                ICouponManager.safeBatchTransferFrom,
                (address(helper), address(loanPositionManager), couponsToPay, new bytes(0))
            ),
            1
        );
        vm.expectCall(
            address(assetPool), abi.encodeCall(IAssetPool.withdraw, (address(usdc), increaseAmount, address(helper))), 1
        );
        helper.adjustPosition(tokenId, initialCollateralAmount, debtAmount, epoch);

        LoanPosition memory position = loanPositionManager.getPosition(tokenId);

        assertEq(position.debtAmount, debtAmount, "DEBT_AMOUNT");
        assertEq(position.expiredWith, epoch, "EXPIRED_WITH");
    }

    function testAdjustPositionDecreaseDebtAndIncreaseEpochs() public {
        uint256 decreaseAmount = usdc.amount(30);
        uint256 debtAmount = initialDebtAmount - decreaseAmount;
        Epoch epoch = startEpoch.add(4);

        uint256 beforeDebtBalance = usdc.balanceOf(address(helper));

        Coupon[] memory couponsToPay = new Coupon[](2);
        couponsToPay[0] = CouponLibrary.from(address(usdc), startEpoch.add(3), debtAmount);
        couponsToPay[1] = CouponLibrary.from(address(usdc), startEpoch.add(4), debtAmount);
        Coupon[] memory couponsToRefund = new Coupon[](2);
        couponsToRefund[0] = CouponLibrary.from(address(usdc), startEpoch.add(1), decreaseAmount);
        couponsToRefund[1] = CouponLibrary.from(address(usdc), startEpoch.add(2), decreaseAmount);
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, initialCollateralAmount, debtAmount, epoch);
        vm.expectCall(
            address(couponManager),
            abi.encodeCall(
                ICouponManager.safeBatchTransferFrom,
                (address(helper), address(loanPositionManager), couponsToPay, new bytes(0))
            ),
            1
        );
        vm.expectCall(
            address(couponManager),
            abi.encodeCall(
                ICouponManager.safeBatchTransferFrom,
                (address(loanPositionManager), address(helper), couponsToRefund, new bytes(0))
            ),
            1
        );
        vm.expectCall(address(assetPool), abi.encodeCall(IAssetPool.deposit, (address(usdc), decreaseAmount)), 1);
        helper.adjustPosition(tokenId, initialCollateralAmount, debtAmount, epoch);

        LoanPosition memory position = loanPositionManager.getPosition(tokenId);

        assertEq(usdc.balanceOf(address(helper)), beforeDebtBalance - decreaseAmount, "DEBT_BALANCE");
        assertEq(position.debtAmount, debtAmount, "DEBT_AMOUNT");
        assertEq(position.expiredWith, epoch, "EXPIRED_WITH");
    }

    function testAdjustPositionDecreaseDebtAndEpochs() public {
        uint256 decreaseAmount = usdc.amount(30);
        uint256 debtAmount = initialDebtAmount - decreaseAmount;
        Epoch epoch = startEpoch.add(1);

        uint256 beforeDebtBalance = usdc.balanceOf(address(helper));

        Coupon[] memory couponsToRefund = new Coupon[](2);
        couponsToRefund[0] = CouponLibrary.from(address(usdc), startEpoch.add(1), decreaseAmount);
        couponsToRefund[1] = CouponLibrary.from(address(usdc), startEpoch.add(2), initialDebtAmount);
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, initialCollateralAmount, debtAmount, epoch);
        vm.expectCall(
            address(couponManager),
            abi.encodeCall(
                ICouponManager.safeBatchTransferFrom,
                (address(loanPositionManager), address(helper), couponsToRefund, new bytes(0))
            ),
            1
        );
        vm.expectCall(address(assetPool), abi.encodeCall(IAssetPool.deposit, (address(usdc), decreaseAmount)), 1);
        helper.adjustPosition(tokenId, initialCollateralAmount, debtAmount, epoch);

        LoanPosition memory position = loanPositionManager.getPosition(tokenId);

        assertEq(usdc.balanceOf(address(helper)), beforeDebtBalance - decreaseAmount, "DEBT_BALANCE");
        assertEq(position.debtAmount, debtAmount, "DEBT_AMOUNT");
        assertEq(position.expiredWith, epoch, "EXPIRED_WITH");
    }

    function testAdjustPositionDecreaseDebtToZero() public {
        uint256 decreaseAmount = initialDebtAmount;
        uint256 debtAmount = 0;
        Epoch epoch = startEpoch;

        uint256 beforeDebtBalance = usdc.balanceOf(address(helper));
        uint256 beforeLoanPositionBalance = loanPositionManager.balanceOf(address(helper));

        Coupon[] memory couponsToRefund = new Coupon[](2);
        couponsToRefund[0] = CouponLibrary.from(address(usdc), startEpoch.add(1), decreaseAmount);
        couponsToRefund[1] = CouponLibrary.from(address(usdc), startEpoch.add(2), decreaseAmount);
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, initialCollateralAmount, debtAmount, epoch);
        vm.expectCall(
            address(couponManager),
            abi.encodeCall(
                ICouponManager.safeBatchTransferFrom,
                (address(loanPositionManager), address(helper), couponsToRefund, new bytes(0))
            ),
            1
        );
        vm.expectCall(address(assetPool), abi.encodeCall(IAssetPool.deposit, (address(usdc), decreaseAmount)), 1);
        helper.adjustPosition(tokenId, initialCollateralAmount, debtAmount, epoch);

        LoanPosition memory position = loanPositionManager.getPosition(tokenId);

        assertEq(usdc.balanceOf(address(helper)), beforeDebtBalance - decreaseAmount, "DEBT_BALANCE");
        assertEq(loanPositionManager.balanceOf(address(helper)), beforeLoanPositionBalance, "LOAN_POSITION_BALANCE");
        assertEq(position.collateralAmount, initialCollateralAmount, "COLLATERAL_AMOUNT");
        assertEq(position.debtAmount, debtAmount, "DEBT_AMOUNT");
        assertEq(position.expiredWith, epoch, "EXPIRED_WITH");
    }

    function testAdjustPositionIncreaseCollateral() public {
        uint256 increaseAmount = weth.amount(1);
        uint256 collateralAmount = initialCollateralAmount + increaseAmount;
        Epoch epoch = startEpoch.add(1);

        uint256 beforeCollateralBalance = weth.balanceOf(address(helper));

        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, collateralAmount, initialDebtAmount, epoch);
        vm.expectCall(address(assetPool), abi.encodeCall(IAssetPool.deposit, (address(weth), increaseAmount)), 1);
        helper.adjustPosition(tokenId, collateralAmount, initialDebtAmount, epoch);

        LoanPosition memory position = loanPositionManager.getPosition(tokenId);

        assertEq(weth.balanceOf(address(helper)), beforeCollateralBalance - increaseAmount, "COLLATERAL_BALANCE");
        assertEq(position.collateralAmount, collateralAmount, "COLLATERAL_AMOUNT");
    }

    function testAdjustPositionDecreaseCollateral() public {
        uint256 decreaseAmount = weth.amount(1);
        uint256 collateralAmount = initialCollateralAmount - decreaseAmount;
        Epoch epoch = startEpoch.add(1);

        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, collateralAmount, initialDebtAmount, epoch);
        vm.expectCall(
            address(assetPool), abi.encodeCall(IAssetPool.withdraw, (address(weth), decreaseAmount, address(helper))), 1
        );
        helper.adjustPosition(tokenId, collateralAmount, initialDebtAmount, epoch);

        LoanPosition memory position = loanPositionManager.getPosition(tokenId);

        assertEq(position.collateralAmount, collateralAmount, "COLLATERAL_AMOUNT");
    }

    function testAdjustPositionDecreaseDebtToTooSmallAmount() public {
        Epoch epoch = startEpoch.add(2);
        vm.expectRevert(abi.encodeWithSelector(TooSmallDebt.selector));
        helper.adjustPosition(tokenId, initialCollateralAmount, 1, epoch);
    }

    function testAdjustPositionDecreaseEpochsToPast() public {
        Epoch epoch = EpochLibrary.lastExpiredEpoch();
        vm.expectRevert(abi.encodeWithSelector(UnpaidDebt.selector));
        helper.adjustPosition(tokenId, initialCollateralAmount, initialDebtAmount, epoch);
    }

    function testAdjustPositionDecreaseTooMuchCollateral() public {
        Epoch epoch = startEpoch.add(2);
        vm.expectRevert(abi.encodeWithSelector(LiquidationThreshold.selector));
        helper.adjustPosition(tokenId, 1, initialDebtAmount, epoch);
    }

    function testAdjustPositionIncreaseTooMuchDebt() public {
        uint256 debtAmount = initialDebtAmount + usdc.amount(18000);
        Epoch epoch = startEpoch.add(2);
        vm.expectRevert(abi.encodeWithSelector(LiquidationThreshold.selector));
        helper.adjustPosition(tokenId, initialCollateralAmount, debtAmount, epoch);
    }

    function testAdjustPositionOwnership() public {
        Epoch epoch = EpochLibrary.current();
        vm.prank(address(helper));
        loanPositionManager.transferFrom(address(helper), address(0x123), tokenId);
        vm.expectRevert(abi.encodeWithSelector(InvalidAccess.selector));
        helper.adjustPosition(tokenId, 0, 0, epoch);
    }

    function testAdjustPositionInvalidTokenId() public {
        Epoch epoch = EpochLibrary.current();
        vm.expectRevert("ERC721: invalid token ID");
        helper.adjustPosition(123, 0, 0, epoch);
    }

    function assertEq(Epoch e1, Epoch e2, string memory err) internal {
        assertEq(e1.unwrap(), e2.unwrap(), err);
    }
}
