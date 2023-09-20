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
import {Utils} from "../../Utils.sol";

import {LoanPositionBurnHelper} from "./helpers/BurnHelper.sol";
import {LoanPositionMintHelper} from "./helpers/MintHelper.sol";
import {TestInitializer} from "./helpers/TestInitializer.sol";

contract LoanPositionManagerBurnUnitTest is Test, ILoanPositionManagerTypes {
    using CouponLibrary for Coupon;
    using EpochLibrary for Epoch;

    MockERC20 public weth;
    MockERC20 public usdc;

    MockOracle public oracle;
    IAssetPool public assetPool;
    ICouponManager public couponManager;
    ILoanPositionManager public loanPositionManager;

    Epoch public startEpoch;
    uint256 public initialCollateralAmount;
    uint256 public initialDebtAmount;

    LoanPositionBurnHelper public helper;
    LoanPositionMintHelper public mintHelper;

    uint256 public tokenId;

    function setUp() public {
        vm.warp(Epoch.wrap(10).startTime());

        TestInitializer.Params memory p = TestInitializer.init(vm);
        weth = p.weth;
        usdc = p.usdc;
        oracle = p.oracle;
        assetPool = p.assetPool;
        couponManager = p.couponManager;
        loanPositionManager = p.loanPositionManager;
        startEpoch = p.startEpoch;
        initialCollateralAmount = p.initialCollateralAmount;
        initialDebtAmount = p.initialDebtAmount;

        helper = new LoanPositionBurnHelper(address(loanPositionManager));
        vm.startPrank(address(helper));
        weth.approve(address(loanPositionManager), type(uint256).max);
        usdc.approve(address(loanPositionManager), type(uint256).max);
        vm.stopPrank();

        mintHelper = new LoanPositionMintHelper(address(loanPositionManager));
        vm.startPrank(address(mintHelper));
        weth.approve(address(loanPositionManager), type(uint256).max);
        usdc.approve(address(loanPositionManager), type(uint256).max);
        vm.stopPrank();

        weth.transfer(address(mintHelper), initialCollateralAmount);
        tokenId = mintHelper.mint(address(weth), address(usdc), initialCollateralAmount, 0, startEpoch, address(this));
        loanPositionManager.setApprovalForAll(address(helper), true);

        vm.warp(startEpoch.add(2).startTime());
    }

    function _mintCoupons(address to, Coupon[] memory coupons) internal {
        couponManager.mintBatch(to, coupons, "");
    }

    function testBurnExpiredPosition() public {
        LoanPosition memory beforePosition = loanPositionManager.getPosition(tokenId);
        assertEq(beforePosition.collateralAmount, initialCollateralAmount);
        assertEq(beforePosition.debtAmount, 0);

        uint256 beforePositionBalance = loanPositionManager.balanceOf(address(this));

        vm.expectEmit(true, true, true, true);
        emit UpdatePosition(tokenId, 0, 0, beforePosition.expiredWith);
        vm.expectCall(
            address(assetPool),
            abi.encodeCall(assetPool.withdraw, (address(weth), initialCollateralAmount, address(helper)))
        );
        helper.burn(tokenId);

        LoanPosition memory afterPosition = loanPositionManager.getPosition(tokenId);

        assertEq(loanPositionManager.balanceOf(address(this)), beforePositionBalance - 1, "INVALID_POSITION_BALANCE");
        assertEq(afterPosition.collateralAmount, 0, "INVALID_COLLATERAL_AMOUNT");
        assertEq(afterPosition.debtAmount, 0, "INVALID_DEBT_AMOUNT");
        assertEq(afterPosition.expiredWith, beforePosition.expiredWith, "INVALID_EXPIRED_WITH");
        vm.expectRevert("ERC721: invalid token ID");
        loanPositionManager.ownerOf(tokenId);
    }

    function testBurnOwnership() public {
        loanPositionManager.setApprovalForAll(address(helper), false);
        vm.expectRevert(abi.encodeWithSelector(InvalidAccess.selector));
        helper.burn(tokenId);
    }

    function testBurnExpiredPositionWhenDebtIsNotZero() public {
        weth.transfer(address(mintHelper), initialCollateralAmount);
        Epoch current = EpochLibrary.current();
        _mintCoupons(address(mintHelper), Utils.toArr(CouponLibrary.from(address(usdc), current, initialDebtAmount)));
        tokenId = mintHelper.mint(
            address(weth), address(usdc), initialCollateralAmount, initialDebtAmount, current, address(helper)
        );

        vm.warp(current.add(1).startTime());

        vm.expectRevert(abi.encodeWithSelector(AlreadyExpired.selector));
        helper.burn(tokenId);
    }

    function assertEq(Epoch e1, Epoch e2, string memory err) internal {
        assertEq(Epoch.unwrap(e1), Epoch.unwrap(e2), err);
    }
}
