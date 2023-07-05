// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ILendingPoolEvents, ILendingPool, ILendingPoolTypes} from "../../../contracts/interfaces/ILendingPool.sol";
import {IWETH9} from "../../../contracts/external/weth/IWETH9.sol";
import {IYieldFarmer} from "../../../contracts/interfaces/IYieldFarmer.sol";
import {CouponKeyLibrary, LoanKeyLibrary} from "../../../contracts/libraries/Keys.sol";
import {MockYieldFarmer} from "../mocks/MockYieldFarmer.sol";
import {ForkTestSetUp} from "../ForkTestSetUp.sol";
import {ERC20Utils} from "../Utils.sol";

contract LendingPoolUnitTest is Test, ILendingPoolEvents, ILendingPoolTypes {
    using ERC20Utils for IERC20;
    using CouponKeyLibrary for CouponKey;
    using LoanKeyLibrary for LoanKey;

    address private constant _USDC_WHALE = 0xcEe284F754E854890e311e3280b767F80797180d;
    address private constant _USER1 = address(0x1);
    address private constant _USER2 = address(0x2);

    IERC20 private _usdc;
    IWETH9 private _weth;
    ILendingPool private _lendingPool;
    MockYieldFarmer private _yieldFarmer;

    receive() external payable {}

    function setUp() public {
        ForkTestSetUp forkSetUp = new ForkTestSetUp();
        forkSetUp.fork(17617512);

        _weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        _usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

        _yieldFarmer = new MockYieldFarmer();
        // _lendingPool = new LendingPool();

        vm.prank(_USDC_WHALE);
        _usdc.transfer(address(this), _usdc.amount(1_000_000_000));
        vm.deal(address(this), 2_000_000_000 ether);
        _weth.deposit{value: 1_000_000_000 ether}();

        _usdc.approve(address(_lendingPool), type(uint256).max);
        _weth.approve(address(_lendingPool), type(uint256).max);
    }

    function testDeposit() public {
        Reserve memory beforeReserve = _lendingPool.getReserve(address(_usdc));
        Vault memory beforeVault = _lendingPool.getVault(address(_usdc), _USER1);
        uint256 beforeThisBalance = _usdc.balanceOf(address(this));
        uint256 beforeYieldFarmerBalance = _yieldFarmer.totalReservedAmount(address(_usdc));

        uint256 amount = _usdc.amount(100);
        vm.expectEmit(true, true, true, true);
        emit Deposit(address(_usdc), address(this), _USER1, amount);
        _lendingPool.deposit(address(_usdc), amount, _USER1);

        Reserve memory afterReserve = _lendingPool.getReserve(address(_usdc));
        Vault memory afterVault = _lendingPool.getVault(address(_usdc), _USER1);

        assertEq(_usdc.balanceOf(address(this)) + amount, beforeThisBalance, "THIS_BALANCE");
        assertEq(
            _yieldFarmer.totalReservedAmount(address(_usdc)),
            beforeYieldFarmerBalance + amount,
            "YIELD_FARMER_BALANCE"
        );
        assertEq(beforeReserve.spendableAmount + amount, afterReserve.spendableAmount, "RESERVE_AMOUNT");
        assertEq(beforeVault.spendableAmount + amount, afterVault.spendableAmount, "VAULT_AMOUNT");
    }

    function testDepositNative() public {
        Reserve memory beforeReserve = _lendingPool.getReserve(address(_weth));
        Vault memory beforeVault = _lendingPool.getVault(address(_weth), _USER1);
        uint256 beforeThisNativeBalance = address(this).balance;
        uint256 beforeThisBalance = _weth.balanceOf(address(this));
        uint256 beforeYieldFarmerBalance = _yieldFarmer.totalReservedAmount(address(_weth));

        uint256 amount1 = 100 ether;
        uint256 amount2 = 50 ether;
        vm.expectEmit(true, true, true, true);
        emit Deposit(address(_weth), address(this), _USER1, amount1 + amount2);
        _lendingPool.deposit{value: amount1}(address(_weth), amount2, _USER1);

        Reserve memory afterReserve = _lendingPool.getReserve(address(_weth));
        Vault memory afterVault = _lendingPool.getVault(address(_weth), _USER1);

        assertEq(address(this).balance + amount1, beforeThisNativeBalance, "THIS_NATIVE_BALANCE");
        assertEq(_weth.balanceOf(address(this)) + amount2, beforeThisBalance, "THIS_BALANCE");
        assertEq(
            _yieldFarmer.totalReservedAmount(address(_weth)),
            beforeYieldFarmerBalance + amount1 + amount2,
            "YIELD_FARMER_BALANCE"
        );
        assertEq(beforeReserve.spendableAmount + amount1 + amount2, afterReserve.spendableAmount, "RESERVE_AMOUNT");
        assertEq(beforeVault.spendableAmount + amount1 + amount2, afterVault.spendableAmount, "VAULT_AMOUNT");
    }

    function testWithdraw() public {
        uint256 amount = _usdc.amount(100);
        _lendingPool.deposit(address(_usdc), amount, address(this));

        Reserve memory beforeReserve = _lendingPool.getReserve(address(_usdc));
        Vault memory beforeVault = _lendingPool.getVault(address(_usdc), address(this));
        uint256 beforeRecipientBalance = _usdc.balanceOf(_USER1);
        uint256 beforePoolBalance = _usdc.balanceOf(address(_lendingPool));
        uint256 beforeYieldFarmerBalance = _yieldFarmer.totalReservedAmount(address(_usdc));

        vm.expectEmit(true, true, true, true);
        emit Withdraw(address(_usdc), address(this), _USER1, amount);
        uint256 returnValue = _lendingPool.withdraw(address(_usdc), amount, _USER1);
        assertEq(returnValue, amount, "RETURN_VALUE");

        Reserve memory afterReserve = _lendingPool.getReserve(address(_usdc));
        Vault memory afterVault = _lendingPool.getVault(address(_usdc), address(this));

        assertEq(_usdc.balanceOf(_USER1), beforeRecipientBalance + amount, "THIS_BALANCE");
        assertEq(_usdc.balanceOf(address(_lendingPool)), beforePoolBalance, "POOL_BALANCE");
        assertEq(
            _yieldFarmer.totalReservedAmount(address(_usdc)) + amount,
            beforeYieldFarmerBalance,
            "YIELD_FARMER_BALANCE"
        );
        assertEq(beforeReserve.spendableAmount, afterReserve.spendableAmount + amount, "RESERVE_AMOUNT");
        assertEq(beforeVault.spendableAmount, afterVault.spendableAmount + amount, "VAULT_AMOUNT");
    }

    function testWithdrawNative() public {
        uint256 amount = 100 ether;
        _lendingPool.deposit(address(_weth), amount, address(this));

        Reserve memory beforeReserve = _lendingPool.getReserve(address(_weth));
        Vault memory beforeVault = _lendingPool.getVault(address(_weth), address(this));
        uint256 beforeRecipientNativeBalance = _USER1.balance;
        uint256 beforeYieldFarmerBalance = _yieldFarmer.totalReservedAmount(address(_weth));

        vm.expectEmit(true, true, true, true);
        emit Withdraw(address(_weth), address(this), _USER1, amount);
        uint256 returnValue = _lendingPool.withdraw(address(0), amount, _USER1);
        assertEq(returnValue, amount, "RETURN_VALUE");

        Reserve memory afterReserve = _lendingPool.getReserve(address(_weth));
        Vault memory afterVault = _lendingPool.getVault(address(_weth), address(this));

        assertEq(_USER1.balance, beforeRecipientNativeBalance + amount, "THIS_NATIVE_BALANCE");
        assertEq(
            _yieldFarmer.totalReservedAmount(address(_weth)) + amount,
            beforeYieldFarmerBalance,
            "YIELD_FARMER_BALANCE"
        );
        assertEq(beforeReserve.spendableAmount, afterReserve.spendableAmount + amount, "RESERVE_AMOUNT");
        assertEq(beforeVault.spendableAmount, afterVault.spendableAmount + amount, "VAULT_AMOUNT");
    }

    function testWithdrawWhenWithdrawalLimitExists() public {
        uint256 amount = _usdc.amount(100);
        _lendingPool.deposit(address(_usdc), amount, address(this));

        _yieldFarmer.setWithdrawLimit(address(_usdc), amount / 2);
        assertEq(_lendingPool.withdrawable(address(_usdc)), amount / 2, "WITHDRAWABLE");

        Reserve memory beforeReserve = _lendingPool.getReserve(address(_usdc));
        Vault memory beforeVault = _lendingPool.getVault(address(_usdc), address(this));
        uint256 beforeRecipientBalance = _usdc.balanceOf(_USER1);
        uint256 beforePoolBalance = _usdc.balanceOf(address(_lendingPool));
        uint256 beforeYieldFarmerBalance = _yieldFarmer.totalReservedAmount(address(_usdc));

        vm.expectEmit(true, true, true, true);
        emit Withdraw(address(_usdc), address(this), _USER1, amount / 2);
        uint256 returnValue = _lendingPool.withdraw(address(_usdc), amount, _USER1);
        assertEq(returnValue, amount / 2, "RETURN_VALUE");

        Reserve memory afterReserve = _lendingPool.getReserve(address(_usdc));
        Vault memory afterVault = _lendingPool.getVault(address(_usdc), address(this));

        assertEq(_usdc.balanceOf(_USER1), beforeRecipientBalance + amount / 2, "THIS_BALANCE");
        assertEq(_usdc.balanceOf(address(_lendingPool)), beforePoolBalance, "POOL_BALANCE");
        assertEq(
            _yieldFarmer.totalReservedAmount(address(_usdc)) + amount / 2,
            beforeYieldFarmerBalance,
            "YIELD_FARMER_BALANCE"
        );
        assertEq(beforeReserve.spendableAmount, afterReserve.spendableAmount + amount / 2, "RESERVE_AMOUNT");
        assertEq(beforeVault.spendableAmount, afterVault.spendableAmount + amount / 2, "VAULT_AMOUNT");
    }

    function testWithdrawWhenAmountExceedsDepositedAmount() public {
        uint256 amount = _usdc.amount(100);
        _lendingPool.deposit(address(_usdc), amount, address(this));

        Reserve memory beforeReserve = _lendingPool.getReserve(address(_usdc));
        Vault memory beforeVault = _lendingPool.getVault(address(_usdc), address(this));
        uint256 beforeRecipientBalance = _usdc.balanceOf(_USER1);
        uint256 beforePoolBalance = _usdc.balanceOf(address(_lendingPool));
        uint256 beforeYieldFarmerBalance = _yieldFarmer.totalReservedAmount(address(_usdc));

        vm.expectEmit(true, true, true, true);
        emit Withdraw(address(_usdc), address(this), _USER1, amount);
        uint256 returnValue = _lendingPool.withdraw(address(_usdc), amount * 2, _USER1);
        assertEq(returnValue, amount, "RETURN_VALUE");

        Reserve memory afterReserve = _lendingPool.getReserve(address(_usdc));
        Vault memory afterVault = _lendingPool.getVault(address(_usdc), address(this));

        assertEq(_usdc.balanceOf(_USER1), beforeRecipientBalance + amount, "THIS_BALANCE");
        assertEq(_usdc.balanceOf(address(_lendingPool)), beforePoolBalance, "POOL_BALANCE");
        assertEq(
            _yieldFarmer.totalReservedAmount(address(_usdc)) + amount,
            beforeYieldFarmerBalance,
            "YIELD_FARMER_BALANCE"
        );
        assertEq(beforeReserve.spendableAmount, afterReserve.spendableAmount + amount, "RESERVE_AMOUNT");
        assertEq(beforeVault.spendableAmount, afterVault.spendableAmount + amount, "VAULT_AMOUNT");
    }

    function testMintCoupon() public {
        uint256 amount = _usdc.amount(100);
        _lendingPool.deposit(address(_usdc), amount, address(this));
        amount /= 2;

        CouponKey memory couponKey = CouponKey({asset: address(_usdc), epoch: 1});
        uint256 couponId = couponKey.toId();

        Reserve memory beforeReserve = _lendingPool.getReserve(address(_usdc));
        Vault memory beforeVault = _lendingPool.getVault(address(_usdc), address(this));
        uint256 beforeCouponBalance = _lendingPool.balanceOf(_USER1, couponId);
        uint256 beforeCouponTotalSupply = _lendingPool.totalSupply(couponId);

        _lendingPool.mintCoupon(couponKey, amount, _USER1);

        Reserve memory afterReserve = _lendingPool.getReserve(address(_usdc));
        Vault memory afterVault = _lendingPool.getVault(address(_usdc), address(this));
        uint256 afterCouponBalance = _lendingPool.balanceOf(_USER1, couponId);
        uint256 afterCouponTotalSupply = _lendingPool.totalSupply(couponId);

        assertEq(beforeReserve.lockedAmount + amount, afterReserve.lockedAmount, "RESERVE_LOCKED");
        assertEq(beforeReserve.spendableAmount, afterReserve.spendableAmount + amount, "RESERVE_AMOUNT");
        assertEq(beforeVault.lockedAmount + amount, afterVault.lockedAmount, "VAULT_LOCKED");
        assertEq(beforeVault.spendableAmount, afterVault.spendableAmount + amount, "VAULT_AMOUNT");
        assertEq(beforeCouponBalance + amount, afterCouponBalance, "COUPON_BALANCE");
        assertEq(beforeCouponTotalSupply + amount, afterCouponTotalSupply, "COUPON_TOTAL_SUPPLY");
    }

    function testMintCouponWhenAmountExceedsDepositedAmount() public {
        uint256 amount = _usdc.amount(100);
        _lendingPool.deposit(address(_usdc), amount, address(this));

        CouponKey memory couponKey = CouponKey({asset: address(_usdc), epoch: 1});
        uint256 couponId = couponKey.toId();

        Reserve memory beforeReserve = _lendingPool.getReserve(address(_usdc));
        Vault memory beforeVault = _lendingPool.getVault(address(_usdc), address(this));
        uint256 beforeCouponBalance = _lendingPool.balanceOf(_USER1, couponId);
        uint256 beforeCouponTotalSupply = _lendingPool.totalSupply(couponId);

        _lendingPool.mintCoupon(couponKey, amount * 2, _USER1);

        Reserve memory afterReserve = _lendingPool.getReserve(address(_usdc));
        Vault memory afterVault = _lendingPool.getVault(address(_usdc), address(this));
        uint256 afterCouponBalance = _lendingPool.balanceOf(_USER1, couponId);
        uint256 afterCouponTotalSupply = _lendingPool.totalSupply(couponId);

        assertEq(beforeReserve.lockedAmount + amount, afterReserve.lockedAmount, "RESERVE_LOCKED");
        assertEq(beforeReserve.spendableAmount, afterReserve.spendableAmount + amount, "RESERVE_AMOUNT");
        assertEq(beforeVault.lockedAmount + amount, afterVault.lockedAmount, "VAULT_LOCKED");
        assertEq(beforeVault.spendableAmount, afterVault.spendableAmount + amount, "VAULT_AMOUNT");
        assertEq(beforeCouponBalance + amount, afterCouponBalance, "COUPON_BALANCE");
        assertEq(beforeCouponTotalSupply + amount, afterCouponTotalSupply, "COUPON_TOTAL_SUPPLY");
    }
}
