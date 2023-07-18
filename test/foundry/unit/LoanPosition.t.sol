// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

import {Errors} from "../../../contracts/Errors.sol";
import {Types} from "../../../contracts/Types.sol";
import {ILoanPosition, ILoanPositionEvents} from "../../../contracts/interfaces/ILoanPosition.sol";
import {ICouponManager} from "../../../contracts/interfaces/ICouponManager.sol";
import {Coupon} from "../../../contracts/libraries/Coupon.sol";
import {Epoch} from "../../../contracts/libraries/Epoch.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockAssetPool} from "../mocks/MockAssetPool.sol";
import {MockOracle} from "../mocks/MockOracle.sol";
import {Constants} from "../Constants.sol";
import "../../../contracts/LoanPosition.sol";
import "../../../contracts/CouponManager.sol";

contract LoanPositionUnitTest is Test, ILoanPositionEvents, ERC1155Holder, ERC721Holder {
    using Coupon for Types.Coupon;
    using Epoch for Types.Epoch;

    MockERC20 public weth;
    MockERC20 public usdc;

    MockOracle public oracle;
    MockAssetPool public assetPool;
    ICouponManager public coupon;
    ILoanPosition public loanPosition;

    Types.Epoch public startEpoch;
    uint256 public snapshotId;
    uint256 public initialCollateralAmount;
    uint256 public initialDebtAmount;

    function setUp() public {
        weth = new MockERC20("Collateral Token", "COL", 18);
        usdc = new MockERC20("USD coin", "USDC", 6);

        weth.mint(address(this), weth.amount(2_000_000_000));
        usdc.mint(address(this), usdc.amount(2_000_000_000));

        assetPool = new MockAssetPool();
        oracle = new MockOracle();
        coupon = new CouponManager(address(this), "URI/");
        loanPosition = new LoanPosition(
            address(coupon),
            address(assetPool),
            address(oracle),
            Constants.TREASURY,
            10 ** 16,
            ""
        );
        loanPosition.setLoanConfiguration(
            address(usdc),
            Types.AssetLoanConfiguration({
                decimal: 0,
                liquidationThreshold: 900000,
                liquidationFee: 15000,
                liquidationProtocolFee: 5000,
                liquidationTargetLtv: 800000
            })
        );
        loanPosition.setLoanConfiguration(
            address(weth),
            Types.AssetLoanConfiguration({
                decimal: 0,
                liquidationThreshold: 800000,
                liquidationFee: 20000,
                liquidationProtocolFee: 5000,
                liquidationTargetLtv: 700000
            })
        );

        weth.approve(address(loanPosition), type(uint256).max);
        usdc.approve(address(loanPosition), type(uint256).max);
        weth.transfer(address(assetPool), weth.amount(1_000_000_000));
        usdc.transfer(address(assetPool), usdc.amount(1_000_000_000));
        assetPool.deposit(address(weth), weth.amount(1_000_000_000));
        assetPool.deposit(address(usdc), usdc.amount(1_000_000_000));

        oracle.setAssetPrice(address(weth), 1800 * 10 ** 8);
        oracle.setAssetPrice(address(usdc), 10 ** 8);

        startEpoch = Epoch.current();

        initialCollateralAmount = weth.amount(10);
        initialDebtAmount = usdc.amount(100);
    }

    function _mintCoupons(address to, Types.Coupon[] memory coupons) internal {
        address minter = coupon.minter();
        vm.startPrank(minter);
        coupon.mintBatch(to, coupons, new bytes(0));
        vm.stopPrank();
    }

    function testMint() public {
        uint256 beforeCollateralBalance = weth.balanceOf(address(this));
        uint256 beforeDebtBalance = usdc.balanceOf(Constants.USER1);
        uint256 beforeLoanPositionBalance = loanPosition.balanceOf(Constants.USER1);
        uint256 nextId = loanPosition.nextId();
        uint256 expectedExpiredAt = coupon.epochEndTime(Types.Epoch.wrap(2));

        Types.Coupon[] memory coupons = new Types.Coupon[](2);
        coupons[0] = Coupon.from(address(usdc), startEpoch, initialDebtAmount);
        coupons[1] = Coupon.from(address(usdc), startEpoch.add(1), initialDebtAmount);
        _mintCoupons(address(this), coupons);

        snapshotId = vm.snapshot();
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(nextId, initialCollateralAmount, initialDebtAmount, expectedExpiredAt);
        loanPosition.mint(
            address(weth),
            address(usdc),
            initialCollateralAmount,
            initialDebtAmount,
            2,
            Constants.USER1,
            new bytes(0)
        );
        vm.revertTo(snapshotId);
        vm.expectCall(
            address(coupon),
            abi.encodeCall(
                ICouponManager.safeBatchTransferFrom,
                (address(this), address(loanPosition), coupons, new bytes(0))
            )
        );
        uint256 tokenId = loanPosition.mint(
            address(weth),
            address(usdc),
            initialCollateralAmount,
            initialDebtAmount,
            2,
            Constants.USER1,
            new bytes(0)
        );

        Types.Loan memory loan = loanPosition.loans(tokenId);

        assertEq(tokenId, nextId, "TOKEN_ID");
        assertEq(usdc.balanceOf(Constants.USER1), beforeDebtBalance + initialDebtAmount, "DEBT_BALANCE");
        assertEq(
            weth.balanceOf(address(this)),
            beforeCollateralBalance - initialCollateralAmount,
            "COLLATERAL_BALANCE"
        );
        assertEq(loanPosition.balanceOf(Constants.USER1), beforeLoanPositionBalance + 1, "LOAN_POSITION_BALANCE");
        assertEq(loanPosition.nextId(), nextId + 1, "NEXT_ID");
        assertEq(loanPosition.ownerOf(tokenId), Constants.USER1, "OWNER_OF");
        assertEq(loan.collateralToken, address(weth), "COLLATERAL_ASSET");
        assertEq(loan.debtToken, address(usdc), "DEBT_ASSET");
        assertEq(loan.collateralAmount, initialCollateralAmount, "COLLATERAL_AMOUNT");
        assertEq(loan.debtAmount, initialDebtAmount, "DEBT_AMOUNT");
        assertEq(loan.expiredAt, expectedExpiredAt, "EXPIRED_AT");
    }

    function testMintWithTooSmallDebtAmount() public {
        Types.Coupon[] memory coupons = new Types.Coupon[](2);
        coupons[0] = Coupon.from(address(usdc), startEpoch, initialDebtAmount);
        coupons[1] = Coupon.from(address(usdc), startEpoch.add(1), initialDebtAmount);
        _mintCoupons(address(this), coupons);

        vm.expectRevert(bytes(Errors.TOO_SMALL_DEBT));
        loanPosition.mint(address(weth), address(usdc), initialCollateralAmount, 1, 2, Constants.USER1, new bytes(0));
    }

    function testMintWithInsufficientCollateralAmount() public {
        uint256 collateralAmount = weth.amount(1);
        uint256 debtAmount = usdc.amount(10000);
        Types.Coupon[] memory coupons = new Types.Coupon[](2);
        coupons[0] = Coupon.from(address(usdc), startEpoch, debtAmount);
        coupons[1] = Coupon.from(address(usdc), startEpoch.add(1), debtAmount);
        _mintCoupons(address(this), coupons);

        vm.expectRevert(bytes(Errors.LIQUIDATION_THRESHOLD));
        loanPosition.mint(address(weth), address(usdc), collateralAmount, debtAmount, 2, Constants.USER1, new bytes(0));
    }

    function _beforeAdjustPosition() internal returns (uint256 tokenId) {
        Types.Coupon[] memory coupons = new Types.Coupon[](8);
        for (uint16 i = 0; i < 8; i++) {
            coupons[i] = Coupon.from(address(usdc), startEpoch.add(i), initialDebtAmount * 10);
        }
        _mintCoupons(address(this), coupons);

        tokenId = loanPosition.mint(
            address(weth),
            address(usdc),
            initialCollateralAmount,
            initialDebtAmount,
            3,
            address(this),
            new bytes(0)
        );
        vm.warp(startEpoch.add(1).startTime());
    }

    // TODO: flash adjust position tests

    function testAdjustPositionIncreaseDebtAndEpochs() public {
        uint256 tokenId = _beforeAdjustPosition();
        uint256 debtAmount = usdc.amount(70);
        uint256 loanEpochs = 2;
        uint256 expectedDebtAmount = initialDebtAmount + debtAmount;
        uint256 expectedExpiredAt = coupon.epochEndTime(Types.Epoch.wrap(5));

        uint256 beforeDebtBalance = usdc.balanceOf(address(this));

        snapshotId = vm.snapshot();
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, initialCollateralAmount, expectedDebtAmount, expectedExpiredAt);
        loanPosition.adjustPosition(tokenId, 0, int256(debtAmount), int256(loanEpochs), new bytes(0));
        vm.revertTo(snapshotId);
        Types.Coupon[] memory coupons = new Types.Coupon[](4);
        coupons[0] = Coupon.from(address(usdc), startEpoch.add(1), debtAmount);
        coupons[1] = Coupon.from(address(usdc), startEpoch.add(2), debtAmount);
        coupons[2] = Coupon.from(address(usdc), startEpoch.add(3), expectedDebtAmount);
        coupons[3] = Coupon.from(address(usdc), startEpoch.add(4), expectedDebtAmount);
        vm.expectCall(
            address(coupon),
            abi.encodeCall(
                ICouponManager.safeBatchTransferFrom,
                (address(this), address(loanPosition), coupons, new bytes(0))
            )
        );
        loanPosition.adjustPosition(tokenId, 0, int256(debtAmount), int256(loanEpochs), new bytes(0));

        Types.Loan memory loan = loanPosition.loans(tokenId);

        assertEq(usdc.balanceOf(address(this)), beforeDebtBalance + debtAmount, "DEBT_BALANCE");
        assertEq(loan.debtAmount, expectedDebtAmount, "DEBT_AMOUNT");
        assertEq(loan.expiredAt, expectedExpiredAt, "EXPIRED_AT");
    }

    function testAdjustPositionIncreaseDebtAndDecreaseEpochs() public {
        uint256 tokenId = _beforeAdjustPosition();
        uint256 debtAmount = usdc.amount(70);
        uint256 loanEpochs = 1;
        uint256 expectedDebtAmount = initialDebtAmount + debtAmount;
        uint256 expectedExpiredAt = coupon.epochEndTime(Types.Epoch.wrap(2));

        uint256 beforeDebtBalance = usdc.balanceOf(address(this));

        snapshotId = vm.snapshot();
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, initialCollateralAmount, expectedDebtAmount, expectedExpiredAt);
        loanPosition.adjustPosition(tokenId, 0, int256(debtAmount), -int256(loanEpochs), new bytes(0));
        vm.revertTo(snapshotId);
        Types.Coupon[] memory coupons = new Types.Coupon[](1);
        coupons[0] = Coupon.from(address(usdc), startEpoch.add(1), debtAmount);
        vm.expectCall(
            address(coupon),
            abi.encodeCall(
                ICouponManager.safeBatchTransferFrom,
                (address(this), address(loanPosition), coupons, new bytes(0))
            )
        );
        loanPosition.adjustPosition(tokenId, 0, int256(debtAmount), -int256(loanEpochs), new bytes(0));
        vm.revertTo(snapshotId);
        coupons = new Types.Coupon[](1);
        coupons[0] = Coupon.from(address(usdc), startEpoch.add(2), initialDebtAmount);
        vm.expectCall(
            address(coupon),
            abi.encodeCall(
                ICouponManager.safeBatchTransferFrom,
                (address(loanPosition), address(this), coupons, new bytes(0))
            )
        );
        loanPosition.adjustPosition(tokenId, 0, int256(debtAmount), -int256(loanEpochs), new bytes(0));

        Types.Loan memory loan = loanPosition.loans(tokenId);

        assertEq(usdc.balanceOf(address(this)), beforeDebtBalance + debtAmount, "DEBT_BALANCE");
        assertEq(loan.debtAmount, expectedDebtAmount, "DEBT_AMOUNT");
        assertEq(loan.expiredAt, expectedExpiredAt, "EXPIRED_AT");
    }

    function testAdjustPositionDecreaseDebtAndIncreaseEpochs() public {
        uint256 tokenId = _beforeAdjustPosition();
        uint256 debtAmount = usdc.amount(30);
        uint256 loanEpochs = 2;
        uint256 expectedDebtAmount = initialDebtAmount - debtAmount;
        uint256 expectedExpiredAt = coupon.epochEndTime(Types.Epoch.wrap(5));

        uint256 beforeDebtBalance = usdc.balanceOf(address(this));

        snapshotId = vm.snapshot();
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, initialCollateralAmount, expectedDebtAmount, expectedExpiredAt);
        loanPosition.adjustPosition(tokenId, 0, -int256(debtAmount), int256(loanEpochs), new bytes(0));
        vm.revertTo(snapshotId);
        Types.Coupon[] memory coupons = new Types.Coupon[](2);
        coupons[0] = Coupon.from(address(usdc), startEpoch.add(3), expectedDebtAmount);
        coupons[1] = Coupon.from(address(usdc), startEpoch.add(4), expectedDebtAmount);
        vm.expectCall(
            address(coupon),
            abi.encodeCall(
                ICouponManager.safeBatchTransferFrom,
                (address(this), address(loanPosition), coupons, new bytes(0))
            )
        );
        loanPosition.adjustPosition(tokenId, 0, -int256(debtAmount), int256(loanEpochs), new bytes(0));
        vm.revertTo(snapshotId);
        coupons = new Types.Coupon[](2);
        coupons[0] = Coupon.from(address(usdc), startEpoch.add(1), debtAmount);
        coupons[1] = Coupon.from(address(usdc), startEpoch.add(2), debtAmount);
        vm.expectCall(
            address(coupon),
            abi.encodeCall(
                ICouponManager.safeBatchTransferFrom,
                (address(loanPosition), address(this), coupons, new bytes(0))
            )
        );
        loanPosition.adjustPosition(tokenId, 0, -int256(debtAmount), int256(loanEpochs), new bytes(0));

        Types.Loan memory loan = loanPosition.loans(tokenId);

        assertEq(usdc.balanceOf(address(this)), beforeDebtBalance - debtAmount, "DEBT_BALANCE");
        assertEq(loan.debtAmount, expectedDebtAmount, "DEBT_AMOUNT");
        assertEq(loan.expiredAt, expectedExpiredAt, "EXPIRED_AT");
    }

    function testAdjustPositionDecreaseDebtAndEpochs() public {
        uint256 tokenId = _beforeAdjustPosition();
        uint256 debtAmount = usdc.amount(30);
        uint256 loanEpochs = 1;
        uint256 expectedDebtAmount = initialDebtAmount - debtAmount;
        uint256 expectedExpiredAt = coupon.epochEndTime(Types.Epoch.wrap(2));

        uint256 beforeDebtBalance = usdc.balanceOf(address(this));

        snapshotId = vm.snapshot();
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, initialCollateralAmount, expectedDebtAmount, expectedExpiredAt);
        loanPosition.adjustPosition(tokenId, 0, -int256(debtAmount), -int256(loanEpochs), new bytes(0));
        vm.revertTo(snapshotId);
        Types.Coupon[] memory coupons = new Types.Coupon[](2);
        coupons[0] = Coupon.from(address(usdc), startEpoch.add(1), debtAmount);
        coupons[1] = Coupon.from(address(usdc), startEpoch.add(2), initialDebtAmount);
        vm.expectCall(
            address(coupon),
            abi.encodeCall(
                ICouponManager.safeBatchTransferFrom,
                (address(loanPosition), address(this), coupons, new bytes(0))
            )
        );
        loanPosition.adjustPosition(tokenId, 0, -int256(debtAmount), -int256(loanEpochs), new bytes(0));

        Types.Loan memory loan = loanPosition.loans(tokenId);

        assertEq(usdc.balanceOf(address(this)), beforeDebtBalance - debtAmount, "DEBT_BALANCE");
        assertEq(loan.debtAmount, expectedDebtAmount, "DEBT_AMOUNT");
        assertEq(loan.expiredAt, expectedExpiredAt, "EXPIRED_AT");
    }

    function testAdjustPositionDecreaseDebtToZero() public {
        uint256 tokenId = _beforeAdjustPosition();
        uint256 debtAmount = initialDebtAmount;
        uint256 loanEpochs = 2;
        uint256 expectedDebtAmount = 0;
        uint256 expectedExpiredAt = coupon.epochEndTime(Types.Epoch.wrap(1));

        uint256 beforeDebtBalance = usdc.balanceOf(address(this));
        uint256 beforeCollateralBalance = weth.balanceOf(address(this));
        uint256 beforeLoanPositionBalance = loanPosition.balanceOf(address(this));

        snapshotId = vm.snapshot();
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, initialCollateralAmount, expectedDebtAmount, expectedExpiredAt);
        loanPosition.adjustPosition(tokenId, 0, -int256(debtAmount), int256(loanEpochs), new bytes(0));
        vm.revertTo(snapshotId);
        Types.Coupon[] memory coupons = new Types.Coupon[](2);
        coupons[0] = Coupon.from(address(usdc), startEpoch.add(1), debtAmount);
        coupons[1] = Coupon.from(address(usdc), startEpoch.add(2), debtAmount);
        vm.expectCall(
            address(coupon),
            abi.encodeCall(
                ICouponManager.safeBatchTransferFrom,
                (address(loanPosition), address(this), coupons, new bytes(0))
            )
        );
        loanPosition.adjustPosition(tokenId, 0, -int256(debtAmount), int256(loanEpochs), new bytes(0));

        Types.Loan memory loan = loanPosition.loans(tokenId);

        assertEq(usdc.balanceOf(address(this)), beforeDebtBalance - debtAmount, "DEBT_BALANCE");
        assertEq(
            weth.balanceOf(address(this)),
            beforeCollateralBalance + initialCollateralAmount,
            "COLLATERAL_BALANCE"
        );
        assertEq(loanPosition.balanceOf(address(this)), beforeLoanPositionBalance - 1, "LOAN_POSITION_BALANCE");
        assertEq(loan.debtAmount, expectedDebtAmount, "DEBT_AMOUNT");
        assertEq(loan.expiredAt, expectedExpiredAt, "EXPIRED_AT");
        vm.expectRevert("ERC721: invalid token ID");
        loanPosition.ownerOf(tokenId);
    }

    function testAdjustPositionIncreaseCollateral() public {
        uint256 tokenId = _beforeAdjustPosition();
        uint256 collateralAmount = weth.amount(1);
        uint256 expectedCollateralAmount = initialCollateralAmount + collateralAmount;
        uint256 expectedExpiredAt = coupon.epochEndTime(Types.Epoch.wrap(2));

        uint256 beforeCollateralBalance = weth.balanceOf(address(this));

        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, expectedCollateralAmount, initialDebtAmount, expectedExpiredAt);
        loanPosition.adjustPosition(tokenId, int256(collateralAmount), 0, 0, new bytes(0));

        Types.Loan memory loan = loanPosition.loans(tokenId);

        assertEq(weth.balanceOf(address(this)), beforeCollateralBalance - collateralAmount, "COLLATERAL_BALANCE");
        assertEq(loan.collateralAmount, expectedCollateralAmount, "COLLATERAL_AMOUNT");
    }

    function testAdjustPositionDecreaseCollateral() public {
        uint256 tokenId = _beforeAdjustPosition();
        uint256 collateralAmount = weth.amount(1);
        uint256 expectedCollateralAmount = initialCollateralAmount - collateralAmount;
        uint256 expectedExpiredAt = coupon.epochEndTime(Types.Epoch.wrap(2));

        uint256 beforeCollateralBalance = weth.balanceOf(address(this));

        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, expectedCollateralAmount, initialDebtAmount, expectedExpiredAt);
        loanPosition.adjustPosition(tokenId, -int256(collateralAmount), 0, 0, new bytes(0));

        Types.Loan memory loan = loanPosition.loans(tokenId);

        assertEq(weth.balanceOf(address(this)), beforeCollateralBalance + collateralAmount, "COLLATERAL_BALANCE");
        assertEq(loan.collateralAmount, expectedCollateralAmount, "COLLATERAL_AMOUNT");
    }

    function testAdjustPositionDecreaseDebtToTooSmallAmount() public {
        uint256 tokenId = _beforeAdjustPosition();
        vm.expectRevert(bytes(Errors.TOO_SMALL_DEBT));
        loanPosition.adjustPosition(tokenId, 0, -int256(initialDebtAmount) + 1, 0, new bytes(0));
    }

    function testAdjustPositionDecreaseEpochsToCurrent() public {
        uint256 tokenId = _beforeAdjustPosition();
        vm.expectRevert(bytes(Errors.UNPAID_DEBT));
        loanPosition.adjustPosition(tokenId, 0, 0, -2, new bytes(0));
    }

    function testAdjustPositionDecreaseTooMuchCollateral() public {
        uint256 tokenId = _beforeAdjustPosition();
        vm.expectRevert(bytes(Errors.LIQUIDATION_THRESHOLD));
        loanPosition.adjustPosition(tokenId, -int256(initialCollateralAmount) + 1, 0, 0, new bytes(0));
    }

    function testAdjustPositionIncreaseTooMuchDebt() public {
        uint256 tokenId = _beforeAdjustPosition();
        uint256 debtAmount = usdc.amount(18000);
        vm.expectRevert(bytes(Errors.LIQUIDATION_THRESHOLD));
        loanPosition.adjustPosition(tokenId, 0, int256(debtAmount), 0, new bytes(0));
    }

    function testAdjustPositionOwnership() public {
        uint256 tokenId = _beforeAdjustPosition();
        vm.startPrank(address(0x123));
        vm.expectRevert("ERC721: caller is not token owner or approved");
        loanPosition.adjustPosition(tokenId, 0, 0, 0, new bytes(0));
        vm.stopPrank();
    }

    function testAdjustPositionInvalidTokenId() public {
        vm.expectRevert("ERC721: invalid token ID");
        loanPosition.adjustPosition(123, 0, 0, 0, new bytes(0));
    }

    function testLiquidationWhenPriceChangesAndEthCollateral() public {
        uint256 nextId = loanPosition.nextId();
        uint256 expectedExpiredAt = coupon.epochEndTime(Types.Epoch.wrap(2));

        Types.Coupon[] memory coupons = new Types.Coupon[](2);
        coupons[0] = Coupon.from(address(usdc), startEpoch, usdc.amount(1344));
        coupons[1] = Coupon.from(address(usdc), startEpoch.add(1), usdc.amount(1344));
        _mintCoupons(address(this), coupons);

        uint256 tokenId = loanPosition.mint(
            address(weth),
            address(usdc),
            weth.amount(1),
            usdc.amount(1344),
            2,
            Constants.USER1,
            new bytes(0)
        );

        oracle.setAssetPrice(address(weth), 1600 * 10 ** 8);

        Types.LiquidationStatus memory liquidationStatus = loanPosition.getLiquidationStatus(tokenId, 0);

        assertEq(liquidationStatus.available, true, "LIQUIDATION_AVAILABLE");
        assertEq(liquidationStatus.liquidationAmount, 0.4975 ether, "LIQUIDATION_AMOUNT");
        assertEq(liquidationStatus.repayAmount, usdc.amount(784), "REPAY_AMOUNT");

        Types.Loan memory beforeLoanPosition = loanPosition.loans(tokenId);
        uint256 beforeUserCoupon1Balance = coupon.balanceOf(Constants.USER1, coupons[0].id());
        uint256 beforeUserCoupon2Balance = coupon.balanceOf(Constants.USER1, coupons[1].id());
        uint256 beforeLiquidatorCollateralBalance = weth.balanceOf(address(this));
        uint256 beforeLiquidatorBalance = usdc.balanceOf(address(this));
        uint256 beforeTreasuryBalance = weth.balanceOf(loanPosition.treasury());

        loanPosition.liquidate(tokenId, 0, new bytes(0));

        Types.Loan memory afterUserLoanStatus = loanPosition.loans(tokenId);
        uint256 afterUserCoupon1Balance = coupon.balanceOf(Constants.USER1, coupons[0].id());
        uint256 afterUserCoupon2Balance = coupon.balanceOf(Constants.USER1, coupons[1].id());
        uint256 afterLiquidatorCollateralBalance = weth.balanceOf(address(this));
        uint256 afterLiquidatorBalance = usdc.balanceOf(address(this));
        uint256 afterTreasuryBalance = weth.balanceOf(loanPosition.treasury());

        assertEq(beforeLoanPosition.debtAmount - afterUserLoanStatus.debtAmount, usdc.amount(784), "DEBT_AMOUNT");
        assertEq(
            beforeLoanPosition.collateralAmount - afterUserLoanStatus.collateralAmount,
            0.5 ether,
            "COLLATERAL_AMOUNT"
        );
        assertEq(afterUserCoupon1Balance - beforeUserCoupon1Balance, usdc.amount(784), "USER_COUPON1_BALANCE");
        assertEq(afterUserCoupon2Balance - beforeUserCoupon2Balance, usdc.amount(784), "USER_COUPON2_BALANCE");
        assertEq(
            beforeLoanPosition.collateralAmount - afterUserLoanStatus.collateralAmount,
            0.5 ether,
            "COLLATERAL_AMOUNT"
        );
        assertEq(beforeLiquidatorBalance - afterLiquidatorBalance, usdc.amount(784), "LIQUIDATOR_BALANCE");
        assertEq(
            afterLiquidatorCollateralBalance - beforeLiquidatorCollateralBalance,
            0.4975 ether,
            "LIQUIDATOR_COLLATERAL_BALANCE"
        );
        assertEq(afterTreasuryBalance - beforeTreasuryBalance, 0.0025 ether, "TREASURY_BALANCE");
    }

    function testLiquidationWhenPriceChangesAndUsdcCollateral() public {
        uint256 nextId = loanPosition.nextId();
        uint256 expectedExpiredAt = coupon.epochEndTime(Types.Epoch.wrap(2));

        Types.Coupon[] memory coupons = new Types.Coupon[](2);
        coupons[0] = Coupon.from(address(usdc), startEpoch, weth.amount(1));
        coupons[1] = Coupon.from(address(usdc), startEpoch.add(1), weth.amount(1));
        _mintCoupons(address(this), coupons);

        uint256 tokenId = loanPosition.mint(
            address(usdc),
            address(weth),
            usdc.amount(3000),
            weth.amount(1),
            2,
            Constants.USER1,
            new bytes(0)
        );

        oracle.setAssetPrice(address(weth), 2500 * 10 ** 8);

        Types.LiquidationStatus memory liquidationStatus = loanPosition.getLiquidationStatus(tokenId, 0);

        assertEq(liquidationStatus.available, true, "LIQUIDATION_AVAILABLE");
        assertEq(liquidationStatus.liquidationAmount, 1421428572, "LIQUIDATION_AMOUNT");
        assertEq(liquidationStatus.repayAmount, 560000000168000000, "REPAY_AMOUNT");

        Types.Loan memory beforeLoanPosition = loanPosition.loans(tokenId);
        uint256 beforeUserCoupon1Balance = coupon.balanceOf(Constants.USER1, coupons[0].id());
        uint256 beforeUserCoupon2Balance = coupon.balanceOf(Constants.USER1, coupons[1].id());
        uint256 beforeLiquidatorCollateralBalance = usdc.balanceOf(address(this));
        uint256 beforeLiquidatorBalance = weth.balanceOf(address(this));
        uint256 beforeTreasuryBalance = usdc.balanceOf(loanPosition.treasury());

        loanPosition.liquidate(tokenId, 0, new bytes(0));

        Types.Loan memory afterUserLoanStatus = loanPosition.loans(tokenId);
        uint256 afterUserCoupon1Balance = coupon.balanceOf(Constants.USER1, coupons[0].id());
        uint256 afterUserCoupon2Balance = coupon.balanceOf(Constants.USER1, coupons[1].id());
        uint256 afterLiquidatorCollateralBalance = usdc.balanceOf(address(this));
        uint256 afterLiquidatorBalance = weth.balanceOf(address(this));
        uint256 afterTreasuryBalance = usdc.balanceOf(loanPosition.treasury());

        assertEq(beforeLoanPosition.debtAmount - afterUserLoanStatus.debtAmount, 560000000168000000, "DEBT_AMOUNT");
        assertEq(
            beforeLoanPosition.collateralAmount - afterUserLoanStatus.collateralAmount,
            1428571429,
            "COLLATERAL_AMOUNT"
        );
        assertEq(afterUserCoupon1Balance - beforeUserCoupon1Balance, 560000000168000000, "USER_COUPON1_BALANCE");
        assertEq(afterUserCoupon2Balance - beforeUserCoupon2Balance, 560000000168000000, "USER_COUPON2_BALANCE");
        assertEq(
            beforeLoanPosition.collateralAmount - afterUserLoanStatus.collateralAmount,
            1428571429,
            "COLLATERAL_AMOUNT"
        );
        assertEq(beforeLiquidatorBalance - afterLiquidatorBalance, 560000000168000000, "LIQUIDATOR_BALANCE");
        assertEq(
            afterLiquidatorCollateralBalance - beforeLiquidatorCollateralBalance,
            1421428572,
            "LIQUIDATOR_COLLATERAL_BALANCE"
        );
        assertEq(afterTreasuryBalance - beforeTreasuryBalance, 7142857, "TREASURY_BALANCE");
    }
}
