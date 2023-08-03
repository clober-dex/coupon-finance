// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
import {Constants} from "../../Constants.sol";
import {LoanPositionLiquidateHelper} from "./helpers/LiquidateHelper.sol";
import {LoanPositionMintHelper} from "./helpers/MintHelper.sol";
import {TestInitHelper} from "./helpers/TestInitHelper.sol";

contract LoanPositionManagerLiquidateUnitTest is Test, ILoanPositionManagerTypes {
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

    LoanPositionLiquidateHelper public helper;

    function setUp() public {
        vm.warp(EpochLibrary.wrap(10).startTime());

        TestInitHelper.TestParams memory p = TestInitHelper.init(vm);
        weth = p.weth;
        usdc = p.usdc;
        oracle = p.oracle;
        assetPool = p.assetPool;
        couponManager = p.couponManager;
        loanPositionManager = p.loanPositionManager;
        startEpoch = p.startEpoch;
        initialCollateralAmount = p.initialCollateralAmount;
        initialDebtAmount = p.initialDebtAmount;

        helper = new LoanPositionLiquidateHelper(address(loanPositionManager));
        vm.startPrank(address(helper));
        weth.approve(address(loanPositionManager), type(uint256).max);
        usdc.approve(address(loanPositionManager), type(uint256).max);
        vm.stopPrank();

        weth.transfer(address(helper), weth.balanceOf(address(this)) / 2);
        usdc.transfer(address(helper), usdc.balanceOf(address(this)) / 2);
    }

    function _mintCoupons(address to, Coupon[] memory coupons) internal {
        couponManager.mintBatch(to, coupons, new bytes(0));
    }

    function _mintPosition(
        uint8 lockEpochs,
        address collateralToken,
        address debtToken,
        uint256 collateralAmount,
        uint256 debtAmount
    ) internal returns (Coupon[] memory coupons, uint256 positionId) {
        coupons = new Coupon[](lockEpochs);
        for (uint8 i = 0; i < lockEpochs; ++i) {
            coupons[i] = CouponLibrary.from(debtToken, startEpoch.add(i), debtAmount);
        }

        LoanPositionMintHelper minter = new LoanPositionMintHelper(address(loanPositionManager));
        _mintCoupons(address(minter), coupons);
        vm.startPrank(address(minter));
        weth.approve(address(loanPositionManager), type(uint256).max);
        usdc.approve(address(loanPositionManager), type(uint256).max);
        vm.stopPrank();

        IERC20(collateralToken).transfer(address(minter), collateralAmount);
        positionId = minter.mint(
            collateralToken, debtToken, collateralAmount, debtAmount, startEpoch.add(lockEpochs - 1), Constants.USER1
        );
    }

    struct Balance {
        uint256 beforeUserCoupon1Balance;
        uint256 beforeUserCoupon2Balance;
        uint256 beforeLiquidatorCollateralBalance;
        uint256 beforeLiquidatorBalance;
        uint256 beforeTreasuryBalance;
    }

    struct LiquidationStatus {
        uint256 liquidationAmount;
        uint256 repayAmount;
        uint256 protocolFeeAmount;
    }

    function _testLiquidation(
        uint256 debtAmount,
        uint256 collateralAmount,
        uint256 changeData,
        uint256 maxRepayAmount,
        uint256 workableAmount,
        uint256 repayAmount,
        uint256 protocolFee,
        bool isEthCollateral,
        bool canLiquidate
    ) private {
        (Coupon[] memory coupons, uint256 tokenId) = _mintPosition(
            2,
            address(isEthCollateral ? weth : usdc),
            address(isEthCollateral ? usdc : weth),
            collateralAmount,
            debtAmount
        );

        MockERC20 collateralToken = isEthCollateral ? weth : usdc;
        MockERC20 debtToken = isEthCollateral ? usdc : weth;

        if (changeData == 0) vm.warp(loanPositionManager.getPosition(tokenId).expiredWith.endTime() + 1);
        else oracle.setAssetPrice(address(weth), changeData);

        LiquidationStatus memory liquidationStatus;
        (liquidationStatus.liquidationAmount, liquidationStatus.repayAmount, liquidationStatus.protocolFeeAmount) =
            loanPositionManager.getLiquidationStatus(tokenId, maxRepayAmount);

        assertEq(liquidationStatus.liquidationAmount, workableAmount + protocolFee, "LIQUIDATION_AMOUNT");
        assertEq(liquidationStatus.repayAmount, repayAmount, "REPAY_AMOUNT");
        assertEq(liquidationStatus.protocolFeeAmount, protocolFee, "PROTOCOL_FEE_AMOUNT");

        LoanPosition memory beforePosition = loanPositionManager.getPosition(tokenId);
        Balance memory balances = Balance({
            beforeUserCoupon1Balance: couponManager.balanceOf(Constants.USER1, coupons[0].id()),
            beforeUserCoupon2Balance: couponManager.balanceOf(Constants.USER1, coupons[1].id()),
            beforeLiquidatorCollateralBalance: collateralToken.balanceOf(address(helper)),
            beforeLiquidatorBalance: debtToken.balanceOf(address(helper)),
            beforeTreasuryBalance: collateralToken.balanceOf(loanPositionManager.treasury())
        });

        helper.liquidate(tokenId, maxRepayAmount);

        LoanPosition memory afterPosition = loanPositionManager.getPosition(tokenId);

        assertEq(beforePosition.debtAmount - afterPosition.debtAmount, repayAmount, "DEBT_AMOUNT");
        assertEq(
            beforePosition.collateralAmount - afterPosition.collateralAmount,
            workableAmount + protocolFee,
            "COLLATERAL_AMOUNT"
        );

        if (changeData > 0) {
            assertEq(
                couponManager.balanceOf(Constants.USER1, coupons[0].id()) - balances.beforeUserCoupon1Balance,
                repayAmount,
                "USER_COUPON1_BALANCE"
            );
            assertEq(
                couponManager.balanceOf(Constants.USER1, coupons[1].id()) - balances.beforeUserCoupon2Balance,
                repayAmount,
                "USER_COUPON2_BALANCE"
            );
        }
        assertEq(
            balances.beforeLiquidatorBalance - debtToken.balanceOf(address(helper)), repayAmount, "LIQUIDATOR_BALANCE"
        );
        assertEq(
            collateralToken.balanceOf(address(helper)) - balances.beforeLiquidatorCollateralBalance,
            workableAmount,
            "LIQUIDATOR_COLLATERAL_BALANCE"
        );
        assertEq(
            collateralToken.balanceOf(loanPositionManager.treasury()) - balances.beforeTreasuryBalance,
            protocolFee,
            "TREASURY_BALANCE"
        );
        if (canLiquidate) {
            isEthCollateral
                ? assertLe(
                    (beforePosition.debtAmount - afterPosition.debtAmount) * 10 ** 20 * 1000000,
                    (beforePosition.collateralAmount - afterPosition.collateralAmount) * oracle.getAssetPrice(address(0))
                        * 980001,
                    "ROUNDING_ISSUE"
                )
                : assertLe(
                    (beforePosition.debtAmount - afterPosition.debtAmount) * oracle.getAssetPrice(address(0)) * 1000000,
                    (beforePosition.collateralAmount - afterPosition.collateralAmount) * 10 ** 20 * 980001,
                    "ROUNDING_ISSUE"
                );
            isEthCollateral
                ? assertGe(
                    (beforePosition.debtAmount - afterPosition.debtAmount) * 10 ** 20 * 1000000,
                    (beforePosition.collateralAmount - afterPosition.collateralAmount) * oracle.getAssetPrice(address(0))
                        * 979999,
                    "ROUNDING_ISSUE"
                )
                : assertGe(
                    (beforePosition.debtAmount - afterPosition.debtAmount) * oracle.getAssetPrice(address(0)) * 1000000,
                    (beforePosition.collateralAmount - afterPosition.collateralAmount) * 10 ** 20 * 979999,
                    "ROUNDING_ISSUE"
                );
        }
        assertLe(
            (collateralToken.balanceOf(loanPositionManager.treasury()) - balances.beforeTreasuryBalance) * 1000,
            (beforePosition.collateralAmount - afterPosition.collateralAmount) * 5,
            "ROUNDING_ISSUE"
        );
        assertGe(
            (collateralToken.balanceOf(loanPositionManager.treasury()) - balances.beforeTreasuryBalance) * 1000000000,
            (beforePosition.collateralAmount - afterPosition.collateralAmount) * 4999999,
            "ROUNDING_ISSUE"
        );
    }

    function _testRevertLiquidation(
        uint256 debtAmount,
        uint256 collateralAmount,
        uint256 price,
        bool epochEnds,
        uint256 maxRepayAmount,
        bool isEthCollateral
    ) private {
        (, uint256 tokenId) = _mintPosition(
            2,
            address(isEthCollateral ? weth : usdc),
            address(isEthCollateral ? usdc : weth),
            collateralAmount,
            debtAmount
        );

        if (epochEnds) vm.warp(loanPositionManager.getPosition(tokenId).expiredWith.endTime() + 1);
        oracle.setAssetPrice(address(weth), price);

        vm.expectRevert(abi.encodeWithSelector(TooSmallDebt.selector));
        loanPositionManager.getLiquidationStatus(tokenId, maxRepayAmount);

        vm.expectRevert(abi.encodeWithSelector(TooSmallDebt.selector));
        helper.liquidate(tokenId, maxRepayAmount);
    }

    function testLiquidationWhenPriceChangesAndEthCollateral() public {
        _testLiquidation(
            usdc.amount(1344), 1 ether, 1600 * 10 ** 8, 0, 0.4975 ether, usdc.amount(784), 0.0025 ether, true, true
        );
    }

    function testLiquidationWhenPriceChangesAndUsdcCollateral() public {
        _testLiquidation(
            1 ether, usdc.amount(3000), 2500 * 10 ** 8, 0, 1421428572, 560000000168000000, 7142857, false, true
        );
    }

    function testLiquidationWhenPriceChangesWithMaxRepayAmount() public {
        _testLiquidation(
            usdc.amount(1344),
            1 ether,
            1600 * 10 ** 8,
            usdc.amount(490),
            0.3109375 ether,
            usdc.amount(490),
            0.0015625 ether,
            true,
            true
        );
    }

    function testLiquidationWhenPriceChangesBig() public {
        _testLiquidation(
            usdc.amount(600), 1 ether, 610 * 10 ** 8, 0, 0.995 ether, usdc.amount(600), 0.005 ether, true, false
        );
    }

    function testLiquidationWhenPriceChangesBigWithMaxRepayAmount() public {
        _testLiquidation(
            usdc.amount(600),
            1 ether,
            610 * 10 ** 8,
            usdc.amount(599),
            988508698561391770,
            593900000,
            4967380394780863,
            true,
            true
        );
    }

    function testLiquidationWhenPriceChangesWithSmallDebt() public {
        oracle.setAssetPrice(address(weth), 1002 * 10 ** 8);
        _testLiquidation(
            usdc.amount(12),
            0.015 ether,
            999 * 10 ** 8,
            0,
            12195869338726483,
            usdc.amount(12),
            61285775571489,
            true,
            true
        );
    }

    function testLiquidationWhenPriceChangesWithSmallDebtWithMaxRepayAmount() public {
        oracle.setAssetPrice(address(weth), 1002 * 10 ** 8);
        _testLiquidation(
            usdc.amount(12),
            0.015 ether,
            999 * 10 ** 8,
            usdc.amount(8),
            2042808114236687,
            2010000,
            10265367408224,
            true,
            true
        );
    }

    function testRevertLiquidationWhenPriceChangesWithSmallDebtWithMaxRepayAmount() public {
        oracle.setAssetPrice(address(weth), 999 * 10 ** 8);
        _testRevertLiquidation(usdc.amount(10), 0.0126 ether, 1001 * 10 ** 8, true, usdc.amount(8), true);
    }

    function testLiquidationWhenPriceChangesWithSmallRemainingDebt() public {
        _testLiquidation(
            usdc.amount(980), 1 ether, 1000 * 10 ** 8, 0, 0.995 ether, usdc.amount(980), 0.005 ether, true, true
        );
    }

    function testLiquidationWhenPriceChangesWithSmallRemainingDebtWithMaxRepayAmount() public {
        _testLiquidation(
            usdc.amount(980),
            1 ether,
            1000 * 10 ** 8,
            usdc.amount(979),
            984846938775510205,
            usdc.amount(970),
            4948979591836734,
            true,
            true
        );
    }

    function testLiquidationWhenPriceChangesWithSmallLiquidation() public {
        oracle.setAssetPrice(address(weth), 3000 * 10 ** 8);
        _testLiquidation(
            usdc.amount(32) + 1,
            0.02 ether,
            2000 * 10 ** 8,
            0,
            16244898466836736,
            usdc.amount(32) + 1,
            81632655612244,
            true,
            true
        );
    }

    function testLiquidationWhenEpochEnds() public {
        _testLiquidation(
            usdc.amount(100), 1 ether, 0, 0, 56405895691609978, usdc.amount(100), 283446712018140, true, true
        );
    }

    function testLiquidationWhenEpochEndsWithMaxRepayAmount() public {
        _testLiquidation(
            usdc.amount(100),
            1 ether,
            0,
            usdc.amount(50),
            28202947845804989,
            usdc.amount(50),
            141723356009070,
            true,
            true
        );
    }

    function testLiquidationWhenEpochEndsWithSmallDebt() public {
        oracle.setAssetPrice(address(weth), 100 * 10 ** 8);
        _testLiquidation(
            usdc.amount(10), 1 ether, 0, 0, 101530612244897960, usdc.amount(10), 510204081632653, true, true
        );
    }

    function testLiquidationWhenEpochEndsWithSmallDebtWithMaxRepayAmount() public {
        _testLiquidation(
            usdc.amount(20), 1 ether, 0, usdc.amount(8), 1128117913832201, usdc.amount(2), 5668934240362, true, true
        );
    }

    function testRevertLiquidationWhenEpochEndsWithSmallDebtWithMaxRepayAmount() public {
        oracle.setAssetPrice(address(weth), 100 * 10 ** 8);
        _testRevertLiquidation(usdc.amount(10), 1 ether, 1800 * 10 ** 8, true, usdc.amount(8), true);
    }

    function testLiquidationWhenEpochEndsWithSmallRemainingDebt() public {
        _testLiquidation(
            usdc.amount(100),
            1 ether,
            0,
            usdc.amount(98),
            46252834467120182,
            usdc.amount(82),
            232426303854875,
            true,
            true
        );
    }

    function testLiquidationWhenEpochEndsWithSmallLiquidation() public {
        _testLiquidation(
            usdc.amount(100), 1 ether, 0, usdc.amount(8), 4512471655328799, usdc.amount(8), 22675736961451, true, true
        );
    }

    function testLiquidationWhenDebtIsBig() public {
        _testLiquidation(
            usdc.amount(600), 1 ether, 500 * 10 ** 8, 0, 0.995 ether, usdc.amount(600), 0.005 ether, true, false
        );
    }

    function testLiquidationMaxEpoch() public {
        uint256 debtAmount = usdc.amount(1000);

        (, uint256 tokenId) = _mintPosition(200, address(weth), address(usdc), 1 ether, debtAmount);

        oracle.setAssetPrice(address(weth), 1000 * 10 ** 8);

        //        LiquidationStatus memory liquidationStatus = loanPositionManager.getLiquidationStatus(tokenId, 0);
        helper.liquidate(tokenId, 0);
        // todo: should check state
    }
}
