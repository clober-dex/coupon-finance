// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {ICoupon} from "./ICoupon.sol";
import {Types} from "../Types.sol";

interface ILendingPoolEvents {
    event Deposit(address indexed asset, address indexed sender, address indexed user, uint256 amount);
    event Withdraw(address indexed asset, address indexed user, address indexed to, uint256 amount);
    event ConvertToCollateral(Types.LoanId indexed loanId, address indexed sender, uint256 amount);
    event LoanLimitChanged(Types.LoanId indexed loanId, uint256 indexed epoch, uint256 limit);
    event Borrow(Types.LoanId indexed loanId, address indexed to, uint256 amount);
    event Repay(Types.LoanId indexed loanId, address indexed sender, uint256 amount);
    event RegisterAsset(address indexed asset, Types.AssetConfiguration config);
}

interface ILendingPool is ILendingPoolEvents, ICoupon {
    // View Functions //
    function baseURI() external view returns (string memory);

    function oracle() external view returns (address);

    function treasury() external view returns (address);

    function startedAt() external view returns (uint256);

    function maxEpoch() external view returns (uint256);

    function epochDuration() external view returns (uint256);

    function currentEpoch() external view returns (uint256);

    function yieldFarmer() external view returns (address);

    function isAssetRegistered(address asset) external view returns (bool);

    function getAssetConfiguration(address asset) external view returns (Types.AssetConfiguration memory);

    function getReserveStatus(address asset) external view returns (Types.ReserveStatus memory);

    function getReserveLockedAmount(address asset, uint256 epoch) external view returns (uint256);

    function getVaultStatus(Types.VaultKey calldata vaultKey) external view returns (Types.VaultStatus memory);

    function getVaultLockedAmount(Types.VaultKey calldata vaultKey, uint256 epoch) external view returns (uint256);

    function getLoanStatus(Types.LoanKey calldata loanKey) external view returns (Types.LoanStatus memory);

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
    function withdraw(address asset, uint256 amount, address recipient) external;

    function mintCoupons(Types.Coupon[] calldata coupons, address recipient) external;

    function burnCoupons(Types.Coupon[] calldata coupons, address recipient) external;

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

    function borrow(Types.Coupon[] calldata coupons, address collateral, address recipient) external;

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
    function registerAsset(address asset, Types.AssetConfiguration calldata config) external;

    function setTreasury(address newTreasury) external;
}
