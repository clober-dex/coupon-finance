// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IPool} from "../../../contracts/external/aave-v3/IPool.sol";
import {IAssetPool, IAssetPoolTypes} from "../../../contracts/interfaces/IAssetPool.sol";
import {AssetPoolAaveV3} from "../../../contracts/AssetPoolAaveV3.sol";
import {Constants} from "../Constants.sol";
import {ForkUtils, ERC20Utils, Utils} from "../Utils.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract AssetPoolAaveV3UnitTest is Test, IAssetPoolTypes {
    using ERC20Utils for IERC20;

    IAssetPool public assetPool;
    IERC20 public usdc;
    IPool public aavePool;

    function setUp() public {
        ForkUtils.fork(vm, Constants.FORK_BLOCK_NUMBER);
        usdc = IERC20(Constants.USDC);
        vm.startPrank(Constants.USDC_WHALE);
        usdc.transfer(address(this), usdc.amount(1_000_000));
        vm.stopPrank();
        aavePool = IPool(Constants.AAVE_V3_POOL);

        assetPool = new AssetPoolAaveV3(address(aavePool), Constants.TREASURY, Utils.toArr(address(this)));
        assetPool.registerAsset(address(usdc));
    }

    function testDeposit() public {
        uint256 amount = usdc.amount(100);
        usdc.transfer(address(assetPool), amount * 10);

        uint256 beforeAssetPoolBalance = usdc.balanceOf(address(assetPool));
        uint256 beforeTotalReserved = assetPool.totalReservedAmount(address(usdc));

        vm.expectCall(
            address(aavePool), abi.encodeCall(aavePool.supply, (address(usdc), amount, address(assetPool), 0)), 1
        );
        assetPool.deposit(address(usdc), amount);

        uint256 afterAssetPoolBalance = usdc.balanceOf(address(assetPool));
        uint256 afterTotalReserved = assetPool.totalReservedAmount(address(usdc));

        assertEq(afterAssetPoolBalance, beforeAssetPoolBalance - amount, "ASSET_POOL_BALANCE");
        assertEq(afterTotalReserved, beforeTotalReserved + amount, "TOTAL_RESERVED");
    }

    function testDepositWithInvalidAsset() public {
        uint256 amount = usdc.amount(100);
        usdc.transfer(address(assetPool), amount * 10);

        vm.expectRevert(abi.encodeWithSelector(InvalidAsset.selector));
        vm.prank(address(0x123));
        assetPool.deposit(address(0x123), amount);
    }

    function testDepositAccess() public {
        uint256 amount = usdc.amount(100);
        usdc.transfer(address(assetPool), amount * 10);

        vm.expectRevert(abi.encodeWithSelector(InvalidAccess.selector));
        vm.prank(address(0x123));
        assetPool.deposit(address(usdc), amount);
    }

    function testWithdraw() public {
        uint256 amount = usdc.amount(100);
        usdc.transfer(address(assetPool), amount * 10);
        assetPool.deposit(address(usdc), amount * 5);

        uint256 beforeAssetPoolBalance = usdc.balanceOf(address(assetPool));
        uint256 beforeTotalReserved = assetPool.totalReservedAmount(address(usdc));
        uint256 beforeUserBalance = usdc.balanceOf(Constants.USER1);

        vm.expectCall(address(aavePool), abi.encodeCall(aavePool.withdraw, (address(usdc), amount, Constants.USER1)), 1);
        assetPool.withdraw(address(usdc), amount, Constants.USER1);

        uint256 afterAssetPoolBalance = usdc.balanceOf(address(assetPool));
        uint256 afterTotalReserved = assetPool.totalReservedAmount(address(usdc));
        uint256 afterUserBalance = usdc.balanceOf(Constants.USER1);

        assertEq(afterAssetPoolBalance, beforeAssetPoolBalance, "ASSET_POOL_BALANCE");
        assertEq(afterTotalReserved, beforeTotalReserved - amount, "TOTAL_RESERVED");
        assertEq(afterUserBalance, beforeUserBalance + amount, "USER_BALANCE");
    }

    function testWithdrawWhenNotEnoughReserved() public {
        uint256 amount = usdc.amount(100);
        usdc.transfer(address(assetPool), amount * 10);
        assetPool.deposit(address(usdc), amount * 5);

        // withdraw until utilization rate is 0
        IERC20 aToken = IERC20(aavePool.getReserveData(address(usdc)).aTokenAddress);
        uint256 withdrawAmount = aToken.balanceOf(0x4fc126B084fD491cF417c306717019e9C0d6d087);
        vm.prank(0x4fc126B084fD491cF417c306717019e9C0d6d087);
        aavePool.withdraw(address(usdc), withdrawAmount, address(0x123));
        withdrawAmount = usdc.balanceOf(address(aToken)) - amount;
        vm.prank(0x91beB5C41dF001175b588C9510327D53f278972A);
        aavePool.withdraw(address(usdc), withdrawAmount, address(0x123));

        uint256 aTokenUnderlyingBalance = usdc.balanceOf(address(aToken));

        uint256 beforeRecipientBalance = usdc.balanceOf(Constants.USER1);
        uint256 beforeRecipientATokenBalance = aToken.balanceOf(Constants.USER1);
        uint256 beforeTotalReserved = assetPool.totalReservedAmount(address(usdc));

        vm.expectCall(
            address(aavePool),
            abi.encodeCall(aavePool.withdraw, (address(usdc), aTokenUnderlyingBalance, Constants.USER1)),
            1
        );
        assetPool.withdraw(address(usdc), amount, Constants.USER1);

        uint256 afterRecipientBalance = usdc.balanceOf(Constants.USER1);
        uint256 afterRecipientATokenBalance = aToken.balanceOf(Constants.USER1);
        uint256 afterTotalReserved = assetPool.totalReservedAmount(address(usdc));

        assertEq(afterRecipientBalance, beforeRecipientBalance + aTokenUnderlyingBalance, "RECIPIENT_BALANCE");
        assertEq(
            afterRecipientATokenBalance,
            beforeRecipientATokenBalance + (amount - aTokenUnderlyingBalance),
            "RECIPIENT_ATOKEN_BALANCE"
        );
        assertEq(afterTotalReserved, beforeTotalReserved - amount, "TOTAL_RESERVED");
    }

    function testWithdrawWithInvalidAsset() public {
        uint256 amount = usdc.amount(100);
        usdc.transfer(address(assetPool), amount * 10);
        assetPool.deposit(address(usdc), amount * 5);

        vm.expectRevert(abi.encodeWithSelector(InvalidAsset.selector));
        vm.prank(address(0x123));
        assetPool.withdraw(address(0x123), amount, Constants.USER1);
    }

    function testWithdrawAccess() public {
        uint256 amount = usdc.amount(100);
        usdc.transfer(address(assetPool), amount * 10);
        assetPool.deposit(address(usdc), amount * 5);

        vm.expectRevert(abi.encodeWithSelector(InvalidAccess.selector));
        vm.prank(address(0x123));
        assetPool.withdraw(address(usdc), amount, Constants.USER1);
    }

    function testWithdrawMoreThanBalance() public {
        uint256 amount = usdc.amount(100);
        usdc.transfer(address(assetPool), amount * 10);
        assetPool.deposit(address(usdc), amount * 5);

        vm.expectRevert(abi.encodeWithSelector(ExceedsBalance.selector, amount * 5));
        assetPool.withdraw(address(usdc), amount * 10, Constants.USER1);
    }

    function testClaim() public {
        uint256 amount = usdc.amount(100);
        usdc.transfer(address(assetPool), amount * 10);
        assetPool.deposit(address(usdc), amount * 5);

        IERC20 aToken = IERC20(aavePool.getReserveData(address(usdc)).aTokenAddress);

        vm.warp(block.timestamp + 1 weeks);

        uint256 beforeATokenBalance = aToken.balanceOf(address(assetPool));
        uint256 beforeTreasuryBalance = usdc.balanceOf(Constants.TREASURY);
        uint256 beforeTotalReserved = assetPool.totalReservedAmount(address(usdc));

        uint256 claimableAmount = assetPool.claimableAmount(address(usdc));
        assertGt(claimableAmount, 0, "CLAIMABLE_AMOUNT");
        assetPool.claim(address(usdc));

        uint256 afterATokenBalance = aToken.balanceOf(address(assetPool));
        uint256 afterTreasuryBalance = usdc.balanceOf(Constants.TREASURY);
        uint256 afterTotalReserved = assetPool.totalReservedAmount(address(usdc));

        assertApproxEqAbs(afterATokenBalance, beforeATokenBalance - claimableAmount, 1, "ATOKEN_BALANCE");
        assertEq(afterTreasuryBalance, beforeTreasuryBalance + claimableAmount, "TREASURY_BALANCE");
        assertEq(afterTotalReserved, beforeTotalReserved, "TOTAL_RESERVED");
    }

    function testClaimWithInvalidToken() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidAsset.selector));
        assetPool.claim(address(0x123));
    }

    function testSetTreasury() public {
        address newTreasury = address(0x123);
        assetPool.setTreasury(newTreasury);
        assertEq(assetPool.treasury(), newTreasury, "TREASURY");
    }

    function testSetTreasuryAccess() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(address(0x123));
        assetPool.setTreasury(address(0x123));
    }

    function testRegisterAsset() public {
        address btc = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
        assertFalse(assetPool.isAssetRegistered(btc), "IS_ASSET_REGISTERED");

        assetPool.registerAsset(btc);

        assertTrue(assetPool.isAssetRegistered(btc), "IS_ASSET_REGISTERED");
        assertEq(IERC20(btc).allowance(address(assetPool), address(aavePool)), type(uint256).max, "ALLOWANCE");
    }

    function testRegisterAssetWithInvalidAsset() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidAsset.selector));
        assetPool.registerAsset(address(0x123));
    }

    function testRegisterAssetAccess() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidAccess.selector));
        vm.prank(address(0x123));
        assetPool.registerAsset(address(0x123));
    }

    function testWithdrawLostToken() public {
        MockERC20 lostToken = new MockERC20("Lost Token", "LOST", 18);
        lostToken.mint(address(assetPool), lostToken.amount(100));

        uint256 beforeLostTokenBalance = lostToken.balanceOf(address(assetPool));
        uint256 beforeRecipientBalance = lostToken.balanceOf(Constants.USER1);

        assetPool.withdrawLostToken(address(lostToken), Constants.USER1);

        uint256 afterLostTokenBalance = lostToken.balanceOf(address(assetPool));
        uint256 afterRecipientBalance = lostToken.balanceOf(Constants.USER1);

        assertEq(afterLostTokenBalance, beforeLostTokenBalance - lostToken.amount(100), "LOST_TOKEN_BALANCE");
        assertEq(afterRecipientBalance, beforeRecipientBalance + lostToken.amount(100), "RECIPIENT_BALANCE");
    }

    function testWithdrawLostTokenWithInvalidToken() public {
        address aUsdc = aavePool.getReserveData(address(usdc)).aTokenAddress;
        assertFalse(assetPool.isAssetRegistered(aUsdc), "IS_ASSET_REGISTERED");

        vm.expectRevert(abi.encodeWithSelector(InvalidAsset.selector));
        assetPool.withdrawLostToken(address(usdc), Constants.USER1);

        vm.expectRevert(abi.encodeWithSelector(InvalidAsset.selector));
        assetPool.withdrawLostToken(address(aUsdc), Constants.USER1);
    }

    function testWithdrawLostTokenAccess() public {
        MockERC20 lostToken = new MockERC20("Lost Token", "LOST", 18);
        lostToken.mint(address(assetPool), lostToken.amount(100));

        vm.expectRevert(abi.encodeWithSelector(InvalidAccess.selector));
        vm.prank(address(0x123));
        assetPool.withdrawLostToken(address(lostToken), Constants.USER1);
    }
}
