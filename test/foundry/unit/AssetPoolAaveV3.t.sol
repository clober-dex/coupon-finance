// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IPool} from "../../../contracts/external/aave-v3/IPool.sol";
import {IAssetPool, IAssetPoolErrors} from "../../../contracts/interfaces/IAssetPool.sol";
import {Constants} from "../Constants.sol";
import {ForkUtils, ERC20Utils} from "../Utils.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract AssetPoolAaveV3UnitTest is Test, IAssetPoolErrors {
    using ERC20Utils for IERC20;

    IAssetPool public farmer;
    IERC20 public usdc;
    IPool public aavePool;

    function setUp() public {
        ForkUtils.fork(vm, Constants.FORK_BLOCK_NUMBER);
        usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        vm.startPrank(Constants.USDC_WHALE);
        usdc.transfer(address(this), usdc.amount(1_000_000_000));
        vm.stopPrank();

        // _farmer = new AssetPoolAaveV3();
        farmer.registerAsset(address(usdc));
    }

    function testDeposit() public {
        uint256 amount = usdc.amount(100);
        usdc.transfer(address(farmer), amount * 10);

        uint256 beforeAssetPoolBalance = usdc.balanceOf(address(farmer));
        uint256 beforeTotalReserved = farmer.totalReservedAmount(address(usdc));

        vm.expectCall(address(aavePool), abi.encodeCall(IPool.supply, (address(usdc), amount, address(this), 0)));
        farmer.deposit(address(usdc), amount);

        uint256 afterAssetPoolBalance = usdc.balanceOf(address(farmer));
        uint256 afterTotalReserved = farmer.totalReservedAmount(address(usdc));

        assertEq(afterAssetPoolBalance, beforeAssetPoolBalance - amount, "ASSET_POOL_BALANCE");
        assertEq(afterTotalReserved, beforeTotalReserved + amount, "TOTAL_RESERVED");
    }

    function testDepositAccess() public {
        uint256 amount = usdc.amount(100);
        usdc.transfer(address(farmer), amount * 10);

        vm.expectRevert(abi.encodeWithSelector(InvalidAsset.selector));
        vm.prank(address(0x123));
        farmer.deposit(address(usdc), amount);
    }

    function testWithdraw() public {
        uint256 amount = usdc.amount(100);
        usdc.transfer(address(farmer), amount * 10);
        farmer.deposit(address(usdc), amount * 5);

        uint256 beforeAssetPoolBalance = usdc.balanceOf(address(farmer));
        uint256 beforeTotalReserved = farmer.totalReservedAmount(address(usdc));
        uint256 beforeUserBalance = usdc.balanceOf(Constants.USER1);

        vm.expectCall(address(aavePool), abi.encodeCall(IPool.withdraw, (address(usdc), amount, Constants.USER1)));
        farmer.withdraw(address(usdc), amount, Constants.USER1);

        uint256 afterAssetPoolBalance = usdc.balanceOf(address(farmer));
        uint256 afterTotalReserved = farmer.totalReservedAmount(address(usdc));
        uint256 afterUserBalance = usdc.balanceOf(Constants.USER1);

        assertEq(afterAssetPoolBalance, beforeAssetPoolBalance, "ASSET_POOL_BALANCE");
        assertEq(afterTotalReserved, beforeTotalReserved - amount, "TOTAL_RESERVED");
        assertEq(afterUserBalance, beforeUserBalance + amount, "USER_BALANCE");
    }

    function testWithdrawAccess() public {
        uint256 amount = usdc.amount(100);
        usdc.transfer(address(farmer), amount * 10);
        farmer.deposit(address(usdc), amount * 5);

        vm.expectRevert(abi.encodeWithSelector(InvalidAsset.selector));
        vm.prank(address(0x123));
        farmer.withdraw(address(usdc), amount, Constants.USER1);
    }

    function testWithdrawMoreThanBalance() public {
        uint256 amount = usdc.amount(100);
        usdc.transfer(address(farmer), amount * 10);
        farmer.deposit(address(usdc), amount * 5);

        vm.expectRevert(abi.encodeWithSelector(ExceedsBalance.selector, amount * 5));
        farmer.withdraw(address(usdc), amount * 10, Constants.USER1);
    }

    function testClaim() public {
        uint256 amount = usdc.amount(100);
        usdc.transfer(address(farmer), amount * 10);
        farmer.deposit(address(usdc), amount * 5);

        IERC20 aToken = IERC20(aavePool.getReserveData(address(usdc)).aTokenAddress);

        uint256 beforeATokenBalance = aToken.balanceOf(address(farmer));
        uint256 beforeUserBalance = usdc.balanceOf(Constants.USER1);
        uint256 beforeTotalReserved = farmer.totalReservedAmount(address(usdc));

        vm.warp(block.timestamp + 1 weeks);
        uint256 aTokenDiff = aToken.balanceOf(address(farmer)) - beforeATokenBalance;
        assertGt(aTokenDiff, 0, "ATOKEN_BALANCE");
        assertEq(farmer.claimableAmount(address(usdc)), aTokenDiff, "CLAIMABLE_AMOUNT");
        farmer.claim(address(usdc));

        uint256 afterATokenBalance = aToken.balanceOf(address(farmer));
        uint256 afterUserBalance = usdc.balanceOf(Constants.USER1);
        uint256 afterTotalReserved = farmer.totalReservedAmount(address(usdc));

        assertEq(afterATokenBalance, beforeATokenBalance - aTokenDiff, "ATOKEN_BALANCE");
        assertEq(afterUserBalance, beforeUserBalance + aTokenDiff, "USER_BALANCE");
        assertEq(afterTotalReserved, beforeTotalReserved, "TOTAL_RESERVED");
    }

    function testSetTreasury() public {
        address newTreasury = address(0x123);
        farmer.setTreasury(newTreasury);
        assertEq(farmer.treasury(), newTreasury, "TREASURY");
    }

    function testSetTreasuryAccess() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidAsset.selector));
        vm.prank(address(0x123));
        farmer.setTreasury(address(0x123));
    }

    function testRegisterAsset() public {
        address btc = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        address aBtc = aavePool.getReserveData(btc).aTokenAddress;
        assertFalse(farmer.isAssetRegistered(btc), "IS_ASSET_REGISTERED");
        assertFalse(farmer.isAssetRegistered(aBtc), "IS_ASSET_REGISTERED");

        farmer.registerAsset(btc);

        assertTrue(farmer.isAssetRegistered(btc), "IS_ASSET_REGISTERED");
        assertTrue(farmer.isAssetRegistered(aBtc), "IS_ASSET_REGISTERED");
    }

    function testRegisterAssetWithInvalidAsset() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidAsset.selector));
        farmer.registerAsset(address(0x123));
    }

    function testRegisterAssetAccess() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidAsset.selector));
        vm.prank(address(0x123));
        farmer.registerAsset(address(0x123));
    }

    function testWithdrawLostToken() public {
        MockERC20 lostToken = new MockERC20("Lost Token", "LOST", 18);
        lostToken.mint(address(farmer), lostToken.amount(100));

        uint256 beforeLostTokenBalance = lostToken.balanceOf(address(farmer));
        uint256 beforeRecipientBalance = lostToken.balanceOf(Constants.USER1);

        farmer.withdrawLostToken(address(lostToken), Constants.USER1);

        uint256 afterLostTokenBalance = lostToken.balanceOf(address(farmer));
        uint256 afterRecipientBalance = lostToken.balanceOf(Constants.USER1);

        assertEq(afterLostTokenBalance, beforeLostTokenBalance - lostToken.amount(100), "LOST_TOKEN_BALANCE");
        assertEq(afterRecipientBalance, beforeRecipientBalance + lostToken.amount(100), "RECIPIENT_BALANCE");
    }

    function testWithdrawLostTokenWithInvalidToken() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidAsset.selector));
        farmer.withdrawLostToken(address(usdc), Constants.USER1);
    }

    function testWithdrawLostTokenAccess() public {}
}
