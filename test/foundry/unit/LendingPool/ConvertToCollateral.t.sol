// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC2612} from "@openzeppelin/contracts/interfaces/IERC2612.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {Types} from "../../../../contracts/Types.sol";
import {ILendingPoolEvents} from "../../../../contracts/interfaces/ILendingPool.sol";
import {CouponKeyLibrary, LoanKeyLibrary} from "../../../../contracts/libraries/Keys.sol";
import {ERC20Utils} from "../../Utils.sol";
import {Constants} from "../Constants.sol";
import {SetUp} from "./SetUp.sol";

contract LendingPoolConvertToCollateralUnitTest is Test, ILendingPoolEvents, ERC1155Holder {
    using ERC20Utils for IERC20;
    using CouponKeyLibrary for Types.CouponKey;
    using LoanKeyLibrary for Types.LoanKey;

    struct PermitParams {
        uint256 nonce;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    SetUp.Result public r;
    uint256 private _snapshotId;
    PermitParams private _permitParams;

    function setUp() public {
        r = SetUp.run(vm);
    }

    function testConvertToCollateral() public {
        uint256 amount = r.usdc.amount(100);
        r.lendingPool.deposit(address(r.usdc), amount, address(this));

        uint256 additionalAmount = amount / 2;

        Types.LoanKey memory loanKey = Types.LoanKey({
            user: Constants.USER1,
            collateral: address(r.usdc),
            asset: address(r.weth)
        });

        Types.ReserveStatus memory beforeReserve = r.lendingPool.getReserveStatus(address(r.usdc));
        Types.VaultStatus memory beforeSenderVault = r.lendingPool.getVaultStatus(
            Types.VaultKey(address(r.usdc), address(this))
        );
        Types.VaultStatus memory beforeUserVault = r.lendingPool.getVaultStatus(
            Types.VaultKey(address(r.usdc), Constants.USER1)
        );
        Types.LoanStatus memory beforeLoan = r.lendingPool.getLoanStatus(loanKey);
        uint256 beforeSenderBalance = r.usdc.balanceOf(address(this));

        _snapshotId = vm.snapshot();
        // check Deposit event
        vm.expectEmit(true, true, true, true);
        emit Deposit(address(r.usdc), address(this), Constants.USER1, additionalAmount);
        r.lendingPool.convertToCollateral(loanKey, amount + additionalAmount);
        // check ConvertToCollateral event
        vm.revertTo(_snapshotId);
        vm.expectEmit(true, true, true, true);
        emit ConvertToCollateral(loanKey.toId(), address(this), amount + additionalAmount);
        r.lendingPool.convertToCollateral(loanKey, amount + additionalAmount);

        Types.ReserveStatus memory afterReserve = r.lendingPool.getReserveStatus(address(r.usdc));
        Types.VaultStatus memory afterSenderVault = r.lendingPool.getVaultStatus(
            Types.VaultKey(address(r.usdc), address(this))
        );
        Types.VaultStatus memory afterUserVault = r.lendingPool.getVaultStatus(
            Types.VaultKey(address(r.usdc), Constants.USER1)
        );
        Types.LoanStatus memory afterLoan = r.lendingPool.getLoanStatus(loanKey);
        uint256 afterSenderBalance = r.usdc.balanceOf(address(this));

        assertEq(
            beforeReserve.collateralAmount + amount + additionalAmount,
            afterReserve.collateralAmount,
            "RESERVE_COLLATERAL"
        );
        assertEq(beforeReserve.spendableAmount, afterReserve.spendableAmount + amount, "RESERVE_SPENDABLE");
        assertEq(
            beforeSenderVault.spendableAmount,
            afterSenderVault.spendableAmount + amount,
            "SENDER_VAULT_SPENDABLE"
        );
        assertEq(
            beforeUserVault.collateralAmount + amount + additionalAmount,
            afterUserVault.collateralAmount,
            "USER_VAULT_COLLATERAL"
        );
        assertEq(beforeUserVault.spendableAmount, afterUserVault.spendableAmount, "USER_VAULT_SPENDABLE");
        assertEq(
            beforeLoan.collateralAmount + amount + additionalAmount,
            afterLoan.collateralAmount,
            "LOAN_COLLATERAL"
        );
        assertEq(beforeSenderBalance, afterSenderBalance + additionalAmount, "BALANCE");
    }

    function testConvertToCollateralWithUnregisteredToken() public {
        vm.expectRevert("Unregistered asset");
        Types.LoanKey memory loanKey1 = Types.LoanKey({
            user: Constants.USER1,
            collateral: address(0x123),
            asset: address(r.weth)
        });
        r.lendingPool.convertToCollateral(loanKey1, 1000);

        vm.expectRevert("Unregistered asset");
        Types.LoanKey memory loanKey2 = Types.LoanKey({
            user: Constants.USER1,
            collateral: address(r.usdc),
            asset: address(0x123)
        });
        r.lendingPool.convertToCollateral(loanKey2, 1000);
    }

    function testConvertToCollateralWithExtraNativeToken() public {
        uint256 amount = 100 ether;
        r.lendingPool.deposit(address(r.weth), amount, address(this));

        uint256 additionalAmount = amount / 2;
        uint256 nativeAmount = amount / 3;

        Types.LoanKey memory loanKey = Types.LoanKey({
            user: Constants.USER1,
            collateral: address(r.weth),
            asset: address(r.weth)
        });

        Types.ReserveStatus memory beforeReserve = r.lendingPool.getReserveStatus(address(r.weth));
        Types.VaultStatus memory beforeUserVault = r.lendingPool.getVaultStatus(
            Types.VaultKey(address(r.weth), Constants.USER1)
        );
        Types.LoanStatus memory beforeLoan = r.lendingPool.getLoanStatus(loanKey);
        uint256 beforeSenderBalance = r.weth.balanceOf(address(this));
        uint256 beforeSenderNativeBalance = address(this).balance;

        {
            // stack too deep
            _snapshotId = vm.snapshot();
            // check Deposit event
            vm.expectEmit(true, true, true, true);
            emit Deposit(address(r.weth), address(this), Constants.USER1, additionalAmount + nativeAmount);
            r.lendingPool.convertToCollateral{value: nativeAmount}(loanKey, amount + additionalAmount);
            // check ConvertToCollateral event
            vm.revertTo(_snapshotId);
            vm.expectEmit(true, true, true, true);
            emit ConvertToCollateral(loanKey.toId(), address(this), amount + additionalAmount + nativeAmount);
            r.lendingPool.convertToCollateral{value: nativeAmount}(loanKey, amount + additionalAmount);
        }

        Types.ReserveStatus memory afterReserve = r.lendingPool.getReserveStatus(address(r.weth));
        Types.VaultStatus memory afterSenderVault = r.lendingPool.getVaultStatus(
            Types.VaultKey(address(r.weth), address(this))
        );
        Types.VaultStatus memory afterUserVault = r.lendingPool.getVaultStatus(
            Types.VaultKey(address(r.weth), Constants.USER1)
        );
        Types.LoanStatus memory afterLoan = r.lendingPool.getLoanStatus(loanKey);

        assertEq(
            beforeReserve.collateralAmount + amount + additionalAmount + nativeAmount,
            afterReserve.collateralAmount,
            "RESERVE_COLLATERAL"
        );
        assertEq(beforeReserve.spendableAmount, afterReserve.spendableAmount + amount, "RESERVE_SPENDABLE");
        assertEq(afterSenderVault.spendableAmount, 0, "SENDER_VAULT_SPENDABLE");
        assertEq(
            beforeUserVault.collateralAmount + amount + additionalAmount + nativeAmount,
            afterUserVault.collateralAmount,
            "USER_VAULT_COLLATERAL"
        );
        assertEq(
            beforeLoan.collateralAmount + amount + additionalAmount + nativeAmount,
            afterLoan.collateralAmount,
            "LOAN_COLLATERAL"
        );
        assertEq(beforeSenderBalance, r.weth.balanceOf(address(this)) + additionalAmount, "BALANCE");
        assertEq(beforeSenderNativeBalance, address(this).balance + nativeAmount, "NATIVE_BALANCE");
    }

    function testConvertToCollateralWithPermit() public {
        uint256 amount = r.usdc.amount(100);
        uint256 additionalAmount = amount / 2;

        r.usdc.transfer(r.permitUser, amount + additionalAmount);
        vm.startPrank(r.permitUser);
        r.lendingPool.deposit(address(r.usdc), amount, r.permitUser);

        Types.LoanKey memory loanKey = Types.LoanKey({
            user: Constants.USER1,
            collateral: address(r.usdc),
            asset: address(r.weth)
        });

        Types.ReserveStatus memory beforeReserve = r.lendingPool.getReserveStatus(address(r.usdc));
        Types.VaultStatus memory beforeSenderVault = r.lendingPool.getVaultStatus(
            Types.VaultKey(address(r.usdc), r.permitUser)
        );
        Types.VaultStatus memory beforeUserVault = r.lendingPool.getVaultStatus(
            Types.VaultKey(address(r.usdc), Constants.USER1)
        );
        Types.LoanStatus memory beforeLoan = r.lendingPool.getLoanStatus(loanKey);
        uint256 beforeSenderBalance = r.usdc.balanceOf(r.permitUser);

        _permitParams.nonce = IERC2612(address(r.usdc)).nonces(r.permitUser);
        {
            bytes32 digest = keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    IERC2612(address(r.usdc)).DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            Constants.PERMIT_TYPEHASH,
                            r.permitUser,
                            address(r.lendingPool),
                            additionalAmount,
                            _permitParams.nonce,
                            type(uint256).max
                        )
                    )
                )
            );
            (_permitParams.v, _permitParams.r, _permitParams.s) = vm.sign(1, digest);

            _snapshotId = vm.snapshot();
            // check Deposit event
            vm.expectEmit(true, true, true, true);
            emit Deposit(address(r.usdc), r.permitUser, Constants.USER1, additionalAmount);
            r.lendingPool.convertToCollateralWithPermit(
                loanKey,
                amount + additionalAmount,
                type(uint256).max,
                _permitParams.v,
                _permitParams.r,
                _permitParams.s
            );
            // check ConvertToCollateral event
            vm.revertTo(_snapshotId);
            vm.expectEmit(true, true, true, true);
            emit ConvertToCollateral(loanKey.toId(), r.permitUser, amount + additionalAmount);
            r.lendingPool.convertToCollateralWithPermit(
                loanKey,
                amount + additionalAmount,
                type(uint256).max,
                _permitParams.v,
                _permitParams.r,
                _permitParams.s
            );
        }

        Types.ReserveStatus memory afterReserve = r.lendingPool.getReserveStatus(address(r.usdc));
        Types.VaultStatus memory afterSenderVault = r.lendingPool.getVaultStatus(
            Types.VaultKey(address(r.usdc), r.permitUser)
        );
        Types.VaultStatus memory afterUserVault = r.lendingPool.getVaultStatus(
            Types.VaultKey(address(r.usdc), Constants.USER1)
        );
        Types.LoanStatus memory afterLoan = r.lendingPool.getLoanStatus(loanKey);
        uint256 afterSenderBalance = r.usdc.balanceOf(r.permitUser);

        assertEq(
            beforeReserve.collateralAmount + amount + additionalAmount,
            afterReserve.collateralAmount,
            "RESERVE_COLLATERAL"
        );
        assertEq(beforeReserve.spendableAmount, afterReserve.spendableAmount + amount, "RESERVE_SPENDABLE");
        assertEq(
            beforeSenderVault.spendableAmount,
            afterSenderVault.spendableAmount + amount,
            "SENDER_VAULT_SPENDABLE"
        );
        assertEq(
            beforeUserVault.collateralAmount + amount + additionalAmount,
            afterUserVault.collateralAmount,
            "USER_VAULT_COLLATERAL"
        );
        assertEq(beforeUserVault.spendableAmount, afterUserVault.spendableAmount, "USER_VAULT_SPENDABLE");
        assertEq(
            beforeLoan.collateralAmount,
            afterLoan.collateralAmount + amount + additionalAmount,
            "LOAN_COLLATERAL"
        );
        assertEq(beforeSenderBalance, afterSenderBalance + additionalAmount, "BALANCE");
        assertEq(IERC2612(address(r.usdc)).nonces(r.permitUser), _permitParams.nonce + 1, "NONCE");

        vm.stopPrank();
    }
}
