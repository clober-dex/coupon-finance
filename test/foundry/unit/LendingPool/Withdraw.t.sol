// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Types} from "../../../../contracts/Types.sol";
import {IYieldFarmer} from "../../../../contracts/interfaces/IYieldFarmer.sol";
import {ILendingPoolEvents} from "../../../../contracts/interfaces/ILendingPool.sol";
import {ERC20Utils} from "../../Utils.sol";
import {Constants} from "../Constants.sol";
import {SetUp} from "./SetUp.sol";

contract LendingPoolWithdrawUnitTest is Test, ILendingPoolEvents {
    using ERC20Utils for IERC20;

    SetUp.Result public r;
    uint256 private _snapshotId;

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

        _snapshotId = vm.snapshot();
        vm.expectEmit(true, true, true, true);
        emit Withdraw(address(r.usdc), address(this), Constants.USER1, amount);
        r.lendingPool.withdraw(address(r.usdc), amount, Constants.USER1);

        vm.revertTo(_snapshotId);
        vm.expectCall(
            address(r.yieldFarmer),
            abi.encodeCall(IYieldFarmer.withdraw, (address(r.usdc), amount, Constants.USER1))
        );
        r.lendingPool.withdraw(address(r.usdc), amount, Constants.USER1);

        Types.ReserveStatus memory afterReserve = r.lendingPool.getReserveStatus(address(r.usdc));
        Types.VaultStatus memory afterVault = r.lendingPool.getVaultStatus(
            Types.VaultKey(address(r.usdc), address(this))
        );

        assertEq(beforeReserve.spendableAmount, afterReserve.spendableAmount + amount, "RESERVE_SPENDABLE");
        assertEq(beforeVault.spendableAmount, afterVault.spendableAmount + amount, "VAULT_SPENDABLE");
    }

    function testWithdrawWithUnregisteredToken() public {
        vm.expectRevert("Unregistered asset");
        r.lendingPool.withdraw(address(0x123), 1000, Constants.USER1);
    }

    function testWithdrawNative() public {
        uint256 amount = 100 ether;
        r.lendingPool.deposit(address(r.weth), amount, address(this));

        Types.ReserveStatus memory beforeReserve = r.lendingPool.getReserveStatus(address(r.weth));
        Types.VaultStatus memory beforeVault = r.lendingPool.getVaultStatus(
            Types.VaultKey(address(r.weth), address(this))
        );

        _snapshotId = vm.snapshot();
        vm.expectEmit(true, true, true, true);
        emit Withdraw(address(r.weth), address(this), Constants.USER1, amount);
        r.lendingPool.withdraw(address(0), amount, Constants.USER1);

        vm.revertTo(_snapshotId);
        vm.expectCall(
            address(r.yieldFarmer),
            abi.encodeCall(IYieldFarmer.withdraw, (address(0), amount, Constants.USER1))
        );
        r.lendingPool.withdraw(address(0), amount, Constants.USER1);

        Types.ReserveStatus memory afterReserve = r.lendingPool.getReserveStatus(address(r.weth));
        Types.VaultStatus memory afterVault = r.lendingPool.getVaultStatus(
            Types.VaultKey(address(r.weth), address(this))
        );

        assertEq(beforeReserve.spendableAmount, afterReserve.spendableAmount + amount, "RESERVE_SPENDABLE");
        assertEq(beforeVault.spendableAmount, afterVault.spendableAmount + amount, "VAULT_SPENDABLE");
    }

    function testWithdrawWhenAmountExceedsDepositedAmount() public {
        uint256 amount = r.usdc.amount(100);
        r.lendingPool.deposit(address(r.usdc), amount, address(this));

        vm.expectRevert(stdError.arithmeticError);
        r.lendingPool.withdraw(address(r.usdc), amount * 2, Constants.USER1);
    }
}
