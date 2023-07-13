// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

import {Types} from "../../../contracts/Types.sol";
import {ILoanPosition, ILoanPositionEvents} from "../../../contracts/interfaces/ILoanPosition.sol";
import {INewCoupon} from "../../../contracts/interfaces/INewCoupon.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockYieldFarmer} from "../mocks/MockYieldFarmer.sol";
import {MockOracle} from "../mocks/MockOracle.sol";
import {Constants} from "./Constants.sol";

contract LoanPositionUnitTest is Test, ILoanPositionEvents, ERC1155Holder, ERC721Holder {
    MockERC20 public collateral;
    MockERC20 public usdc;

    MockOracle public oracle;
    MockYieldFarmer public yieldFarmer;
    INewCoupon public coupon;
    ILoanPosition public loanPosition;

    uint256 private _snapshotId;
    Types.PermitParams private _permitParams;

    uint256 private _initialCollateralAmount;
    uint256 private _initialDebtAmount;

    function setUp() public {
        collateral = new MockERC20("Collateral Token", "COL", 18);
        usdc = new MockERC20("USD coin", "USDC", 6);

        collateral.mint(address(this), collateral.amount(2_000_000_000));
        usdc.mint(address(this), usdc.amount(2_000_000_000));

        yieldFarmer = new MockYieldFarmer();
        oracle = new MockOracle();
        // loanPosition = new LoanPosition();

        collateral.approve(address(loanPosition), type(uint256).max);
        usdc.approve(address(loanPosition), type(uint256).max);
        collateral.approve(address(yieldFarmer), type(uint256).max);
        usdc.approve(address(yieldFarmer), type(uint256).max);
        yieldFarmer.deposit(address(collateral), collateral.amount(1_000_000_000));
        yieldFarmer.deposit(address(usdc), collateral.amount(1_000_000_000));

        oracle.setAssetPrice(address(collateral), 1800 * 10 ** 8);
        oracle.setAssetPrice(address(usdc), 10 ** 8);

        _initialCollateralAmount = collateral.amount(1);
        _initialDebtAmount = usdc.amount(100);
    }

    function _mintCoupons(address to, Types.Coupon[] memory coupons) internal {
        address minter = coupon.minter();
        vm.startPrank(minter);
        coupon.mintBatch(to, coupons, new bytes(0));
        vm.stopPrank();
    }

    function testMint() public {
        uint256 beforeCollateralBalance = collateral.balanceOf(address(this));
        uint256 beforeDebtBalance = usdc.balanceOf(Constants.USER1);
        uint256 beforeLoanPositionBalance = loanPosition.balanceOf(Constants.USER1);
        uint256 nextId = loanPosition.nextId();
        uint256 expectedExpiredAt = coupon.epochEndTime(2);

        Types.Coupon[] memory coupons = new Types.Coupon[](2);
        coupons[0] = Types.Coupon({key: Types.CouponKey({asset: address(usdc), epoch: 1}), amount: _initialDebtAmount});
        coupons[1] = Types.Coupon({key: Types.CouponKey({asset: address(usdc), epoch: 2}), amount: _initialDebtAmount});
        _mintCoupons(address(this), coupons);

        _snapshotId = vm.snapshot();
        vm.expectEmit(true, true, true, true);
        emit PositionUpdated(nextId, _initialCollateralAmount, _initialDebtAmount, expectedExpiredAt);
        loanPosition.mint(
            address(collateral),
            address(usdc),
            _initialCollateralAmount,
            _initialDebtAmount,
            2,
            Constants.USER1,
            new bytes(0)
        );
        vm.revertTo(_snapshotId);
        vm.expectCall(address(coupon), abi.encodeCall(INewCoupon.burnBatch, (address(this), coupons)));
        uint256 tokenId = loanPosition.mint(
            address(collateral),
            address(usdc),
            _initialCollateralAmount,
            _initialDebtAmount,
            2,
            Constants.USER1,
            new bytes(0)
        );

        Types.Loan memory loan = loanPosition.loans(tokenId);

        assertEq(tokenId, nextId, "TOKEN_ID");
        assertEq(usdc.balanceOf(Constants.USER1), beforeDebtBalance + _initialDebtAmount, "DEBT_BALANCE");
        assertEq(
            collateral.balanceOf(address(this)),
            beforeCollateralBalance - _initialCollateralAmount,
            "COLLATERAL_BALANCE"
        );
        assertEq(loanPosition.balanceOf(Constants.USER1), beforeLoanPositionBalance + 1, "LOAN_POSITION_BALANCE");
        assertEq(loanPosition.nextId(), nextId + 1, "NEXT_ID");
        assertEq(loanPosition.ownerOf(tokenId), Constants.USER1, "OWNER_OF");
        assertEq(loan.collateralToken, address(collateral), "COLLATERAL_ASSET");
        assertEq(loan.debtToken, address(usdc), "DEBT_ASSET");
        assertEq(loan.collateralAmount, _initialCollateralAmount, "COLLATERAL_AMOUNT");
        assertEq(loan.debtAmount, _initialDebtAmount, "DEBT_AMOUNT");
        assertEq(loan.expiredAt, expectedExpiredAt, "EXPIRED_AT");
    }

    function testMintWithTooSmallDebtAmount() public {}

    function testMintWithInsufficientCollateralAmount() public {}
}
