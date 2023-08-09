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

        uint256 beforeTokenBalance = usdc.balanceOf(address(this));
        uint256 beforeATokenBalance = aUsdc.balanceOf(address(this));
        uint256 beforeSubstituteBalance = aaveTokenSubstitute.balanceOf(address(this));

        IERC20(usdc).approve(address(aaveTokenSubstitute), amount);
        aaveTokenSubstitute.mint(amount, address(this));

        assertEq(beforeTokenBalance, usdc.balanceOf(address(this)) + amount, "USDC_BALANCE");
        assertEq(beforeATokenBalance, aUsdc.balanceOf(address(this)), "AUSDC_BALANCE");
        assertEq(beforeSubstituteBalance + amount, aaveTokenSubstitute.balanceOf(address(this)), "WAUSDC_BALANCE");
    }

    function testMintByAToken() public {
        uint256 amount = usdc.amount(1_000);

        uint256 beforeTokenBalance = usdc.balanceOf(address(this));
        uint256 beforeATokenBalance = aUsdc.balanceOf(address(this));
        uint256 beforeSubstituteBalance = aaveTokenSubstitute.balanceOf(address(this));

        IERC20(aUsdc).approve(address(aaveTokenSubstitute), amount);
        aaveTokenSubstitute.mintByAToken(amount, address(this));

        assertEq(beforeTokenBalance, usdc.balanceOf(address(this)), "USDC_BALANCE");
        assertEq(beforeATokenBalance, aUsdc.balanceOf(address(this)) + amount, "AUSDC_BALANCE");
        assertEq(beforeSubstituteBalance + amount, aaveTokenSubstitute.balanceOf(address(this)), "WAUSDC_BALANCE");
    }

    function testMintableAmount() public {
        assertEq(aaveTokenSubstitute.mintableAmount(), 41000000000000, "MINTABLE_AMOUNT");
    }

    function testBurnableAmount() public {
        assertEq(aaveTokenSubstitute.burnableAmount(), 1320271880938, "BURNABLE_AMOUNT");
    }

    function testBurn() public {
        uint256 amount = usdc.amount(1_000);
        IERC20(usdc).approve(address(aaveTokenSubstitute), amount);
        aaveTokenSubstitute.mint(amount, address(this));

        uint256 beforeTokenBalance = usdc.balanceOf(address(this));
        uint256 beforeATokenBalance = aUsdc.balanceOf(address(this));
        uint256 beforeSubstituteBalance = aaveTokenSubstitute.balanceOf(address(this));

        aaveTokenSubstitute.burn(amount, address(this));

        assertEq(beforeTokenBalance + amount, usdc.balanceOf(address(this)), "USDC_BALANCE");
        assertEq(beforeATokenBalance, aUsdc.balanceOf(address(this)), "AUSDC_BALANCE");
        assertEq(beforeSubstituteBalance, aaveTokenSubstitute.balanceOf(address(this)) + amount, "WAUSDC_BALANCE");
    }

    function testBurnByAToken() public {
        uint256 amount = usdc.amount(100);
        IERC20(usdc).approve(address(aaveTokenSubstitute), amount);
        aaveTokenSubstitute.mint(amount, address(this));

        uint256 beforeTokenBalance = usdc.balanceOf(address(this));
        uint256 beforeATokenBalance = aUsdc.balanceOf(address(this));
        uint256 beforeSubstituteBalance = aaveTokenSubstitute.balanceOf(address(this));

        aaveTokenSubstitute.burnToAToken(amount, address(this));

        assertEq(beforeTokenBalance, usdc.balanceOf(address(this)), "USDC_BALANCE");
        assertEq(beforeATokenBalance + amount, aUsdc.balanceOf(address(this)), "AUSDC_BALANCE");
        assertEq(beforeSubstituteBalance, aaveTokenSubstitute.balanceOf(address(this)) + amount, "WAUSDC_BALANCE");
    }
}
