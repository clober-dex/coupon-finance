// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {ICouponManager} from "../../../../contracts/interfaces/ICouponManager.sol";
import {IAssetPool} from "../../../../contracts/interfaces/IAssetPool.sol";
import {
    ILoanPositionManager, ILoanPositionManagerTypes
} from "../../../../contracts/interfaces/ILoanPositionManager.sol";
import {Coupon, CouponLibrary} from "../../../../contracts/libraries/Coupon.sol";
import {Epoch, EpochLibrary} from "../../../../contracts/libraries/Epoch.sol";
import {LoanPosition} from "../../../../contracts/libraries/LoanPosition.sol";

import {MockERC20} from "../../mocks/MockERC20.sol";
import {MockOracle} from "../../mocks/MockOracle.sol";
import {Constants} from "../../Constants.sol";
import {LoanPositionMintHelper} from "./helpers/MintHelper.sol";
import {TestInitializer} from "./helpers/TestInitializer.sol";

contract LoanPositionManagerMintUnitTest is Test, ILoanPositionManagerTypes {
    using CouponLibrary for Coupon;
    using EpochLibrary for Epoch;

    MockERC20 public weth;
    MockERC20 public usdc;

    ICouponManager public couponManager;
    ILoanPositionManager public loanPositionManager;

    Epoch public startEpoch;
    uint256 public initialCollateralAmount;
    uint256 public initialDebtAmount;

    LoanPositionMintHelper public helper;

    function setUp() public {
        vm.warp(Epoch.wrap(10).startTime());

        TestInitializer.Params memory p = TestInitializer.init(vm);
        weth = p.weth;
        usdc = p.usdc;
        couponManager = p.couponManager;
        loanPositionManager = p.loanPositionManager;
        startEpoch = p.startEpoch;
        initialCollateralAmount = p.initialCollateralAmount;
        initialDebtAmount = p.initialDebtAmount;

        helper = new LoanPositionMintHelper(address(loanPositionManager));
        vm.startPrank(address(helper));
        weth.approve(address(loanPositionManager), type(uint256).max);
        usdc.approve(address(loanPositionManager), type(uint256).max);
        vm.stopPrank();

        weth.transfer(address(helper), weth.balanceOf(address(this)));
        usdc.transfer(address(helper), usdc.balanceOf(address(this)));
    }

    function _mintCoupons(address to, Coupon[] memory coupons) internal {
        couponManager.mintBatch(to, coupons, new bytes(0));
    }

    function testMint() public {
        uint256 beforeCollateralBalance = weth.balanceOf(address(helper));
        uint256 beforeDebtBalance = usdc.balanceOf(Constants.USER1);
        uint256 beforeLoanPositionBalance = loanPositionManager.balanceOf(Constants.USER1);
        uint256 nextId = loanPositionManager.nextId();
        Epoch epoch = startEpoch.add(1);

        Coupon[] memory coupons = new Coupon[](2);
        coupons[0] = CouponLibrary.from(address(usdc), startEpoch, initialDebtAmount);
        coupons[1] = CouponLibrary.from(address(usdc), startEpoch.add(1), initialDebtAmount);
        _mintCoupons(address(helper), coupons);

        vm.expectEmit(true, true, true, true);
        emit UpdatePosition(nextId, initialCollateralAmount, initialDebtAmount, epoch);
        vm.expectCall(address(couponManager), abi.encodeCall(ICouponManager.burnBatch, (address(helper), coupons)), 1);
        uint256 tokenId = helper.mint(
            address(weth), address(usdc), initialCollateralAmount, initialDebtAmount, epoch, Constants.USER1
        );

        LoanPosition memory position = loanPositionManager.getPosition(tokenId);

        assertEq(tokenId, nextId, "TOKEN_ID");
        assertEq(usdc.balanceOf(Constants.USER1), beforeDebtBalance + initialDebtAmount, "DEBT_BALANCE");
        assertEq(
            weth.balanceOf(address(helper)), beforeCollateralBalance - initialCollateralAmount, "COLLATERAL_BALANCE"
        );
        assertEq(loanPositionManager.balanceOf(Constants.USER1), beforeLoanPositionBalance + 1, "LOAN_POSITION_BALANCE");
        assertEq(loanPositionManager.nextId(), nextId + 1, "NEXT_ID");
        assertEq(loanPositionManager.ownerOf(tokenId), Constants.USER1, "OWNER_OF");
        assertEq(position.collateralToken, address(weth), "COLLATERAL_ASSET");
        assertEq(position.debtToken, address(usdc), "DEBT_ASSET");
        assertEq(position.collateralAmount, initialCollateralAmount, "COLLATERAL_AMOUNT");
        assertEq(position.debtAmount, initialDebtAmount, "DEBT_AMOUNT");
        assertEq(position.expiredWith, epoch, "EXPIRED_WITH");
    }

    function testMintWithTooSmallDebtAmount() public {
        Coupon[] memory coupons = new Coupon[](2);
        coupons[0] = CouponLibrary.from(address(usdc), startEpoch, initialDebtAmount);
        coupons[1] = CouponLibrary.from(address(usdc), startEpoch.add(1), initialDebtAmount);
        _mintCoupons(address(helper), coupons);

        vm.expectRevert(abi.encodeWithSelector(TooSmallDebt.selector));
        helper.mint(address(weth), address(usdc), initialCollateralAmount, 1, startEpoch.add(1), Constants.USER1);
    }

    function testMintWithInsufficientCollateralAmount() public {
        uint256 collateralAmount = weth.amount(1);
        uint256 debtAmount = usdc.amount(10000);
        Coupon[] memory coupons = new Coupon[](2);
        coupons[0] = CouponLibrary.from(address(usdc), startEpoch, debtAmount);
        coupons[1] = CouponLibrary.from(address(usdc), startEpoch.add(1), debtAmount);
        _mintCoupons(address(helper), coupons);

        vm.expectRevert(abi.encodeWithSelector(LiquidationThreshold.selector));
        helper.mint(address(weth), address(usdc), collateralAmount, debtAmount, startEpoch.add(1), Constants.USER1);
    }

    function testMintWithUnregisteredAsset() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidPair.selector));
        helper.mint(
            address(0x23), address(usdc), initialCollateralAmount, initialDebtAmount, startEpoch.add(1), Constants.USER1
        );
        vm.expectRevert(abi.encodeWithSelector(InvalidPair.selector));
        helper.mint(
            address(usdc),
            address(0x123),
            initialCollateralAmount,
            initialDebtAmount,
            startEpoch.add(1),
            Constants.USER1
        );
    }

    function assertEq(Epoch e1, Epoch e2, string memory err) internal {
        assertEq(Epoch.unwrap(e1), Epoch.unwrap(e2), err);
    }
}
