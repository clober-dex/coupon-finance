// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

library Types {
    /// NEW TYPES=== ///
    struct Bond {
        uint256 nonce;
        address asset;
        uint256 unlockedAt;
        uint256 amount;
    }
    struct Loan {
        uint256 nonce;
        address collateralToken;
        address debtToken;
        uint256 collateralAmount;
        uint256 debtAmount;
        uint256 expiredAt;
    }
    struct LoanConfiguration {
        uint32 decimal;
        uint32 liquidationThreshold;
        uint32 liquidationBonus;
        uint32 liquidationProtocolFee;
        uint32 liquidationTargetLtv;
    }
    /// ===NEW TYPES ///

    struct CouponKey {
        address asset;
        uint256 epoch;
    }

    struct Coupon {
        CouponKey key;
        uint256 amount;
    }

    // totalAmount = spendableAmount + lockedAmount + collateralAmount
    struct ReserveStatus {
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
    struct VaultStatus {
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

    struct LoanStatus {
        uint256 amount;
        uint256 collateralAmount;
        uint256 limit;
    }

    struct LiquidationStatus {
        bool available;
        uint256 liquidationAmount;
    }

    struct AssetConfiguration {
        uint32 decimal;
        uint32 liquidationThreshold;
        uint32 liquidationBonus;
        uint32 liquidationProtocolFee;
        uint32 liquidationTargetLtv;
    }

    struct PermitParams {
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }
}
