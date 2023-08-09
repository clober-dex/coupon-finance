// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {CouponManager} from "../../../contracts/CouponManager.sol";
import {ICouponManager} from "../../../contracts/interfaces/ICouponManager.sol";
import {CouponKey, CouponKeyLibrary} from "../../../contracts/libraries/CouponKey.sol";
import {Coupon, CouponLibrary} from "../../../contracts/libraries/Coupon.sol";
import {Epoch, EpochLibrary} from "../../../contracts/libraries/Epoch.sol";
import {Constants} from "../Constants.sol";
import {Utils} from "../Utils.sol";
import {ForkUtils, ERC20Utils, Utils} from "../Utils.sol";
import "../../../contracts/AaveTokenSubstitute.sol";

contract AaveTokenSubstituteUnitTest is Test, ERC1155Holder {
    using ERC20Utils for IERC20;

    AaveTokenSubstitute public aaveTokenSubstitute;
    IERC20 public usdc;
    IERC20 public aUsdc;

    function setUp() public {
        ForkUtils.fork(vm, Constants.FORK_BLOCK_NUMBER);

        usdc = IERC20(Constants.USDC);
        vm.startPrank(Constants.USDC_WHALE);
        usdc.transfer(address(this), usdc.amount(1_000_000));
        vm.stopPrank();

        aaveTokenSubstitute = new AaveTokenSubstitute(
            Constants.USDC,
            Constants.AAVE_V3_POOL
        );

        aUsdc = IERC20(aaveTokenSubstitute.aToken());

        usdc.approve(Constants.AAVE_V3_POOL, usdc.amount(500_000));
        IPool(Constants.AAVE_V3_POOL).supply(Constants.USDC, usdc.amount(500_000), address(this), 0);
    }

    function testMint() public {
        uint256 amount = usdc.amount(1_000);

        uint256 beforeUsdcBalance = usdc.balanceOf(address(this));
        uint256 beforeAusdcBalance = aUsdc.balanceOf(address(this));
        uint256 beforeWausdcBalance = aaveTokenSubstitute.balanceOf(address(this));

        IERC20(aUsdc).approve(address(aaveTokenSubstitute), amount);
        aaveTokenSubstitute.mint(amount, address(this));

        assertEq(beforeUsdcBalance, usdc.balanceOf(address(this)), "USDC_BALANCE");
        assertEq(beforeAusdcBalance, aUsdc.balanceOf(address(this)) + amount, "AUSDC_BALANCE");
        assertEq(beforeWausdcBalance + amount, aaveTokenSubstitute.balanceOf(address(this)), "WAUSDC_BALANCE");
    }

    function testMintWithUnderlying() public {
        uint256 amount = usdc.amount(1_000);

        uint256 beforeUsdcBalance = usdc.balanceOf(address(this));
        uint256 beforeAusdcBalance = aUsdc.balanceOf(address(this));
        uint256 beforeWausdcBalance = aaveTokenSubstitute.balanceOf(address(this));

        IERC20(usdc).approve(address(aaveTokenSubstitute), amount);
        aaveTokenSubstitute.mintByUnderlying(amount, address(this));

        assertEq(beforeUsdcBalance, usdc.balanceOf(address(this)) + amount, "USDC_BALANCE");
        assertEq(beforeAusdcBalance, aUsdc.balanceOf(address(this)), "AUSDC_BALANCE");
        assertEq(beforeWausdcBalance + amount, aaveTokenSubstitute.balanceOf(address(this)), "WAUSDC_BALANCE");
    }

    function testBurn() public {
        uint256 amount = usdc.amount(1_000);
        IERC20(aUsdc).approve(address(aaveTokenSubstitute), amount);
        aaveTokenSubstitute.mint(amount, address(this));

        uint256 beforeUsdcBalance = usdc.balanceOf(address(this));
        uint256 beforeAusdcBalance = aUsdc.balanceOf(address(this));
        uint256 beforeWausdcBalance = aaveTokenSubstitute.balanceOf(address(this));

        aaveTokenSubstitute.burn(amount, address(this));
        assertEq(beforeUsdcBalance, usdc.balanceOf(address(this)), "USDC_BALANCE");
        assertEq(beforeAusdcBalance + amount, aUsdc.balanceOf(address(this)), "AUSDC_BALANCE");
        assertEq(beforeWausdcBalance, aaveTokenSubstitute.balanceOf(address(this)) + amount, "WAUSDC_BALANCE");
    }

    function testBurnWithUnderlying() public {
        uint256 amount = usdc.amount(1_000);
        IERC20(aUsdc).approve(address(aaveTokenSubstitute), amount);
        aaveTokenSubstitute.mint(amount, address(this));

        uint256 beforeUsdcBalance = usdc.balanceOf(address(this));
        uint256 beforeAusdcBalance = aUsdc.balanceOf(address(this));
        uint256 beforeWausdcBalance = aaveTokenSubstitute.balanceOf(address(this));

        aaveTokenSubstitute.burnToUnderlying(amount, address(this));

        assertEq(beforeUsdcBalance + amount, usdc.balanceOf(address(this)), "USDC_BALANCE");
        assertEq(beforeAusdcBalance, aUsdc.balanceOf(address(this)), "AUSDC_BALANCE");
        assertEq(beforeWausdcBalance, aaveTokenSubstitute.balanceOf(address(this)) + amount, "WAUSDC_BALANCE");
    }
}
