// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {ICouponPool} from "./ICoupon.sol";
import {Types} from "../Types.sol";

interface ILendingPoolEvents {
    event Deposit(address indexed asset, address indexed sender, address indexed user, uint256 amount);
    event Withdraw(address indexed asset, address indexed user, address indexed to, uint256 amount);
    event ConvertToCollateral(
        address indexed collateral,
        address indexed loanAsset,
        address sender,
        address indexed user,
        uint256 amount
    );
}

interface ILendingPool is ILendingPoolEvents, ICouponPool {
    // View Functions //
    function epochDuration() external view returns (uint256);

    function currentEpoch() external view returns (uint256);

    function yieldFarmer() external view returns (address);

    function getReserve(address asset) external view returns (Types.Reserve memory);

    function getReserveLockedAmount(address asset, uint256 epoch) external view returns (uint256);

    function getVault(Types.VaultKey calldata vaultKey) external view returns (Types.Vault memory);

    function getVaultLockedAmount(Types.VaultKey calldata vaultKey, uint256 epoch) external view returns (uint256);

    function getLoan(Types.LoanKey calldata loanKey) external view returns (Types.Loan memory);

    function getLoanLimit(Types.LoanKey calldata loanKey, uint256 epoch) external view returns (uint256);

    function withdrawable(address asset) external view returns (uint256);

    // User Functions //
    function deposit(address asset, uint256 amount, address recipient) external payable;

    function depositWithPermit(
        address asset,
        uint256 amount,
        address recipient,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    // @dev If the amount exceeds the withdrawable balance, it will withdraw the maximum amount.
    function withdraw(address asset, uint256 amount, address recipient) external returns (uint256);

    function mintCoupon(Types.CouponKey calldata couponKey, uint256 amount, address recipient) external;

    function burnCoupon(Types.CouponKey calldata couponKey, uint256 amount, address recipient) external;

    // @dev Pull tokens if the deposited amount is less than the amount specified.
    function convertToCollateral(Types.LoanKey calldata loanKey, uint256 amount) external payable;

    function convertToCollateralWithPermit(
        Types.LoanKey calldata loanKey,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function borrow(Types.CouponKey calldata couponKey, address collateral, uint256 amount, address recipient) external;

    function repay(Types.LoanKey calldata loanKey, uint256 amount) external payable;

    function repayWithPermit(
        Types.LoanKey calldata loanKey,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function liquidate(address collateral, address debt, address user, uint256 maxRepayAmount) external;

    // Admin Functions //
    function openReserve(address asset) external;
}
