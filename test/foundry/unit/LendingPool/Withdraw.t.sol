// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Types} from "../../../../contracts/Types.sol";
import {ILendingPoolEvents} from "../../../../contracts/interfaces/ILendingPool.sol";
import {ERC20Utils} from "../../Utils.sol";
import {Constants} from "../Constants.sol";
import {SetUp} from "./SetUp.sol";

contract LendingPoolDepositUnitTest is Test, ILendingPoolEvents {
    using ERC20Utils for IERC20;

    SetUp.Result public r;

    receive() external payable {}

    function setUp() public {
        r = SetUp.run(vm);
    }

    function testWithdraw() public {
        uint256 amount = r.usdc.amount(100);
        r.lendingPool.deposit(address(r.usdc), amount, address(this));

        Types.ReserveStatus memory beforeReserve = r.lendingPool.getReserveStatus(address(r.usdc));
        Types.VaultStatus memory beforeVault = r.lendingPool.getVaultStatus(
            Types.VaultKey(address(r.usdc), address(this))
        );
        uint256 beforeRecipientBalance = r.usdc.balanceOf(Constants.USER1);
        uint256 beforePoolBalance = r.usdc.balanceOf(address(r.lendingPool));
        uint256 beforeYieldFarmerBalance = r.yieldFarmer.totalReservedAmount(address(r.usdc));

        vm.expectEmit(true, true, true, true);
        emit Withdraw(address(r.usdc), address(this), Constants.USER1, amount);
        uint256 returnValue = r.lendingPool.withdraw(address(r.usdc), amount, Constants.USER1);
        assertEq(returnValue, amount, "RETURN_VALUE");

        Types.ReserveStatus memory afterReserve = r.lendingPool.getReserveStatus(address(r.usdc));
        Types.VaultStatus memory afterVault = r.lendingPool.getVaultStatus(
            Types.VaultKey(address(r.usdc), address(this))
        );

        assertEq(r.usdc.balanceOf(Constants.USER1), beforeRecipientBalance + amount, "THIS_BALANCE");
        assertEq(r.usdc.balanceOf(address(r.lendingPool)), beforePoolBalance, "POOL_BALANCE");
        assertEq(
            r.yieldFarmer.totalReservedAmount(address(r.usdc)) + amount,
            beforeYieldFarmerBalance,
            "YIELD_FARMER_BALANCE"
        );
        assertEq(beforeReserve.spendableAmount, afterReserve.spendableAmount + amount, "RESERVE_SPENDABLE");
        assertEq(beforeVault.spendableAmount, afterVault.spendableAmount + amount, "VAULT_SPENDABLE");
    }

    function testWithdrawNative() public {
        uint256 amount = 100 ether;
        r.lendingPool.deposit(address(r.weth), amount, address(this));

        Types.ReserveStatus memory beforeReserve = r.lendingPool.getReserveStatus(address(r.weth));
        Types.VaultStatus memory beforeVault = r.lendingPool.getVaultStatus(
            Types.VaultKey(address(r.weth), address(this))
        );
        uint256 beforeRecipientNativeBalance = Constants.USER1.balance;
        uint256 beforeYieldFarmerBalance = r.yieldFarmer.totalReservedAmount(address(r.weth));

        vm.expectEmit(true, true, true, true);
        emit Withdraw(address(r.weth), address(this), Constants.USER1, amount);
        uint256 returnValue = r.lendingPool.withdraw(address(0), amount, Constants.USER1);
        assertEq(returnValue, amount, "RETURN_VALUE");

        Types.ReserveStatus memory afterReserve = r.lendingPool.getReserveStatus(address(r.weth));
        Types.VaultStatus memory afterVault = r.lendingPool.getVaultStatus(
            Types.VaultKey(address(r.weth), address(this))
        );

        assertEq(Constants.USER1.balance, beforeRecipientNativeBalance + amount, "THIS_NATIVE_BALANCE");
        assertEq(
            r.yieldFarmer.totalReservedAmount(address(r.weth)) + amount,
            beforeYieldFarmerBalance,
            "YIELD_FARMER_BALANCE"
        );
        assertEq(beforeReserve.spendableAmount, afterReserve.spendableAmount + amount, "RESERVE_SPENDABLE");
        assertEq(beforeVault.spendableAmount, afterVault.spendableAmount + amount, "VAULT_SPENDABLE");
    }

    function testWithdrawWhenWithdrawalLimitExists() public {
        uint256 amount = r.usdc.amount(100);
        r.lendingPool.deposit(address(r.usdc), amount, address(this));

        r.yieldFarmer.setWithdrawLimit(address(r.usdc), amount / 2);
        assertEq(r.lendingPool.withdrawable(address(r.usdc)), amount / 2, "WITHDRAWABLE");

        Types.ReserveStatus memory beforeReserve = r.lendingPool.getReserveStatus(address(r.usdc));
        Types.VaultStatus memory beforeVault = r.lendingPool.getVaultStatus(
            Types.VaultKey(address(r.usdc), address(this))
        );
        uint256 beforeRecipientBalance = r.usdc.balanceOf(Constants.USER1);
        uint256 beforePoolBalance = r.usdc.balanceOf(address(r.lendingPool));
        uint256 beforeYieldFarmerBalance = r.yieldFarmer.totalReservedAmount(address(r.usdc));

        vm.expectEmit(true, true, true, true);
        emit Withdraw(address(r.usdc), address(this), Constants.USER1, amount / 2);
        uint256 returnValue = r.lendingPool.withdraw(address(r.usdc), amount, Constants.USER1);
        assertEq(returnValue, amount / 2, "RETURN_VALUE");

        Types.ReserveStatus memory afterReserve = r.lendingPool.getReserveStatus(address(r.usdc));
        Types.VaultStatus memory afterVault = r.lendingPool.getVaultStatus(
            Types.VaultKey(address(r.usdc), address(this))
        );

        assertEq(r.usdc.balanceOf(Constants.USER1), beforeRecipientBalance + amount / 2, "THIS_BALANCE");
        assertEq(r.usdc.balanceOf(address(r.lendingPool)), beforePoolBalance, "POOL_BALANCE");
        assertEq(
            r.yieldFarmer.totalReservedAmount(address(r.usdc)) + amount / 2,
            beforeYieldFarmerBalance,
            "YIELD_FARMER_BALANCE"
        );
        assertEq(beforeReserve.spendableAmount, afterReserve.spendableAmount + amount / 2, "RESERVE_SPENDABLE");
        assertEq(beforeVault.spendableAmount, afterVault.spendableAmount + amount / 2, "VAULT_SPENDABLE");
    }

    function testWithdrawWhenAmountExceedsDepositedAmount() public {
        uint256 amount = r.usdc.amount(100);
        r.lendingPool.deposit(address(r.usdc), amount, address(this));

        Types.ReserveStatus memory beforeReserve = r.lendingPool.getReserveStatus(address(r.usdc));
        Types.VaultStatus memory beforeVault = r.lendingPool.getVaultStatus(
            Types.VaultKey(address(r.usdc), address(this))
        );
        uint256 beforeRecipientBalance = r.usdc.balanceOf(Constants.USER1);
        uint256 beforePoolBalance = r.usdc.balanceOf(address(r.lendingPool));
        uint256 beforeYieldFarmerBalance = r.yieldFarmer.totalReservedAmount(address(r.usdc));

        vm.expectEmit(true, true, true, true);
        emit Withdraw(address(r.usdc), address(this), Constants.USER1, amount);
        uint256 returnValue = r.lendingPool.withdraw(address(r.usdc), amount * 2, Constants.USER1);
        assertEq(returnValue, amount, "RETURN_VALUE");

        Types.ReserveStatus memory afterReserve = r.lendingPool.getReserveStatus(address(r.usdc));
        Types.VaultStatus memory afterVault = r.lendingPool.getVaultStatus(
            Types.VaultKey(address(r.usdc), address(this))
        );

        assertEq(r.usdc.balanceOf(Constants.USER1), beforeRecipientBalance + amount, "THIS_BALANCE");
        assertEq(r.usdc.balanceOf(address(r.lendingPool)), beforePoolBalance, "POOL_BALANCE");
        assertEq(
            r.yieldFarmer.totalReservedAmount(address(r.usdc)) + amount,
            beforeYieldFarmerBalance,
            "YIELD_FARMER_BALANCE"
        );
        assertEq(beforeReserve.spendableAmount, afterReserve.spendableAmount + amount, "RESERVE_SPENDABLE");
        assertEq(beforeVault.spendableAmount, afterVault.spendableAmount + amount, "VAULT_SPENDABLE");
    }
}
