// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ILendingPoolEvents, ILendingPool} from "../../../contracts/interfaces/ILendingPool.sol";
import {IWETH9} from "../../../contracts/interfaces/external/IWETH9.sol";
import {IYieldFarmer} from "../../../contracts/interfaces/IYieldFarmer.sol";
import {LendingPool} from "../../../contracts/LendingPool.sol";
import {ERC20Utils} from "../Utils.sol";
import {ForkTestSetUp} from "../ForkTestSetUp.sol";
import {MockYieldFarmer} from "../mocks/MockYieldFarmer.sol";

contract LendingPoolUnitTest is Test, ILendingPoolEvents {
    using ERC20Utils for IERC20;

    address private constant _USDC_WHALE = 0xcEe284F754E854890e311e3280b767F80797180d;
    address private constant _USER = address(0x1);

    IERC20 private _usdc;
    IWETH9 private _weth;
    ILendingPool private _lendingPool;
    MockYieldFarmer private _yieldFarmer;

    function setUp() public {
        ForkTestSetUp forkSetUp = new ForkTestSetUp();
        forkSetUp.fork(17617512);

        _weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        _usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

        _yieldFarmer = new MockYieldFarmer();
        // _lendingPool = new LendingPool();

        vm.prank(_USDC_WHALE);
        _usdc.transfer(address(this), _usdc.amount(1_000_000_000));

        _usdc.approve(address(_lendingPool), type(uint256).max);
        _weth.approve(address(_lendingPool), type(uint256).max);
    }

    function testDeposit() public {
        ILendingPool.Reserve memory beforeReserve = _lendingPool.getReserve(address(_usdc));
        ILendingPool.Vault memory beforeVault = _lendingPool.getVault(_USER, address(_usdc));
        uint256 beforeThisBalance = _usdc.balanceOf(address(this));
        uint256 beforePoolBalance = _usdc.balanceOf(address(_lendingPool));
        uint256 beforeYieldFarmerBalance = _yieldFarmer.totalReservedAmount(address(_usdc));

        uint256 amount = _usdc.amount(100);
        vm.expectEmit(true, true, true, true);
        emit Deposit(address(_usdc), address(this), _USER, amount);
        _lendingPool.deposit(address(_usdc), amount, _USER);

        ILendingPool.Reserve memory afterReserve = _lendingPool.getReserve(address(_usdc));
        ILendingPool.Vault memory afterVault = _lendingPool.getVault(_USER, address(_usdc));

        assertEq(_usdc.balanceOf(address(this)) + amount, beforeThisBalance, "THIS_BALANCE");
        assertEq(_usdc.balanceOf(address(_lendingPool)), beforePoolBalance, "POOL_BALANCE");
        assertEq(
            _yieldFarmer.totalReservedAmount(address(_usdc)),
            beforeYieldFarmerBalance + amount,
            "YIELD_FARMER_BALANCE"
        );
        assertEq(beforeReserve.amount + amount, afterReserve.amount, "RESERVE_AMOUNT");
        assertEq(beforeVault.amount + amount, afterVault.amount, "VAULT_AMOUNT");
    }

    function testWithdraw() public {
        uint256 amount = _usdc.amount(100);
        _lendingPool.deposit(address(_usdc), amount, address(this));

        ILendingPool.Reserve memory beforeReserve = _lendingPool.getReserve(address(_usdc));
        ILendingPool.Vault memory beforeVault = _lendingPool.getVault(address(this), address(_usdc));
        uint256 beforeRecipientBalance = _usdc.balanceOf(_USER);
        uint256 beforePoolBalance = _usdc.balanceOf(address(_lendingPool));
        uint256 beforeYieldFarmerBalance = _yieldFarmer.totalReservedAmount(address(_usdc));

        vm.expectEmit(true, true, true, true);
        emit Withdraw(address(_usdc), address(this), _USER, amount);
        uint256 returnValue = _lendingPool.withdraw(address(_usdc), amount, _USER);
        assertEq(returnValue, amount, "RETURN_VALUE");

        ILendingPool.Reserve memory afterReserve = _lendingPool.getReserve(address(_usdc));
        ILendingPool.Vault memory afterVault = _lendingPool.getVault(address(this), address(_usdc));

        assertEq(_usdc.balanceOf(_USER), beforeRecipientBalance + amount, "THIS_BALANCE");
        assertEq(_usdc.balanceOf(address(_lendingPool)), beforePoolBalance, "POOL_BALANCE");
        assertEq(
            _yieldFarmer.totalReservedAmount(address(_usdc)) + amount,
            beforeYieldFarmerBalance,
            "YIELD_FARMER_BALANCE"
        );
        assertEq(beforeReserve.amount, afterReserve.amount + amount, "RESERVE_AMOUNT");
        assertEq(beforeVault.amount, afterVault.amount + amount, "VAULT_AMOUNT");
    }

    function testWithdrawWhenWithdrawalLimitExists() public {
        uint256 amount = _usdc.amount(100);
        _lendingPool.deposit(address(_usdc), amount, address(this));

        _yieldFarmer.setWithdrawLimit(address(_usdc), amount / 2);
        assertEq(_lendingPool.withdrawable(address(_usdc)), amount / 2, "WITHDRAWABLE");

        ILendingPool.Reserve memory beforeReserve = _lendingPool.getReserve(address(_usdc));
        ILendingPool.Vault memory beforeVault = _lendingPool.getVault(address(this), address(_usdc));
        uint256 beforeRecipientBalance = _usdc.balanceOf(_USER);
        uint256 beforePoolBalance = _usdc.balanceOf(address(_lendingPool));
        uint256 beforeYieldFarmerBalance = _yieldFarmer.totalReservedAmount(address(_usdc));

        vm.expectEmit(true, true, true, true);
        emit Withdraw(address(_usdc), address(this), _USER, amount / 2);
        uint256 returnValue = _lendingPool.withdraw(address(_usdc), amount, _USER);
        assertEq(returnValue, amount / 2, "RETURN_VALUE");

        ILendingPool.Reserve memory afterReserve = _lendingPool.getReserve(address(_usdc));
        ILendingPool.Vault memory afterVault = _lendingPool.getVault(address(this), address(_usdc));

        assertEq(_usdc.balanceOf(_USER), beforeRecipientBalance + amount / 2, "THIS_BALANCE");
        assertEq(_usdc.balanceOf(address(_lendingPool)), beforePoolBalance, "POOL_BALANCE");
        assertEq(
            _yieldFarmer.totalReservedAmount(address(_usdc)) + amount / 2,
            beforeYieldFarmerBalance,
            "YIELD_FARMER_BALANCE"
        );
        assertEq(beforeReserve.amount, afterReserve.amount + amount / 2, "RESERVE_AMOUNT");
        assertEq(beforeVault.amount, afterVault.amount + amount / 2, "VAULT_AMOUNT");
    }

    function testWithdrawWhenAmountExceedsDepositedAmount() public {
        uint256 amount = _usdc.amount(100);
        _lendingPool.deposit(address(_usdc), amount, address(this));

        ILendingPool.Reserve memory beforeReserve = _lendingPool.getReserve(address(_usdc));
        ILendingPool.Vault memory beforeVault = _lendingPool.getVault(address(this), address(_usdc));
        uint256 beforeRecipientBalance = _usdc.balanceOf(_USER);
        uint256 beforePoolBalance = _usdc.balanceOf(address(_lendingPool));
        uint256 beforeYieldFarmerBalance = _yieldFarmer.totalReservedAmount(address(_usdc));

        vm.expectEmit(true, true, true, true);
        emit Withdraw(address(_usdc), address(this), _USER, amount);
        uint256 returnValue = _lendingPool.withdraw(address(_usdc), amount * 2, _USER);
        assertEq(returnValue, amount, "RETURN_VALUE");

        ILendingPool.Reserve memory afterReserve = _lendingPool.getReserve(address(_usdc));
        ILendingPool.Vault memory afterVault = _lendingPool.getVault(address(this), address(_usdc));

        assertEq(_usdc.balanceOf(_USER), beforeRecipientBalance + amount, "THIS_BALANCE");
        assertEq(_usdc.balanceOf(address(_lendingPool)), beforePoolBalance, "POOL_BALANCE");
        assertEq(
            _yieldFarmer.totalReservedAmount(address(_usdc)) + amount,
            beforeYieldFarmerBalance,
            "YIELD_FARMER_BALANCE"
        );
        assertEq(beforeReserve.amount, afterReserve.amount + amount, "RESERVE_AMOUNT");
        assertEq(beforeVault.amount, afterVault.amount + amount, "VAULT_AMOUNT");
    }
}
