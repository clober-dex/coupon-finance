// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC2612} from "@openzeppelin/contracts/interfaces/IERC2612.sol";

import {Types} from "../../../../contracts/Types.sol";
import {ILendingPoolEvents} from "../../../../contracts/interfaces/ILendingPool.sol";
import {ERC20Utils} from "../../Utils.sol";
import {Constants} from "../Constants.sol";
import {SetUp} from "./SetUp.sol";

contract LendingPoolDepositUnitTest is Test, ILendingPoolEvents {
    using ERC20Utils for IERC20;

    struct PermitParams {
        uint256 nonce;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    SetUp.Result public r;
    PermitParams private _permitParams;

    function setUp() public {
        r = SetUp.run(vm);
    }

    function testDeposit() public {
        Types.ReserveStatus memory beforeReserve = r.lendingPool.getReserveStatus(address(r.usdc));
        Types.VaultStatus memory beforeVault = r.lendingPool.getVaultStatus(
            Types.VaultKey(address(r.usdc), Constants.USER1)
        );
        uint256 beforeThisBalance = r.usdc.balanceOf(address(this));
        uint256 beforeYieldFarmerBalance = r.yieldFarmer.totalReservedAmount(address(r.usdc));

        uint256 amount = r.usdc.amount(100);
        vm.expectEmit(true, true, true, true);
        emit Deposit(address(r.usdc), address(this), Constants.USER1, amount);
        r.lendingPool.deposit(address(r.usdc), amount, Constants.USER1);

        Types.ReserveStatus memory afterReserve = r.lendingPool.getReserveStatus(address(r.usdc));
        Types.VaultStatus memory afterVault = r.lendingPool.getVaultStatus(
            Types.VaultKey(address(r.usdc), Constants.USER1)
        );

        assertEq(r.usdc.balanceOf(address(this)) + amount, beforeThisBalance, "THIS_BALANCE");
        assertEq(
            r.yieldFarmer.totalReservedAmount(address(r.usdc)),
            beforeYieldFarmerBalance + amount,
            "YIELD_FARMER_BALANCE"
        );
        assertEq(beforeReserve.spendableAmount + amount, afterReserve.spendableAmount, "RESERVE_SPENDABLE");
        assertEq(beforeVault.spendableAmount + amount, afterVault.spendableAmount, "VAULT_SPENDABLE");
    }

    function testDepositWithUnregisteredToken() public {
        vm.expectRevert("Unregistered token");
        r.lendingPool.deposit(address(0x123), 1000, Constants.USER1);
    }

    function testDepositNative() public {
        Types.ReserveStatus memory beforeReserve = r.lendingPool.getReserveStatus(address(r.weth));
        Types.VaultStatus memory beforeVault = r.lendingPool.getVaultStatus(
            Types.VaultKey(address(r.weth), Constants.USER1)
        );
        uint256 beforeThisNativeBalance = address(this).balance;
        uint256 beforeThisBalance = r.weth.balanceOf(address(this));
        uint256 beforeYieldFarmerBalance = r.yieldFarmer.totalReservedAmount(address(r.weth));

        uint256 amount1 = 100 ether;
        uint256 amount2 = 50 ether;
        vm.expectEmit(true, true, true, true);
        emit Deposit(address(r.weth), address(this), Constants.USER1, amount1 + amount2);
        r.lendingPool.deposit{value: amount1}(address(r.weth), amount2, Constants.USER1);

        Types.ReserveStatus memory afterReserve = r.lendingPool.getReserveStatus(address(r.weth));
        Types.VaultStatus memory afterVault = r.lendingPool.getVaultStatus(
            Types.VaultKey(address(r.weth), Constants.USER1)
        );

        assertEq(address(this).balance + amount1, beforeThisNativeBalance, "THIS_NATIVE_BALANCE");
        assertEq(r.weth.balanceOf(address(this)) + amount2, beforeThisBalance, "THIS_BALANCE");
        assertEq(
            r.yieldFarmer.totalReservedAmount(address(r.weth)),
            beforeYieldFarmerBalance + amount1 + amount2,
            "YIELD_FARMER_BALANCE"
        );
        assertEq(beforeReserve.spendableAmount + amount1 + amount2, afterReserve.spendableAmount, "RESERVE_SPENDABLE");
        assertEq(beforeVault.spendableAmount + amount1 + amount2, afterVault.spendableAmount, "VAULT_SPENDABLE");
    }

    function testDepositWithPermit() public {
        IERC2612 permitToken = IERC2612(address(r.usdc));
        uint256 amount = r.usdc.amount(100);
        r.usdc.transfer(r.permitUser, amount);
        vm.startPrank(r.permitUser);

        Types.ReserveStatus memory beforeReserve = r.lendingPool.getReserveStatus(address(r.usdc));
        Types.VaultStatus memory beforeVault = r.lendingPool.getVaultStatus(
            Types.VaultKey(address(r.usdc), Constants.USER1)
        );
        uint256 beforeSenderBalance = r.usdc.balanceOf(r.permitUser);
        uint256 beforeYieldFarmerBalance = r.yieldFarmer.totalReservedAmount(address(r.usdc));

        _permitParams.nonce = permitToken.nonces(r.permitUser);
        {
            bytes32 digest = keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    permitToken.DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            Constants.PERMIT_TYPEHASH,
                            r.permitUser,
                            address(r.lendingPool),
                            amount,
                            _permitParams.nonce,
                            type(uint256).max
                        )
                    )
                )
            );
            (_permitParams.v, _permitParams.r, _permitParams.s) = vm.sign(1, digest);

            vm.expectEmit(true, true, true, true);
            emit Deposit(address(r.usdc), r.permitUser, Constants.USER1, amount);
            r.lendingPool.depositWithPermit(
                address(r.usdc),
                amount,
                Constants.USER1,
                type(uint256).max,
                _permitParams.v,
                _permitParams.r,
                _permitParams.s
            );
        }

        Types.ReserveStatus memory afterReserve = r.lendingPool.getReserveStatus(address(r.usdc));
        Types.VaultStatus memory afterVault = r.lendingPool.getVaultStatus(
            Types.VaultKey(address(r.usdc), Constants.USER1)
        );

        assertEq(r.usdc.balanceOf(r.permitUser) + amount, beforeSenderBalance, "SENDER_BALANCE");
        assertEq(
            r.yieldFarmer.totalReservedAmount(address(r.usdc)),
            beforeYieldFarmerBalance + amount,
            "YIELD_FARMER_BALANCE"
        );
        assertEq(beforeReserve.spendableAmount + amount, afterReserve.spendableAmount, "RESERVE_SPENDABLE");
        assertEq(beforeVault.spendableAmount + amount, afterVault.spendableAmount, "VAULT_SPENDABLE");
        assertEq(permitToken.nonces(r.permitUser), _permitParams.nonce + 1, "NONCE");

        vm.stopPrank();
    }
}
