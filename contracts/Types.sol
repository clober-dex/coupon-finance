// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

library Types {
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
        address asset;
        address user;
    }

    type VaultId is bytes32;

    // totalAmount = spendableAmount + lockedAmount + collateralAmount
    struct Vault {
        uint256 spendableAmount;
        uint256 lockedAmount;
        uint256 collateralAmount;
    }

    struct LoanKey {
        address collateral;
        address asset;
        address user;
    }

    type LoanId is bytes32;

    struct Loan {
        uint256 amount;
        uint256 collateralAmount;
    }
}
