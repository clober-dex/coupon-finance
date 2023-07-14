// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

library Types {
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

    struct AssetLoanConfiguration {
        uint32 decimal;
        uint32 liquidationThreshold;
        uint32 liquidationFee;
        uint32 liquidationProtocolFee;
        uint32 liquidationTargetLtv;
    }

    struct CouponKey {
        address asset;
        uint256 epoch;
    }

    struct Coupon {
        CouponKey key;
        uint256 amount;
    }

    struct LiquidationStatus {
        bool available;
        uint256 liquidationAmount;
        uint256 repayAmount;
    }

    struct PermitParams {
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }
}
