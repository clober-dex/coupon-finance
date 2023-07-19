// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

import {Errors} from "../../../contracts/Errors.sol";
import {Types} from "../../../contracts/Types.sol";
import {LoanPositionManager} from "../../../contracts/LoanPositionManager.sol";
import {CouponManager} from "../../../contracts/CouponManager.sol";
import {ILoanPositionManager, ILoanPositionManagerEvents} from "../../../contracts/interfaces/ILoanPositionManager.sol";
import {ICouponManager} from "../../../contracts/interfaces/ICouponManager.sol";
import {Coupon} from "../../../contracts/libraries/Coupon.sol";
import {Epoch} from "../../../contracts/libraries/Epoch.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockAssetPool} from "../mocks/MockAssetPool.sol";
import {MockOracle} from "../mocks/MockOracle.sol";
import {Constants} from "../Constants.sol";

contract LoanPositionUnitTest is Test, ILoanPositionManagerEvents, ERC1155Holder, ERC721Holder {
    using Coupon for Types.Coupon;
    using Epoch for Types.Epoch;

    MockERC20 public weth;
    MockERC20 public usdc;

    MockOracle public oracle;
    MockAssetPool public assetPool;
    ICouponManager public couponManager;
    ILoanPositionManager public loanPositionManager;

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
            Types.AssetLoanConfiguration({
                decimal: 0,
                liquidationThreshold: 900000,
                liquidationFee: 15000,
                liquidationProtocolFee: 5000,
                liquidationTargetLtv: 800000
            })
        );
        loanPositionManager.setLoanConfiguration(
            address(weth),
            Types.AssetLoanConfiguration({
                decimal: 0,
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

        startEpoch = Epoch.current();

        initialCollateralAmount = weth.amount(10);
        initialDebtAmount = usdc.amount(100);
    }

    function _mintCoupons(address to, Types.Coupon[] memory coupons) internal {
        address minter = couponManager.minter();
        vm.startPrank(minter);
        couponManager.mintBatch(to, coupons, new bytes(0));
        vm.stopPrank();
    }

    function testMint() public {
        uint256 beforeCollateralBalance = weth.balanceOf(address(this));
        uint256 beforeDebtBalance = usdc.balanceOf(Constants.USER1);
        uint256 beforeLoanPositionBalance = loanPositionManager.balanceOf(Constants.USER1);
        uint256 nextId = loanPositionManager.nextId();
        uint256 expectedExpiredAt = couponManager.epochEndTime(Types.Epoch.wrap(2));

        Types.Coupon[] memory coupons = new Types.Coupon[](2);
        coupons[0] = Coupon.from(address(usdc), startEpoch, initialDebtAmount);
        coupons[1] = Coupon.from(address(usdc), startEpoch.add(1), initialDebtAmount);
        _mintCoupons(address(this), coupons);

        snapshotId = vm.snapshot();
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(nextId, initialCollateralAmount, initialDebtAmount, expectedExpiredAt);
        loanPositionManager.mint(
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
            address(couponManager),
            abi.encodeCall(
                ICouponManager.safeBatchTransferFrom,
                (address(this), address(loanPositionManager), coupons, new bytes(0))
            ),
            1
        );
        uint256 tokenId = loanPositionManager.mint(
            address(weth),
            address(usdc),
            initialCollateralAmount,
            initialDebtAmount,
            2,
            Constants.USER1,
            new bytes(0)
        );

        Types.LoanPosition memory loan = loanPositionManager.getLoans(tokenId);

        assertEq(tokenId, nextId, "TOKEN_ID");
        assertEq(usdc.balanceOf(Constants.USER1), beforeDebtBalance + initialDebtAmount, "DEBT_BALANCE");
        assertEq(
            weth.balanceOf(address(this)),
            beforeCollateralBalance - initialCollateralAmount,
            "COLLATERAL_BALANCE"
        );
        assertEq(
            loanPositionManager.balanceOf(Constants.USER1),
            beforeLoanPositionBalance + 1,
            "LOAN_POSITION_BALANCE"
        );
        assertEq(loanPositionManager.nextId(), nextId + 1, "NEXT_ID");
        assertEq(loanPositionManager.ownerOf(tokenId), Constants.USER1, "OWNER_OF");
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
        loanPositionManager.mint(
            address(weth),
            address(usdc),
            initialCollateralAmount,
            1,
            2,
            Constants.USER1,
            new bytes(0)
        );
    }

    function testMintWithInsufficientCollateralAmount() public {
        uint256 collateralAmount = weth.amount(1);
        uint256 debtAmount = usdc.amount(10000);
        Types.Coupon[] memory coupons = new Types.Coupon[](2);
        coupons[0] = Coupon.from(address(usdc), startEpoch, debtAmount);
        coupons[1] = Coupon.from(address(usdc), startEpoch.add(1), debtAmount);
        _mintCoupons(address(this), coupons);

        vm.expectRevert(bytes(Errors.LIQUIDATION_THRESHOLD));
        loanPositionManager.mint(
            address(weth),
            address(usdc),
            collateralAmount,
            debtAmount,
            2,
            Constants.USER1,
            new bytes(0)
        );
    }

    function _beforeAdjustPosition() internal returns (uint256 tokenId) {
        Types.Coupon[] memory coupons = new Types.Coupon[](8);
        for (uint16 i = 0; i < 8; i++) {
            coupons[i] = Coupon.from(address(usdc), startEpoch.add(i), initialDebtAmount * 10);
        }
        _mintCoupons(address(this), coupons);

        tokenId = loanPositionManager.mint(
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
        uint256 expectedExpiredAt = couponManager.epochEndTime(Types.Epoch.wrap(5));

        uint256 beforeDebtBalance = usdc.balanceOf(address(this));

        snapshotId = vm.snapshot();
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, initialCollateralAmount, expectedDebtAmount, expectedExpiredAt);
        loanPositionManager.adjustPosition(tokenId, 0, int256(debtAmount), int256(loanEpochs), new bytes(0));
        vm.revertTo(snapshotId);
        Types.Coupon[] memory coupons = new Types.Coupon[](4);
        coupons[0] = Coupon.from(address(usdc), startEpoch.add(1), debtAmount);
        coupons[1] = Coupon.from(address(usdc), startEpoch.add(2), debtAmount);
        coupons[2] = Coupon.from(address(usdc), startEpoch.add(3), expectedDebtAmount);
        coupons[3] = Coupon.from(address(usdc), startEpoch.add(4), expectedDebtAmount);
        vm.expectCall(
            address(couponManager),
            abi.encodeCall(
                ICouponManager.safeBatchTransferFrom,
                (address(this), address(loanPositionManager), coupons, new bytes(0))
            ),
            1
        );
        loanPositionManager.adjustPosition(tokenId, 0, int256(debtAmount), int256(loanEpochs), new bytes(0));

        Types.LoanPosition memory loan = loanPositionManager.getLoans(tokenId);

        assertEq(usdc.balanceOf(address(this)), beforeDebtBalance + debtAmount, "DEBT_BALANCE");
        assertEq(loan.debtAmount, expectedDebtAmount, "DEBT_AMOUNT");
        assertEq(loan.expiredAt, expectedExpiredAt, "EXPIRED_AT");
    }

    function testAdjustPositionIncreaseDebtAndDecreaseEpochs() public {
        uint256 tokenId = _beforeAdjustPosition();
        uint256 debtAmount = usdc.amount(70);
        uint256 loanEpochs = 1;
        uint256 expectedDebtAmount = initialDebtAmount + debtAmount;
        uint256 expectedExpiredAt = couponManager.epochEndTime(Types.Epoch.wrap(2));

        uint256 beforeDebtBalance = usdc.balanceOf(address(this));

        snapshotId = vm.snapshot();
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, initialCollateralAmount, expectedDebtAmount, expectedExpiredAt);
        loanPositionManager.adjustPosition(tokenId, 0, int256(debtAmount), -int256(loanEpochs), new bytes(0));
        vm.revertTo(snapshotId);
        Types.Coupon[] memory coupons = new Types.Coupon[](1);
        coupons[0] = Coupon.from(address(usdc), startEpoch.add(1), debtAmount);
        vm.expectCall(
            address(couponManager),
            abi.encodeCall(
                ICouponManager.safeBatchTransferFrom,
                (address(this), address(loanPositionManager), coupons, new bytes(0))
            ),
            1
        );
        loanPositionManager.adjustPosition(tokenId, 0, int256(debtAmount), -int256(loanEpochs), new bytes(0));
        vm.revertTo(snapshotId);
        coupons = new Types.Coupon[](1);
        coupons[0] = Coupon.from(address(usdc), startEpoch.add(2), initialDebtAmount);
        vm.expectCall(
            address(couponManager),
            abi.encodeCall(
                ICouponManager.safeBatchTransferFrom,
                (address(loanPositionManager), address(this), coupons, new bytes(0))
            ),
            1
        );
        loanPositionManager.adjustPosition(tokenId, 0, int256(debtAmount), -int256(loanEpochs), new bytes(0));

        Types.LoanPosition memory loan = loanPositionManager.getLoans(tokenId);

        assertEq(usdc.balanceOf(address(this)), beforeDebtBalance + debtAmount, "DEBT_BALANCE");
        assertEq(loan.debtAmount, expectedDebtAmount, "DEBT_AMOUNT");
        assertEq(loan.expiredAt, expectedExpiredAt, "EXPIRED_AT");
    }

    function testAdjustPositionDecreaseDebtAndIncreaseEpochs() public {
        uint256 tokenId = _beforeAdjustPosition();
        uint256 debtAmount = usdc.amount(30);
        uint256 loanEpochs = 2;
        uint256 expectedDebtAmount = initialDebtAmount - debtAmount;
        uint256 expectedExpiredAt = couponManager.epochEndTime(Types.Epoch.wrap(5));

        uint256 beforeDebtBalance = usdc.balanceOf(address(this));

        snapshotId = vm.snapshot();
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, initialCollateralAmount, expectedDebtAmount, expectedExpiredAt);
        loanPositionManager.adjustPosition(tokenId, 0, -int256(debtAmount), int256(loanEpochs), new bytes(0));
        vm.revertTo(snapshotId);
        Types.Coupon[] memory coupons = new Types.Coupon[](2);
        coupons[0] = Coupon.from(address(usdc), startEpoch.add(3), expectedDebtAmount);
        coupons[1] = Coupon.from(address(usdc), startEpoch.add(4), expectedDebtAmount);
        vm.expectCall(
            address(couponManager),
            abi.encodeCall(
                ICouponManager.safeBatchTransferFrom,
                (address(this), address(loanPositionManager), coupons, new bytes(0))
            ),
            1
        );
        loanPositionManager.adjustPosition(tokenId, 0, -int256(debtAmount), int256(loanEpochs), new bytes(0));
        vm.revertTo(snapshotId);
        coupons = new Types.Coupon[](2);
        coupons[0] = Coupon.from(address(usdc), startEpoch.add(1), debtAmount);
        coupons[1] = Coupon.from(address(usdc), startEpoch.add(2), debtAmount);
        vm.expectCall(
            address(couponManager),
            abi.encodeCall(
                ICouponManager.safeBatchTransferFrom,
                (address(loanPositionManager), address(this), coupons, new bytes(0))
            ),
            1
        );
        loanPositionManager.adjustPosition(tokenId, 0, -int256(debtAmount), int256(loanEpochs), new bytes(0));

        Types.LoanPosition memory loan = loanPositionManager.getLoans(tokenId);

        assertEq(usdc.balanceOf(address(this)), beforeDebtBalance - debtAmount, "DEBT_BALANCE");
        assertEq(loan.debtAmount, expectedDebtAmount, "DEBT_AMOUNT");
        assertEq(loan.expiredAt, expectedExpiredAt, "EXPIRED_AT");
    }

    function testAdjustPositionDecreaseDebtAndEpochs() public {
        uint256 tokenId = _beforeAdjustPosition();
        uint256 debtAmount = usdc.amount(30);
        uint256 loanEpochs = 1;
        uint256 expectedDebtAmount = initialDebtAmount - debtAmount;
        uint256 expectedExpiredAt = couponManager.epochEndTime(Types.Epoch.wrap(2));

        uint256 beforeDebtBalance = usdc.balanceOf(address(this));

        snapshotId = vm.snapshot();
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, initialCollateralAmount, expectedDebtAmount, expectedExpiredAt);
        loanPositionManager.adjustPosition(tokenId, 0, -int256(debtAmount), -int256(loanEpochs), new bytes(0));
        vm.revertTo(snapshotId);
        Types.Coupon[] memory coupons = new Types.Coupon[](2);
        coupons[0] = Coupon.from(address(usdc), startEpoch.add(1), debtAmount);
        coupons[1] = Coupon.from(address(usdc), startEpoch.add(2), initialDebtAmount);
        vm.expectCall(
            address(couponManager),
            abi.encodeCall(
                ICouponManager.safeBatchTransferFrom,
                (address(loanPositionManager), address(this), coupons, new bytes(0))
            ),
            1
        );
        loanPositionManager.adjustPosition(tokenId, 0, -int256(debtAmount), -int256(loanEpochs), new bytes(0));

        Types.LoanPosition memory loan = loanPositionManager.getLoans(tokenId);

        assertEq(usdc.balanceOf(address(this)), beforeDebtBalance - debtAmount, "DEBT_BALANCE");
        assertEq(loan.debtAmount, expectedDebtAmount, "DEBT_AMOUNT");
        assertEq(loan.expiredAt, expectedExpiredAt, "EXPIRED_AT");
    }

    function testAdjustPositionDecreaseDebtToZero() public {
        uint256 tokenId = _beforeAdjustPosition();
        uint256 debtAmount = initialDebtAmount;
        uint256 loanEpochs = 2;
        uint256 expectedDebtAmount = 0;
        uint256 expectedExpiredAt = couponManager.epochEndTime(Types.Epoch.wrap(1));

        uint256 beforeDebtBalance = usdc.balanceOf(address(this));
        uint256 beforeCollateralBalance = weth.balanceOf(address(this));
        uint256 beforeLoanPositionBalance = loanPositionManager.balanceOf(address(this));

        snapshotId = vm.snapshot();
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, initialCollateralAmount, expectedDebtAmount, expectedExpiredAt);
        loanPositionManager.adjustPosition(tokenId, 0, -int256(debtAmount), int256(loanEpochs), new bytes(0));
        vm.revertTo(snapshotId);
        Types.Coupon[] memory coupons = new Types.Coupon[](2);
        coupons[0] = Coupon.from(address(usdc), startEpoch.add(1), debtAmount);
        coupons[1] = Coupon.from(address(usdc), startEpoch.add(2), debtAmount);
        vm.expectCall(
            address(couponManager),
            abi.encodeCall(
                ICouponManager.safeBatchTransferFrom,
                (address(loanPositionManager), address(this), coupons, new bytes(0))
            ),
            1
        );
        loanPositionManager.adjustPosition(tokenId, 0, -int256(debtAmount), int256(loanEpochs), new bytes(0));

        Types.LoanPosition memory loan = loanPositionManager.getLoans(tokenId);

        assertEq(usdc.balanceOf(address(this)), beforeDebtBalance - debtAmount, "DEBT_BALANCE");
        assertEq(
            weth.balanceOf(address(this)),
            beforeCollateralBalance + initialCollateralAmount,
            "COLLATERAL_BALANCE"
        );
        assertEq(loanPositionManager.balanceOf(address(this)), beforeLoanPositionBalance - 1, "LOAN_POSITION_BALANCE");
        assertEq(loan.debtAmount, expectedDebtAmount, "DEBT_AMOUNT");
        assertEq(loan.expiredAt, expectedExpiredAt, "EXPIRED_AT");
        vm.expectRevert("ERC721: invalid token ID");
        loanPositionManager.ownerOf(tokenId);
    }

    function testAdjustPositionIncreaseCollateral() public {
        uint256 tokenId = _beforeAdjustPosition();
        uint256 collateralAmount = weth.amount(1);
        uint256 expectedCollateralAmount = initialCollateralAmount + collateralAmount;
        uint256 expectedExpiredAt = couponManager.epochEndTime(Types.Epoch.wrap(2));

        uint256 beforeCollateralBalance = weth.balanceOf(address(this));

        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, expectedCollateralAmount, initialDebtAmount, expectedExpiredAt);
        loanPositionManager.adjustPosition(tokenId, int256(collateralAmount), 0, 0, new bytes(0));

        Types.LoanPosition memory loan = loanPositionManager.getLoans(tokenId);

        assertEq(weth.balanceOf(address(this)), beforeCollateralBalance - collateralAmount, "COLLATERAL_BALANCE");
        assertEq(loan.collateralAmount, expectedCollateralAmount, "COLLATERAL_AMOUNT");
    }

    function testAdjustPositionDecreaseCollateral() public {
        uint256 tokenId = _beforeAdjustPosition();
        uint256 collateralAmount = weth.amount(1);
        uint256 expectedCollateralAmount = initialCollateralAmount - collateralAmount;
        uint256 expectedExpiredAt = couponManager.epochEndTime(Types.Epoch.wrap(2));

        uint256 beforeCollateralBalance = weth.balanceOf(address(this));

        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(tokenId, expectedCollateralAmount, initialDebtAmount, expectedExpiredAt);
        loanPositionManager.adjustPosition(tokenId, -int256(collateralAmount), 0, 0, new bytes(0));

        Types.LoanPosition memory loan = loanPositionManager.getLoans(tokenId);

        assertEq(weth.balanceOf(address(this)), beforeCollateralBalance + collateralAmount, "COLLATERAL_BALANCE");
        assertEq(loan.collateralAmount, expectedCollateralAmount, "COLLATERAL_AMOUNT");
    }

    function testAdjustPositionDecreaseDebtToTooSmallAmount() public {
        uint256 tokenId = _beforeAdjustPosition();
        vm.expectRevert(bytes(Errors.TOO_SMALL_DEBT));
        loanPositionManager.adjustPosition(tokenId, 0, -int256(initialDebtAmount) + 1, 0, new bytes(0));
    }

    function testAdjustPositionDecreaseEpochsToCurrent() public {
        uint256 tokenId = _beforeAdjustPosition();
        vm.expectRevert(bytes(Errors.UNPAID_DEBT));
        loanPositionManager.adjustPosition(tokenId, 0, 0, -2, new bytes(0));
    }

    function testAdjustPositionDecreaseTooMuchCollateral() public {
        uint256 tokenId = _beforeAdjustPosition();
        vm.expectRevert(bytes(Errors.LIQUIDATION_THRESHOLD));
        loanPositionManager.adjustPosition(tokenId, -int256(initialCollateralAmount) + 1, 0, 0, new bytes(0));
    }

    function testAdjustPositionIncreaseTooMuchDebt() public {
        uint256 tokenId = _beforeAdjustPosition();
        uint256 debtAmount = usdc.amount(18000);
        vm.expectRevert(bytes(Errors.LIQUIDATION_THRESHOLD));
        loanPositionManager.adjustPosition(tokenId, 0, int256(debtAmount), 0, new bytes(0));
    }

    function testAdjustPositionOwnership() public {
        uint256 tokenId = _beforeAdjustPosition();
        vm.startPrank(address(0x123));
        vm.expectRevert("ERC721: caller is not token owner or approved");
        loanPositionManager.adjustPosition(tokenId, 0, 0, 0, new bytes(0));
        vm.stopPrank();
    }

    function testAdjustPositionInvalidTokenId() public {
        vm.expectRevert("ERC721: invalid token ID");
        loanPositionManager.adjustPosition(123, 0, 0, 0, new bytes(0));
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
        Types.Coupon[] memory coupons = new Types.Coupon[](2);
        coupons[0] = Coupon.from(address(usdc), startEpoch, debtAmount);
        coupons[1] = Coupon.from(address(usdc), startEpoch.add(1), debtAmount);
        _mintCoupons(address(this), coupons);

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

        if (changeData == 0) vm.warp(block.timestamp + 1);
        else oracle.setAssetPrice(address(weth), changeData);

        Types.LiquidationStatus memory liquidationStatus = loanPositionManager.getLiquidationStatus(
            tokenId,
            maxRepayAmount
        );

        assertEq(liquidationStatus.liquidationAmount, liquidationAmount, "LIQUIDATION_AMOUNT");
        assertEq(liquidationStatus.repayAmount, repayAmount, "REPAY_AMOUNT");

        Types.LoanPosition memory beforeLoanPosition = loanPositionManager.getLoans(tokenId);
        Balance memory balances = Balance({
            beforeUserCoupon1Balance: couponManager.balanceOf(Constants.USER1, coupons[0].id()),
            beforeUserCoupon2Balance: couponManager.balanceOf(Constants.USER1, coupons[1].id()),
            beforeLiquidatorCollateralBalance: collateralToken.balanceOf(address(this)),
            beforeLiquidatorBalance: debtToken.balanceOf(address(this)),
            beforeTreasuryBalance: collateralToken.balanceOf(loanPositionManager.treasury())
        });

        loanPositionManager.liquidate(tokenId, maxRepayAmount, new bytes(0));

        Types.LoanPosition memory afterUserLoanStatus = loanPositionManager.getLoans(tokenId);

        assertEq(beforeLoanPosition.debtAmount - afterUserLoanStatus.debtAmount, repayAmount, "DEBT_AMOUNT");
        assertEq(
            beforeLoanPosition.collateralAmount - afterUserLoanStatus.collateralAmount,
            liquidationAmount + protocolFee,
            "COLLATERAL_AMOUNT"
        );

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
        assertEq(
            beforeLoanPosition.collateralAmount - afterUserLoanStatus.collateralAmount,
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
                    (beforeLoanPosition.debtAmount - afterUserLoanStatus.debtAmount) * 10 ** 20 * 1000000,
                    (beforeLoanPosition.collateralAmount - afterUserLoanStatus.collateralAmount) *
                        oracle.getAssetPrice(address(0)) *
                        980001,
                    "ROUNDING_ISSUE"
                )
                : assertLe(
                    (beforeLoanPosition.debtAmount - afterUserLoanStatus.debtAmount) *
                        oracle.getAssetPrice(address(0)) *
                        1000000,
                    (beforeLoanPosition.collateralAmount - afterUserLoanStatus.collateralAmount) * 10 ** 20 * 980001,
                    "ROUNDING_ISSUE"
                );
            isEthCollateral
                ? assertGe(
                    (beforeLoanPosition.debtAmount - afterUserLoanStatus.debtAmount) * 10 ** 20 * 1000000,
                    (beforeLoanPosition.collateralAmount - afterUserLoanStatus.collateralAmount) *
                        oracle.getAssetPrice(address(0)) *
                        979999,
                    "ROUNDING_ISSUE"
                )
                : assertGe(
                    (beforeLoanPosition.debtAmount - afterUserLoanStatus.debtAmount) *
                        oracle.getAssetPrice(address(0)) *
                        1000000,
                    (beforeLoanPosition.collateralAmount - afterUserLoanStatus.collateralAmount) * 10 ** 20 * 979999,
                    "ROUNDING_ISSUE"
                );
        }
        assertLe(
            (collateralToken.balanceOf(loanPositionManager.treasury()) - balances.beforeTreasuryBalance) * 1000,
            (beforeLoanPosition.collateralAmount - afterUserLoanStatus.collateralAmount) * 5,
            "ROUNDING_ISSUE"
        );
        assertGe(
            (collateralToken.balanceOf(loanPositionManager.treasury()) - balances.beforeTreasuryBalance) * 1000000000,
            (beforeLoanPosition.collateralAmount - afterUserLoanStatus.collateralAmount) * 4999999,
            "ROUNDING_ISSUE"
        );
    }

    function _testRevertLiquidation(
        uint256 debtAmount,
        uint256 collateralAmount,
        uint256 changeData,
        uint256 maxRepayAmount,
        bool isEthCollateral
    ) private {
        Types.Coupon[] memory coupons = new Types.Coupon[](2);
        coupons[0] = Coupon.from(address(usdc), startEpoch, debtAmount);
        coupons[1] = Coupon.from(address(usdc), startEpoch.add(1), debtAmount);
        _mintCoupons(address(this), coupons);

        MockERC20 collateralToken = isEthCollateral ? weth : usdc;
        MockERC20 debtToken = isEthCollateral ? usdc : weth;

        uint256 tokenId = loanPositionManager.mint(
            address(collateralToken),
            address(debtToken),
            collateralAmount,
            debtAmount,
            2,
            Constants.USER1,
            new bytes(0)
        );

        if (changeData == 0) vm.warp(block.timestamp + 1);
        else oracle.setAssetPrice(address(weth), changeData);

        vm.expectRevert(bytes(Errors.TOO_SMALL_DEBT));
        Types.LiquidationStatus memory liquidationStatus = loanPositionManager.getLiquidationStatus(
            tokenId,
            maxRepayAmount
        );

        vm.expectRevert(bytes(Errors.TOO_SMALL_DEBT));
        loanPositionManager.liquidate(tokenId, maxRepayAmount, new bytes(0));
    }

    function testLiquidationWhenPriceChangesAndEthCollateral() public {
        _testLiquidation(
            usdc.amount(1344),
            1 ether,
            1600 * 10 ** 8,
            0,
            0.4975 ether,
            usdc.amount(784),
            0.0025 ether,
            true,
            true
        );
    }

    function testLiquidationWhenPriceChangesAndUsdcCollateral() public {
        _testLiquidation(
            1 ether,
            usdc.amount(3000),
            2500 * 10 ** 8,
            0,
            1421428572,
            560000000168000000,
            7142857,
            false,
            true
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
            usdc.amount(600),
            1 ether,
            610 * 10 ** 8,
            0,
            0.995 ether,
            usdc.amount(600),
            0.005 ether,
            true,
            false
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
        _testLiquidation(
            usdc.amount(12),
            0.015 ether,
            1000 * 10 ** 8,
            0,
            12183673469387756,
            usdc.amount(12),
            61224489795918,
            true,
            true
        );
    }

    function testLiquidationWhenPriceChangesWithSmallDebtWithMaxRepayAmount() public {
        _testLiquidation(
            usdc.amount(12),
            0.015 ether,
            1000 * 10 ** 8,
            usdc.amount(8),
            2030612244897960,
            usdc.amount(2),
            10204081632653,
            true,
            true
        );
    }

    function testRevertLiquidationWhenPriceChangesWithSmallDebtWithMaxRepayAmount() public {
        _testRevertLiquidation(usdc.amount(10), 0.012 ether, 1000 * 10 ** 8, usdc.amount(8), true);
    }

    function testLiquidationWhenPriceChangesWithSmallRemainingDebt() public {
        _testLiquidation(
            usdc.amount(980),
            1 ether,
            1000 * 10 ** 8,
            0,
            0.995 ether,
            usdc.amount(980),
            0.005 ether,
            true,
            true
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
            usdc.amount(100),
            1 ether,
            0,
            0,
            56405895691609978,
            usdc.amount(100),
            283446712018140,
            true,
            true
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
        _testLiquidation(usdc.amount(10), 1 ether, 0, 0, 5640589569160998, usdc.amount(10), 28344671201814, true, true);
    }

    function testLiquidationWhenEpochEndsWithSmallDebtWithMaxRepayAmount() public {
        _testLiquidation(
            usdc.amount(20),
            1 ether,
            0,
            usdc.amount(8),
            1128117913832201,
            usdc.amount(2),
            5668934240362,
            true,
            true
        );
    }

    function testRevertLiquidationWhenEpochEndsWithSmallDebtWithMaxRepayAmount() public {
        _testRevertLiquidation(usdc.amount(10), 1 ether, 0, usdc.amount(8), true);
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
            usdc.amount(100),
            1 ether,
            0,
            usdc.amount(8),
            4512471655328799,
            usdc.amount(8),
            22675736961451,
            true,
            true
        );
    }
}
