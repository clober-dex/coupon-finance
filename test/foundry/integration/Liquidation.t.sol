// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {ERC1155Holder, IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {Errors} from "../../../contracts/Errors.sol";
import {LoanPosition, LoanPositionManager} from "../../../contracts/LoanPositionManager.sol";
import {CouponManager} from "../../../contracts/CouponManager.sol";
import {ILoanPositionManager, ILoanPositionManagerEvents, ILoanPositionManagerStructs} from "../../../contracts/interfaces/ILoanPositionManager.sol";
import {ICouponManager} from "../../../contracts/interfaces/ICouponManager.sol";
import {IERC721Permit} from "../../../contracts/interfaces/IERC721Permit.sol";
import {IAssetPool} from "../../../contracts/interfaces/IAssetPool.sol";
import {Coupon, CouponLibrary} from "../../../contracts/libraries/Coupon.sol";
import {Epoch, EpochLibrary} from "../../../contracts/libraries/Epoch.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockAssetPool} from "../mocks/MockAssetPool.sol";
import {MockOracle} from "../mocks/MockOracle.sol";
import {Constants} from "../Constants.sol";

contract LiquidationIntegrationTest is Test, ERC1155Holder, ILoanPositionManagerEvents, ILoanPositionManagerStructs {
    using CouponLibrary for Coupon;
    using EpochLibrary for Epoch;

    MockERC20 public weth;
    MockERC20 public usdc;

    MockOracle public oracle;
    MockAssetPool public assetPool;
    ICouponManager public couponManager;
    ILoanPositionManager public loanPositionManager;

    Epoch public startEpoch;
    uint256 public snapshotId;
    uint256 public initialCollateralAmount;
    uint256 public initialDebtAmount;

    function setUp() public {
        vm.warp(EpochLibrary.wrap(10).startTime());

        weth = new MockERC20("Collateral Token", "COL", 18);
        usdc = new MockERC20("USD coin", "USDC", 6);

        weth.mint(address(this), weth.amount(2_000_000_000));
        usdc.mint(address(this), usdc.amount(2_000_000_000));

        assetPool = new MockAssetPool();
        oracle = new MockOracle(address(weth));
        couponManager = new CouponManager(address(this), "URI/");
        loanPositionManager = new LoanPositionManager(
            address(couponManager),
            address(assetPool),
            address(oracle),
            Constants.TREASURY,
            10 ** 16,
            ""
        );
        loanPositionManager.setLoanConfiguration(
            address(usdc),
            LoanConfiguration({
                liquidationThreshold: 900000,
                liquidationFee: 15000,
                liquidationProtocolFee: 5000,
                liquidationTargetLtv: 800000
            })
        );
        loanPositionManager.setLoanConfiguration(
            address(weth),
            LoanConfiguration({
                liquidationThreshold: 800000,
                liquidationFee: 20000,
                liquidationProtocolFee: 5000,
                liquidationTargetLtv: 700000
            })
        );

        weth.approve(address(loanPositionManager), type(uint256).max);
        usdc.approve(address(loanPositionManager), type(uint256).max);
        weth.transfer(address(assetPool), weth.amount(1_000_000_000));
        usdc.transfer(address(assetPool), usdc.amount(1_000_000_000));
        assetPool.deposit(address(weth), weth.amount(1_000_000_000));
        assetPool.deposit(address(usdc), usdc.amount(1_000_000_000));

        oracle.setAssetPrice(address(weth), 1800 * 10 ** 8);
        oracle.setAssetPrice(address(usdc), 10 ** 8);

        startEpoch = EpochLibrary.current();

        initialCollateralAmount = weth.amount(10);
        initialDebtAmount = usdc.amount(100);
    }

    function _mintCoupons(address to, Coupon[] memory coupons) internal {
        address minter = couponManager.minter();
        vm.startPrank(minter);
        couponManager.mintBatch(to, coupons, new bytes(0));
        vm.stopPrank();
    }

    struct Balance {
        uint256 beforeUserCoupon1Balance;
        uint256 beforeUserCoupon2Balance;
        uint256 beforeLiquidatorCollateralBalance;
        uint256 beforeLiquidatorBalance;
        uint256 beforeTreasuryBalance;
    }

    function _testLiquidation(
        uint256 debtAmount,
        uint256 collateralAmount,
        uint256 changeData,
        uint256 maxRepayAmount,
        uint256 liquidationAmount,
        uint256 repayAmount,
        uint256 protocolFee,
        bool isEthCollateral,
        bool canLiquidate
    ) private {
        Coupon[] memory coupons = new Coupon[](2);
        coupons[0] = CouponLibrary.from(address(isEthCollateral ? usdc : weth), startEpoch, debtAmount);
        coupons[1] = CouponLibrary.from(address(isEthCollateral ? usdc : weth), startEpoch.add(1), debtAmount);
        _mintCoupons(address(this), coupons);

        couponManager.setApprovalForAll(address(loanPositionManager), true);
        uint256 tokenId = loanPositionManager.mint(
            address(isEthCollateral ? weth : usdc),
            address(isEthCollateral ? usdc : weth),
            collateralAmount,
            debtAmount,
            2,
            Constants.USER1,
            new bytes(0)
        );

        MockERC20 collateralToken = isEthCollateral ? weth : usdc;
        MockERC20 debtToken = isEthCollateral ? usdc : weth;

        if (changeData == 0) vm.warp(loanPositionManager.getPosition(tokenId).expiredWith.endTime() + 1);
        else oracle.setAssetPrice(address(weth), changeData);

        LiquidationStatus memory liquidationStatus = loanPositionManager.getLiquidationStatus(tokenId, maxRepayAmount);

        assertEq(liquidationStatus.liquidationAmount, liquidationAmount, "LIQUIDATION_AMOUNT");
        assertEq(liquidationStatus.repayAmount, repayAmount, "REPAY_AMOUNT");

        LoanPosition memory beforePosition = loanPositionManager.getPosition(tokenId);
        Balance memory balances = Balance({
            beforeUserCoupon1Balance: couponManager.balanceOf(Constants.USER1, coupons[0].id()),
            beforeUserCoupon2Balance: couponManager.balanceOf(Constants.USER1, coupons[1].id()),
            beforeLiquidatorCollateralBalance: collateralToken.balanceOf(address(this)),
            beforeLiquidatorBalance: debtToken.balanceOf(address(this)),
            beforeTreasuryBalance: collateralToken.balanceOf(loanPositionManager.treasury())
        });

        loanPositionManager.liquidate(tokenId, maxRepayAmount, new bytes(0));

        LoanPosition memory afterPosition = loanPositionManager.getPosition(tokenId);

        assertEq(beforePosition.debtAmount - afterPosition.debtAmount, repayAmount, "DEBT_AMOUNT");
        assertEq(
            beforePosition.collateralAmount - afterPosition.collateralAmount,
            liquidationAmount + protocolFee,
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
            beforePosition.collateralAmount - afterPosition.collateralAmount,
            liquidationAmount + protocolFee,
            "COLLATERAL_AMOUNT"
        );
        assertEq(
            balances.beforeLiquidatorBalance - debtToken.balanceOf(address(this)),
            repayAmount,
            "LIQUIDATOR_BALANCE"
        );
        assertEq(
            collateralToken.balanceOf(address(this)) - balances.beforeLiquidatorCollateralBalance,
            liquidationAmount,
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
                    (beforePosition.collateralAmount - afterPosition.collateralAmount) *
                        oracle.getAssetPrice(address(0)) *
                        980001,
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
                    (beforePosition.collateralAmount - afterPosition.collateralAmount) *
                        oracle.getAssetPrice(address(0)) *
                        979999,
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

    function testLiquidationWhenDebtIsBig() public {
        _testLiquidation(
            usdc.amount(600),
            1 ether,
            500 * 10 ** 8,
            0,
            0.995 ether,
            usdc.amount(600),
            0.005 ether,
            true,
            false
        );
    }
}
