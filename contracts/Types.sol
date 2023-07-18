// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

library Types {
    type Epoch is uint16;

    struct Bond {
        address asset;
        uint64 nonce;
        Epoch expiredWith;
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

    // liquidationFee = liquidator fee + protocol fee
    // debt = collateral * (1 - liquidationFee)
    struct AssetLoanConfiguration {
        uint32 decimal;
        uint32 liquidationThreshold;
        uint32 liquidationFee;
        uint32 liquidationProtocolFee;
        uint32 liquidationTargetLtv;
    }

    struct CouponKey {
        address asset;
        Epoch epoch;
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
