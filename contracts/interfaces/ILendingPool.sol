// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {ICouponPool} from "./ICoupon.sol";

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

interface ILendingPoolTypes {
    struct CouponKey {
        address asset;
        uint256 epoch;
    }

    // totalAmount = spendableAmount + lockedAmount + collateralAmount
    struct Reserve {
        uint256 spendableAmount;
        uint256 lockedAmount;
        uint256 collateralAmount;
    }

    struct VaultKey {
        address user;
        address asset;
    }

    // totalAmount = spendableAmount + lockedAmount + collateralAmount
    struct Vault {
        uint256 spendableAmount;
        uint256 lockedAmount;
        uint256 collateralAmount;
    }

    struct LoanKey {
        address user;
        address collateral;
        address asset;
    }

    struct Loan {
        uint256 amount;
        uint256 collateralAmount;
    }
}

interface ILendingPool is ILendingPoolEvents, ILendingPoolTypes, ICouponPool {
    // View Functions //
    function epochDuration() external view returns (uint256);

    function currentEpoch() external view returns (uint256);

    function yieldFarmer() external view returns (address);

    function getReserve(address asset) external view returns (Reserve memory);

    function getVault(address asset, address user) external view returns (Vault memory);

    function getLoan(LoanKey calldata loanKey) external view returns (Loan memory);

    function getLoanLimit(LoanKey calldata loanKey, uint256 epoch) external view returns (uint256);

    function withdrawable(address asset) external view returns (uint256);

    // User Functions //
    function deposit(address asset, uint256 amount, address recipient) external payable;

    // @dev If the amount exceeds the withdrawable balance, it will withdraw the maximum amount.
    function withdraw(address asset, uint256 amount, address recipient) external returns (uint256);

    function mintCoupon(CouponKey calldata couponKey, uint256 amount, address recipient) external;

    function burnCoupon(CouponKey calldata couponKey, uint256 amount, address recipient) external;

    // @dev Pull tokens if the deposited amount is less than the amount specified.
    function convertToCollateral(LoanKey calldata loanKey, uint256 amount) external payable;

    function borrow(CouponKey calldata couponKey, address collateral, uint256 amount, address recipient) external;

    function repay(address asset, uint256 amount, address recipient) external;

    function liquidate(address collateral, address debt, address user, uint256 maxRepayAmount) external;

    // Admin Functions //
    function openReserve(address asset) external;
}
