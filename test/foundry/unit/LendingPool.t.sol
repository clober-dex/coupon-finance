// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC2612} from "@openzeppelin/contracts/interfaces/IERC2612.sol";

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

    bytes32 private constant _PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
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
        Vault memory beforeVault = _lendingPool.getVault(VaultKey(address(_usdc), _USER1));
        uint256 beforeThisBalance = _usdc.balanceOf(address(this));
        uint256 beforeYieldFarmerBalance = _yieldFarmer.totalReservedAmount(address(_usdc));

        uint256 amount = _usdc.amount(100);
        vm.expectEmit(true, true, true, true);
        emit Deposit(address(_usdc), address(this), _USER1, amount);
        _lendingPool.deposit(address(_usdc), amount, _USER1);

        Reserve memory afterReserve = _lendingPool.getReserve(address(_usdc));
        Vault memory afterVault = _lendingPool.getVault(VaultKey(address(_usdc), _USER1));

        assertEq(_usdc.balanceOf(address(this)) + amount, beforeThisBalance, "THIS_BALANCE");
        assertEq(
            _yieldFarmer.totalReservedAmount(address(_usdc)),
            beforeYieldFarmerBalance + amount,
            "YIELD_FARMER_BALANCE"
        );
        assertEq(beforeReserve.spendableAmount + amount, afterReserve.spendableAmount, "RESERVE_SPENDABLE");
        assertEq(beforeVault.spendableAmount + amount, afterVault.spendableAmount, "VAULT_SPENDABLE");
    }

    function testDepositNative() public {
        Reserve memory beforeReserve = _lendingPool.getReserve(address(_weth));
        Vault memory beforeVault = _lendingPool.getVault(VaultKey(address(_weth), _USER1));
        uint256 beforeThisNativeBalance = address(this).balance;
        uint256 beforeThisBalance = _weth.balanceOf(address(this));
        uint256 beforeYieldFarmerBalance = _yieldFarmer.totalReservedAmount(address(_weth));

        uint256 amount1 = 100 ether;
        uint256 amount2 = 50 ether;
        vm.expectEmit(true, true, true, true);
        emit Deposit(address(_weth), address(this), _USER1, amount1 + amount2);
        _lendingPool.deposit{value: amount1}(address(_weth), amount2, _USER1);

        Reserve memory afterReserve = _lendingPool.getReserve(address(_weth));
        Vault memory afterVault = _lendingPool.getVault(VaultKey(address(_weth), _USER1));

        assertEq(address(this).balance + amount1, beforeThisNativeBalance, "THIS_NATIVE_BALANCE");
        assertEq(_weth.balanceOf(address(this)) + amount2, beforeThisBalance, "THIS_BALANCE");
        assertEq(
            _yieldFarmer.totalReservedAmount(address(_weth)),
            beforeYieldFarmerBalance + amount1 + amount2,
            "YIELD_FARMER_BALANCE"
        );
        assertEq(beforeReserve.spendableAmount + amount1 + amount2, afterReserve.spendableAmount, "RESERVE_SPENDABLE");
        assertEq(beforeVault.spendableAmount + amount1 + amount2, afterVault.spendableAmount, "VAULT_SPENDABLE");
    }

    function testDepositWithPermit() public {
        IERC2612 permitToken = IERC2612(address(_usdc));
        address unapprovedUser = vm.addr(1);
        uint256 amount = _usdc.amount(100);
        _usdc.transfer(unapprovedUser, amount);
        vm.startPrank(unapprovedUser);

        Reserve memory beforeReserve = _lendingPool.getReserve(address(_usdc));
        Vault memory beforeVault = _lendingPool.getVault(VaultKey(address(_usdc), _USER1));
        uint256 beforeSenderBalance = _usdc.balanceOf(unapprovedUser);
        uint256 beforeYieldFarmerBalance = _yieldFarmer.totalReservedAmount(address(_usdc));

        uint256 nonce = permitToken.nonces(unapprovedUser);
        {
            uint256 deadline = type(uint256).max;
            bytes32 digest = keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    permitToken.DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(_PERMIT_TYPEHASH, unapprovedUser, address(_lendingPool), amount, nonce, deadline)
                    )
                )
            );
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, digest);

            vm.expectEmit(true, true, true, true);
            emit Deposit(address(_usdc), unapprovedUser, _USER1, amount);
            _lendingPool.depositWithPermit(address(_usdc), amount, _USER1, deadline, v, r, s);
        }

        Reserve memory afterReserve = _lendingPool.getReserve(address(_usdc));
        Vault memory afterVault = _lendingPool.getVault(VaultKey(address(_usdc), _USER1));

        assertEq(_usdc.balanceOf(unapprovedUser) + amount, beforeSenderBalance, "SENDER_BALANCE");
        assertEq(
            _yieldFarmer.totalReservedAmount(address(_usdc)),
            beforeYieldFarmerBalance + amount,
            "YIELD_FARMER_BALANCE"
        );
        assertEq(beforeReserve.spendableAmount + amount, afterReserve.spendableAmount, "RESERVE_SPENDABLE");
        assertEq(beforeVault.spendableAmount + amount, afterVault.spendableAmount, "VAULT_SPENDABLE");
        assertEq(permitToken.nonces(unapprovedUser), nonce + 1, "NONCE");

        vm.stopPrank();
    }

    function testWithdraw() public {
        uint256 amount = _usdc.amount(100);
        _lendingPool.deposit(address(_usdc), amount, address(this));

        Reserve memory beforeReserve = _lendingPool.getReserve(address(_usdc));
        Vault memory beforeVault = _lendingPool.getVault(VaultKey(address(_usdc), address(this)));
        uint256 beforeRecipientBalance = _usdc.balanceOf(_USER1);
        uint256 beforePoolBalance = _usdc.balanceOf(address(_lendingPool));
        uint256 beforeYieldFarmerBalance = _yieldFarmer.totalReservedAmount(address(_usdc));

        vm.expectEmit(true, true, true, true);
        emit Withdraw(address(_usdc), address(this), _USER1, amount);
        uint256 returnValue = _lendingPool.withdraw(address(_usdc), amount, _USER1);
        assertEq(returnValue, amount, "RETURN_VALUE");

        Reserve memory afterReserve = _lendingPool.getReserve(address(_usdc));
        Vault memory afterVault = _lendingPool.getVault(VaultKey(address(_usdc), address(this)));

        assertEq(_usdc.balanceOf(_USER1), beforeRecipientBalance + amount, "THIS_BALANCE");
        assertEq(_usdc.balanceOf(address(_lendingPool)), beforePoolBalance, "POOL_BALANCE");
        assertEq(
            _yieldFarmer.totalReservedAmount(address(_usdc)) + amount,
            beforeYieldFarmerBalance,
            "YIELD_FARMER_BALANCE"
        );
        assertEq(beforeReserve.spendableAmount, afterReserve.spendableAmount + amount, "RESERVE_SPENDABLE");
        assertEq(beforeVault.spendableAmount, afterVault.spendableAmount + amount, "VAULT_SPENDABLE");
    }

    function testWithdrawNative() public {
        uint256 amount = 100 ether;
        _lendingPool.deposit(address(_weth), amount, address(this));

        Reserve memory beforeReserve = _lendingPool.getReserve(address(_weth));
        Vault memory beforeVault = _lendingPool.getVault(VaultKey(address(_weth), address(this)));
        uint256 beforeRecipientNativeBalance = _USER1.balance;
        uint256 beforeYieldFarmerBalance = _yieldFarmer.totalReservedAmount(address(_weth));

        vm.expectEmit(true, true, true, true);
        emit Withdraw(address(_weth), address(this), _USER1, amount);
        uint256 returnValue = _lendingPool.withdraw(address(0), amount, _USER1);
        assertEq(returnValue, amount, "RETURN_VALUE");

        Reserve memory afterReserve = _lendingPool.getReserve(address(_weth));
        Vault memory afterVault = _lendingPool.getVault(VaultKey(address(_weth), address(this)));

        assertEq(_USER1.balance, beforeRecipientNativeBalance + amount, "THIS_NATIVE_BALANCE");
        assertEq(
            _yieldFarmer.totalReservedAmount(address(_weth)) + amount,
            beforeYieldFarmerBalance,
            "YIELD_FARMER_BALANCE"
        );
        assertEq(beforeReserve.spendableAmount, afterReserve.spendableAmount + amount, "RESERVE_SPENDABLE");
        assertEq(beforeVault.spendableAmount, afterVault.spendableAmount + amount, "VAULT_SPENDABLE");
    }

    function testWithdrawWhenWithdrawalLimitExists() public {
        uint256 amount = _usdc.amount(100);
        _lendingPool.deposit(address(_usdc), amount, address(this));

        _yieldFarmer.setWithdrawLimit(address(_usdc), amount / 2);
        assertEq(_lendingPool.withdrawable(address(_usdc)), amount / 2, "WITHDRAWABLE");

        Reserve memory beforeReserve = _lendingPool.getReserve(address(_usdc));
        Vault memory beforeVault = _lendingPool.getVault(VaultKey(address(_usdc), address(this)));
        uint256 beforeRecipientBalance = _usdc.balanceOf(_USER1);
        uint256 beforePoolBalance = _usdc.balanceOf(address(_lendingPool));
        uint256 beforeYieldFarmerBalance = _yieldFarmer.totalReservedAmount(address(_usdc));

        vm.expectEmit(true, true, true, true);
        emit Withdraw(address(_usdc), address(this), _USER1, amount / 2);
        uint256 returnValue = _lendingPool.withdraw(address(_usdc), amount, _USER1);
        assertEq(returnValue, amount / 2, "RETURN_VALUE");

        Reserve memory afterReserve = _lendingPool.getReserve(address(_usdc));
        Vault memory afterVault = _lendingPool.getVault(VaultKey(address(_usdc), address(this)));

        assertEq(_usdc.balanceOf(_USER1), beforeRecipientBalance + amount / 2, "THIS_BALANCE");
        assertEq(_usdc.balanceOf(address(_lendingPool)), beforePoolBalance, "POOL_BALANCE");
        assertEq(
            _yieldFarmer.totalReservedAmount(address(_usdc)) + amount / 2,
            beforeYieldFarmerBalance,
            "YIELD_FARMER_BALANCE"
        );
        assertEq(beforeReserve.spendableAmount, afterReserve.spendableAmount + amount / 2, "RESERVE_SPENDABLE");
        assertEq(beforeVault.spendableAmount, afterVault.spendableAmount + amount / 2, "VAULT_SPENDABLE");
    }

    function testWithdrawWhenAmountExceedsDepositedAmount() public {
        uint256 amount = _usdc.amount(100);
        _lendingPool.deposit(address(_usdc), amount, address(this));

        Reserve memory beforeReserve = _lendingPool.getReserve(address(_usdc));
        Vault memory beforeVault = _lendingPool.getVault(VaultKey(address(_usdc), address(this)));
        uint256 beforeRecipientBalance = _usdc.balanceOf(_USER1);
        uint256 beforePoolBalance = _usdc.balanceOf(address(_lendingPool));
        uint256 beforeYieldFarmerBalance = _yieldFarmer.totalReservedAmount(address(_usdc));

        vm.expectEmit(true, true, true, true);
        emit Withdraw(address(_usdc), address(this), _USER1, amount);
        uint256 returnValue = _lendingPool.withdraw(address(_usdc), amount * 2, _USER1);
        assertEq(returnValue, amount, "RETURN_VALUE");

        Reserve memory afterReserve = _lendingPool.getReserve(address(_usdc));
        Vault memory afterVault = _lendingPool.getVault(VaultKey(address(_usdc), address(this)));

        assertEq(_usdc.balanceOf(_USER1), beforeRecipientBalance + amount, "THIS_BALANCE");
        assertEq(_usdc.balanceOf(address(_lendingPool)), beforePoolBalance, "POOL_BALANCE");
        assertEq(
            _yieldFarmer.totalReservedAmount(address(_usdc)) + amount,
            beforeYieldFarmerBalance,
            "YIELD_FARMER_BALANCE"
        );
        assertEq(beforeReserve.spendableAmount, afterReserve.spendableAmount + amount, "RESERVE_SPENDABLE");
        assertEq(beforeVault.spendableAmount, afterVault.spendableAmount + amount, "VAULT_SPENDABLE");
    }

    function testMintCoupon() public {
        uint256 amount = _usdc.amount(100);
        _lendingPool.deposit(address(_usdc), amount, address(this));
        amount /= 2;

        CouponKey memory couponKey = CouponKey({asset: address(_usdc), epoch: 1});
        uint256 couponId = couponKey.toId();

        Reserve memory beforeReserve = _lendingPool.getReserve(address(_usdc));
        Vault memory beforeVault = _lendingPool.getVault(VaultKey(address(_usdc), address(this)));
        uint256 beforeCouponBalance = _lendingPool.balanceOf(_USER1, couponId);
        uint256 beforeCouponTotalSupply = _lendingPool.totalSupply(couponId);

        _lendingPool.mintCoupon(couponKey, amount, _USER1);

        Reserve memory afterReserve = _lendingPool.getReserve(address(_usdc));
        Vault memory afterVault = _lendingPool.getVault(VaultKey(address(_usdc), address(this)));
        uint256 afterCouponBalance = _lendingPool.balanceOf(_USER1, couponId);
        uint256 afterCouponTotalSupply = _lendingPool.totalSupply(couponId);

        assertEq(beforeReserve.lockedAmount + amount, afterReserve.lockedAmount, "RESERVE_LOCKED");
        assertEq(beforeReserve.spendableAmount, afterReserve.spendableAmount + amount, "RESERVE_SPENDABLE");
        assertEq(beforeVault.lockedAmount + amount, afterVault.lockedAmount, "VAULT_LOCKED");
        assertEq(beforeVault.spendableAmount, afterVault.spendableAmount + amount, "VAULT_SPENDABLE");
        assertEq(beforeCouponBalance + amount, afterCouponBalance, "COUPON_BALANCE");
        assertEq(beforeCouponTotalSupply + amount, afterCouponTotalSupply, "COUPON_TOTAL_SUPPLY");
    }

    function testMintCouponWhenAmountExceedsDepositedAmount() public {
        uint256 amount = _usdc.amount(100);
        _lendingPool.deposit(address(_usdc), amount, address(this));

        CouponKey memory couponKey = CouponKey({asset: address(_usdc), epoch: 1});
        uint256 couponId = couponKey.toId();

        Reserve memory beforeReserve = _lendingPool.getReserve(address(_usdc));
        Vault memory beforeVault = _lendingPool.getVault(VaultKey(address(_usdc), address(this)));
        uint256 beforeCouponBalance = _lendingPool.balanceOf(_USER1, couponId);
        uint256 beforeCouponTotalSupply = _lendingPool.totalSupply(couponId);

        _lendingPool.mintCoupon(couponKey, amount * 2, _USER1);

        Reserve memory afterReserve = _lendingPool.getReserve(address(_usdc));
        Vault memory afterVault = _lendingPool.getVault(VaultKey(address(_usdc), address(this)));
        uint256 afterCouponBalance = _lendingPool.balanceOf(_USER1, couponId);
        uint256 afterCouponTotalSupply = _lendingPool.totalSupply(couponId);

        assertEq(beforeReserve.lockedAmount + amount, afterReserve.lockedAmount, "RESERVE_LOCKED");
        assertEq(beforeReserve.spendableAmount, afterReserve.spendableAmount + amount, "RESERVE_SPENDABLE");
        assertEq(beforeVault.lockedAmount + amount, afterVault.lockedAmount, "VAULT_LOCKED");
        assertEq(beforeVault.spendableAmount, afterVault.spendableAmount + amount, "VAULT_SPENDABLE");
        assertEq(beforeCouponBalance + amount, afterCouponBalance, "COUPON_BALANCE");
        assertEq(beforeCouponTotalSupply + amount, afterCouponTotalSupply, "COUPON_TOTAL_SUPPLY");
    }

    function testLockedAmountChanges() public {
        uint256 amount0 = _usdc.amount(50);
        uint256 amount1 = _usdc.amount(70);
        uint256 amount2 = _usdc.amount(100);
        _lendingPool.deposit(address(_usdc), amount0 + amount1 + amount2, address(this));

        CouponKey memory couponKey1 = CouponKey({asset: address(_usdc), epoch: 1});
        CouponKey memory couponKey2 = CouponKey({asset: address(_usdc), epoch: 2});

        _lendingPool.mintCoupon(couponKey1, amount1, address(this));
        _lendingPool.mintCoupon(couponKey2, amount2, address(this));

        // epoch 1
        Reserve memory reserve = _lendingPool.getReserve(address(_usdc));
        Vault memory vault = _lendingPool.getVault(VaultKey(address(_usdc), address(this)));
        assertEq(reserve.lockedAmount, amount1 + amount2, "RESERVE_LOCKED");
        assertEq(reserve.spendableAmount, amount0, "RESERVE_SPENDABLE");
        assertEq(vault.lockedAmount, amount1 + amount2, "VAULT_LOCKED");
        assertEq(vault.spendableAmount, amount0, "VAULT_SPENDABLE");

        vm.warp(block.timestamp + _lendingPool.epochDuration());

        // epoch 2
        reserve = _lendingPool.getReserve(address(_usdc));
        vault = _lendingPool.getVault(VaultKey(address(_usdc), address(this)));
        assertEq(reserve.lockedAmount, amount2, "RESERVE_LOCKED");
        assertEq(reserve.spendableAmount, amount0 + amount1, "RESERVE_SPENDABLE");
        assertEq(vault.lockedAmount, amount2, "VAULT_LOCKED");
        assertEq(vault.spendableAmount, amount0 + amount1, "VAULT_SPENDABLE");

        vm.warp(block.timestamp + _lendingPool.epochDuration());

        // epoch 3
        reserve = _lendingPool.getReserve(address(_usdc));
        vault = _lendingPool.getVault(VaultKey(address(_usdc), address(this)));
        assertEq(reserve.lockedAmount, 0, "RESERVE_LOCKED");
        assertEq(reserve.spendableAmount, amount0 + amount1 + amount2, "RESERVE_SPENDABLE");
        assertEq(vault.lockedAmount, 0, "VAULT_LOCKED");
        assertEq(vault.spendableAmount, amount0 + amount1 + amount2, "VAULT_SPENDABLE");

        assertEq(_lendingPool.getReserveLockedAmount(address(_usdc), 1), amount1 + amount2, "RESERVE_LOCKED_1");
        assertEq(_lendingPool.getReserveLockedAmount(address(_usdc), 2), amount2, "RESERVE_LOCKED_2");
        assertEq(_lendingPool.getReserveLockedAmount(address(_usdc), 3), 0, "RESERVE_LOCKED_3");
        assertEq(
            _lendingPool.getVaultLockedAmount(VaultKey(address(_usdc), address(this)), 1),
            amount1 + amount2,
            "VAULT_LOCKED_1"
        );
        assertEq(
            _lendingPool.getVaultLockedAmount(VaultKey(address(_usdc), address(this)), 2),
            amount2,
            "VAULT_LOCKED_2"
        );
        assertEq(_lendingPool.getVaultLockedAmount(VaultKey(address(_usdc), address(this)), 3), 0, "VAULT_LOCKED_3");
    }

    function testBurnCoupon() public {
        uint256 amount = _usdc.amount(100);
        _lendingPool.deposit(address(_usdc), amount, address(this));

        CouponKey memory couponKey = CouponKey({asset: address(_usdc), epoch: 1});
        uint256 couponId = couponKey.toId();
        _lendingPool.mintCoupon(couponKey, amount, _USER1);

        uint256 burnAmount = amount / 3;
        Reserve memory beforeReserve = _lendingPool.getReserve(address(_usdc));
        Vault memory beforeVault = _lendingPool.getVault(VaultKey(address(_usdc), address(this)));
        uint256 beforeCouponBalance = _lendingPool.balanceOf(_USER1, couponId);
        uint256 beforeCouponTotalSupply = _lendingPool.totalSupply(couponId);

        vm.prank(_USER1);
        _lendingPool.burnCoupon(couponKey, burnAmount, address(this));

        Reserve memory afterReserve = _lendingPool.getReserve(address(_usdc));
        Vault memory afterVault = _lendingPool.getVault(VaultKey(address(_usdc), address(this)));
        uint256 afterCouponBalance = _lendingPool.balanceOf(_USER1, couponId);
        uint256 afterCouponTotalSupply = _lendingPool.totalSupply(couponId);

        assertEq(beforeReserve.lockedAmount, afterReserve.lockedAmount + burnAmount, "RESERVE_LOCKED");
        assertEq(beforeReserve.spendableAmount + burnAmount, afterReserve.spendableAmount, "RESERVE_SPENDABLE");
        assertEq(beforeVault.lockedAmount, afterVault.lockedAmount + burnAmount, "VAULT_LOCKED");
        assertEq(beforeVault.spendableAmount + burnAmount, afterVault.spendableAmount, "VAULT_SPENDABLE");
        assertEq(beforeCouponBalance, afterCouponBalance + burnAmount, "COUPON_BALANCE");
        assertEq(beforeCouponTotalSupply, afterCouponTotalSupply + burnAmount, "COUPON_TOTAL_SUPPLY");
    }

    function testBurnCouponWhenTheAmountExceedsLockedAmount() public {
        uint256 amount = _usdc.amount(100);
        _lendingPool.deposit(address(_usdc), amount, address(this));

        CouponKey memory couponKey = CouponKey({asset: address(_usdc), epoch: 1});
        uint256 couponId = couponKey.toId();
        _lendingPool.mintCoupon(couponKey, amount, _USER1);

        uint256 burnAmount = amount / 3;
        _lendingPool.deposit(address(_usdc), burnAmount - 1, _USER1);
        vm.prank(_USER1);
        _lendingPool.mintCoupon(couponKey, burnAmount - 1, _USER2);

        Reserve memory beforeReserve = _lendingPool.getReserve(address(_usdc));
        Vault memory beforeVault = _lendingPool.getVault(VaultKey(address(_usdc), address(this)));
        uint256 beforeCouponBalance = _lendingPool.balanceOf(_USER1, couponId);
        uint256 beforeCouponTotalSupply = _lendingPool.totalSupply(couponId);

        vm.prank(_USER1);
        _lendingPool.burnCoupon(couponKey, burnAmount, _USER1);

        Reserve memory afterReserve = _lendingPool.getReserve(address(_usdc));
        Vault memory afterVault = _lendingPool.getVault(VaultKey(address(_usdc), _USER1));
        uint256 afterCouponBalance = _lendingPool.balanceOf(_USER1, couponId);
        uint256 afterCouponTotalSupply = _lendingPool.totalSupply(couponId);

        assertEq(beforeReserve.lockedAmount, afterReserve.lockedAmount + burnAmount - 1, "RESERVE_LOCKED");
        assertEq(beforeReserve.spendableAmount + burnAmount - 1, afterReserve.spendableAmount, "RESERVE_SPENDABLE");
        assertEq(afterVault.lockedAmount, 0, "VAULT_LOCKED");
        assertEq(beforeVault.spendableAmount + burnAmount - 1, afterVault.spendableAmount, "VAULT_SPENDABLE");
        assertEq(beforeCouponBalance, afterCouponBalance + burnAmount - 1, "COUPON_BALANCE");
        assertEq(beforeCouponTotalSupply, afterCouponTotalSupply + burnAmount - 1, "COUPON_TOTAL_SUPPLY");
    }

    function testBurnCouponWithExpiredCoupon() public {
        uint256 amount = _usdc.amount(100);
        _lendingPool.deposit(address(_usdc), amount, address(this));

        CouponKey memory couponKey = CouponKey({asset: address(_usdc), epoch: 1});
        uint256 couponId = couponKey.toId();
        _lendingPool.mintCoupon(couponKey, amount, _USER1);

        uint256 couponBalance = _lendingPool.balanceOf(_USER1, couponId);
        vm.prank(_USER1);
        _lendingPool.burnCoupon(couponKey, amount, _USER1);
        assertEq(_lendingPool.balanceOf(_USER1, couponId), couponBalance, "COUPON_BALANCE_0");

        vm.warp(block.timestamp + _lendingPool.epochDuration());

        vm.prank(_USER1);
        _lendingPool.burnCoupon(couponKey, amount / 2, _USER1);
        assertEq(_lendingPool.balanceOf(_USER1, couponId), amount / 2, "COUPON_BALANCE_1");

        assertEq(_lendingPool.getReserveLockedAmount(address(_usdc), 1), amount, "RESERVE_LOCKED_0");
        assertEq(
            _lendingPool.getVaultLockedAmount(VaultKey(address(_usdc), address(this)), 1),
            amount,
            "VAULT_LOCKED_0"
        );
        _lendingPool.burnCoupon(couponKey, amount / 2, address(this));
        // expect no change
        assertEq(_lendingPool.getReserveLockedAmount(address(_usdc), 1), amount, "RESERVE_LOCKED_1");
        assertEq(
            _lendingPool.getVaultLockedAmount(VaultKey(address(_usdc), address(this)), 1),
            amount,
            "VAULT_LOCKED_1"
        );
    }

    function testConvertToCollateral() public {
        uint256 amount = _usdc.amount(100);
        _lendingPool.deposit(address(_usdc), amount, address(this));

        uint256 additionalAmount = amount / 2;

        Reserve memory beforeReserve = _lendingPool.getReserve(address(_usdc));
        Vault memory beforeSenderVault = _lendingPool.getVault(VaultKey(address(_usdc), address(this)));
        Vault memory beforeUserVault = _lendingPool.getVault(VaultKey(address(_usdc), _USER1));
        uint256 beforeSenderBalance = _usdc.balanceOf(address(this));

        LoanKey memory loanKey = LoanKey({user: _USER1, collateral: address(_usdc), asset: address(_weth)});
        uint256 snapshotId = vm.snapshot();
        // check Deposit event
        vm.expectEmit(true, true, true, true);
        emit Deposit(address(_usdc), address(this), _USER1, additionalAmount);
        _lendingPool.convertToCollateral(loanKey, amount + additionalAmount);
        // check ConvertToCollateral event
        vm.revertTo(snapshotId);
        vm.expectEmit(true, true, true, true);
        emit ConvertToCollateral(
            loanKey.collateral,
            loanKey.asset,
            address(this),
            loanKey.user,
            amount + additionalAmount
        );
        _lendingPool.convertToCollateral(loanKey, amount + additionalAmount);

        Reserve memory afterReserve = _lendingPool.getReserve(address(_usdc));
        Vault memory afterSenderVault = _lendingPool.getVault(VaultKey(address(_usdc), address(this)));
        Vault memory afterUserVault = _lendingPool.getVault(VaultKey(address(_usdc), _USER1));
        uint256 afterSenderBalance = _usdc.balanceOf(address(this));

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
        assertEq(beforeSenderBalance, afterSenderBalance + additionalAmount, "BALANCE");
    }

    function testConvertToCollateralWithExtraNativeToken() public {
        uint256 amount = 100 ether;
        _lendingPool.deposit(address(_weth), amount, address(this));

        uint256 additionalAmount = amount / 2;
        uint256 nativeAmount = amount / 3;

        Reserve memory beforeReserve = _lendingPool.getReserve(address(_weth));
        Vault memory beforeUserVault = _lendingPool.getVault(VaultKey(address(_weth), _USER1));
        uint256 beforeSenderBalance = _weth.balanceOf(address(this));
        uint256 beforeSenderNativeBalance = address(this).balance;

        {
            // stack too deep

            LoanKey memory loanKey = LoanKey({user: _USER1, collateral: address(_weth), asset: address(_weth)});
            uint256 snapshotId = vm.snapshot();
            // check Deposit event
            vm.expectEmit(true, true, true, true);
            emit Deposit(address(_weth), address(this), _USER1, additionalAmount + nativeAmount);
            _lendingPool.convertToCollateral{value: nativeAmount}(loanKey, amount + additionalAmount + nativeAmount);
            // check ConvertToCollateral event
            vm.revertTo(snapshotId);
            vm.expectEmit(true, true, true, true);
            emit ConvertToCollateral(
                loanKey.collateral,
                loanKey.asset,
                address(this),
                loanKey.user,
                amount + additionalAmount + nativeAmount
            );
            _lendingPool.convertToCollateral{value: nativeAmount}(loanKey, amount + additionalAmount + nativeAmount);
        }

        Reserve memory afterReserve = _lendingPool.getReserve(address(_weth));
        Vault memory afterSenderVault = _lendingPool.getVault(VaultKey(address(_weth), address(this)));
        Vault memory afterUserVault = _lendingPool.getVault(VaultKey(address(_weth), _USER1));
        uint256 afterSenderBalance = _weth.balanceOf(address(this));
        uint256 afterSenderNativeBalance = address(this).balance;

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
        assertEq(beforeSenderBalance, afterSenderBalance + additionalAmount, "BALANCE");
        assertEq(beforeSenderNativeBalance, afterSenderNativeBalance + nativeAmount, "NATIVE_BALANCE");
    }

    function testConvertToCollateralShouldUseNativeTokenFirst() public {
        uint256 amount = 100 ether;
        _lendingPool.deposit(address(_weth), amount, address(this));

        uint256 nativeAmount = 50 ether;

        Reserve memory beforeReserve = _lendingPool.getReserve(address(_weth));
        Vault memory beforeSenderVault = _lendingPool.getVault(VaultKey(address(_weth), address(this)));
        Vault memory beforeUserVault = _lendingPool.getVault(VaultKey(address(_weth), _USER1));
        uint256 beforeSenderBalance = _weth.balanceOf(address(this));
        uint256 beforeSenderNativeBalance = address(this).balance;

        LoanKey memory loanKey = LoanKey({user: _USER1, collateral: address(_weth), asset: address(_weth)});
        uint256 snapshotId = vm.snapshot();
        // check Deposit event
        vm.expectEmit(true, true, true, true);
        emit Deposit(address(_weth), address(this), _USER1, nativeAmount);
        _lendingPool.convertToCollateral{value: nativeAmount}(loanKey, nativeAmount);
        // check ConvertToCollateral event
        vm.revertTo(snapshotId);
        vm.expectEmit(true, true, true, true);
        emit ConvertToCollateral(loanKey.collateral, loanKey.asset, address(this), loanKey.user, nativeAmount);
        _lendingPool.convertToCollateral{value: nativeAmount}(loanKey, nativeAmount);

        Reserve memory afterReserve = _lendingPool.getReserve(address(_weth));
        Vault memory afterSenderVault = _lendingPool.getVault(VaultKey(address(_weth), address(this)));
        Vault memory afterUserVault = _lendingPool.getVault(VaultKey(address(_weth), _USER1));
        uint256 afterSenderBalance = _weth.balanceOf(address(this));
        uint256 afterSenderNativeBalance = address(this).balance;

        assertEq(beforeReserve.collateralAmount + nativeAmount, afterReserve.collateralAmount, "RESERVE_COLLATERAL");
        assertEq(beforeReserve.spendableAmount, afterReserve.spendableAmount, "RESERVE_SPENDABLE");
        assertEq(beforeSenderVault.spendableAmount, afterSenderVault.spendableAmount, "SENDER_VAULT_SPENDABLE");
        assertEq(
            beforeUserVault.collateralAmount + nativeAmount,
            afterUserVault.collateralAmount,
            "USER_VAULT_COLLATERAL"
        );
        assertEq(beforeSenderBalance, afterSenderBalance, "BALANCE");
        assertEq(beforeSenderNativeBalance, afterSenderNativeBalance + nativeAmount, "NATIVE_BALANCE");
    }

    function testConvertToCollateralShouldReturnExceededNativeToken() public {
        uint256 amount = 100 ether;
        _lendingPool.deposit(address(_weth), amount, address(this));

        uint256 nativeAmount = 50 ether;

        Reserve memory beforeReserve = _lendingPool.getReserve(address(_weth));
        Vault memory beforeSenderVault = _lendingPool.getVault(VaultKey(address(_weth), address(this)));
        Vault memory beforeUserVault = _lendingPool.getVault(VaultKey(address(_weth), _USER1));
        uint256 beforeSenderBalance = _weth.balanceOf(address(this));
        uint256 beforeSenderNativeBalance = address(this).balance;
        uint256 beforePoolNativeBalance = address(_lendingPool).balance;
        {
            // stack too deep
            LoanKey memory loanKey = LoanKey({user: _USER1, collateral: address(_weth), asset: address(_weth)});
            uint256 snapshotId = vm.snapshot();
            // check Deposit event
            vm.expectEmit(true, true, true, true);
            emit Deposit(address(_weth), address(this), _USER1, nativeAmount / 2);
            _lendingPool.convertToCollateral{value: nativeAmount}(loanKey, nativeAmount / 2);
            // check ConvertToCollateral event
            vm.revertTo(snapshotId);
            vm.expectEmit(true, true, true, true);
            emit ConvertToCollateral(loanKey.collateral, loanKey.asset, address(this), loanKey.user, nativeAmount / 2);
            _lendingPool.convertToCollateral{value: nativeAmount}(loanKey, nativeAmount / 2);
        }

        Reserve memory afterReserve = _lendingPool.getReserve(address(_weth));
        Vault memory afterSenderVault = _lendingPool.getVault(VaultKey(address(_weth), address(this)));
        Vault memory afterUserVault = _lendingPool.getVault(VaultKey(address(_weth), _USER1));
        uint256 afterSenderBalance = _weth.balanceOf(address(this));
        uint256 afterSenderNativeBalance = address(this).balance;
        uint256 afterPoolNativeBalance = address(_lendingPool).balance;

        assertEq(
            beforeReserve.collateralAmount + nativeAmount / 2,
            afterReserve.collateralAmount,
            "RESERVE_COLLATERAL"
        );
        assertEq(beforeReserve.spendableAmount, afterReserve.spendableAmount, "RESERVE_SPENDABLE");
        assertEq(beforeSenderVault.spendableAmount, afterSenderVault.spendableAmount, "SENDER_VAULT_SPENDABLE");
        assertEq(
            beforeUserVault.collateralAmount + nativeAmount / 2,
            afterUserVault.collateralAmount,
            "USER_VAULT_COLLATERAL"
        );
        assertEq(beforeSenderBalance, afterSenderBalance, "BALANCE");
        assertEq(beforeSenderNativeBalance, afterSenderNativeBalance + nativeAmount / 2, "NATIVE_BALANCE");
        assertEq(beforePoolNativeBalance, afterPoolNativeBalance, "POOL_NATIVE_BALANCE");
    }
}
