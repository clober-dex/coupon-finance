// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IPositionManagerTypes, IPositionManager} from "./IPositionManager.sol";
import {CouponKey} from "../libraries/CouponKey.sol";
import {Coupon} from "../libraries/Coupon.sol";
import {Epoch} from "../libraries/Epoch.sol";
import {LoanPosition} from "../libraries/LoanPosition.sol";

interface ILoanPositionManagerTypes is IPositionManagerTypes {
    // liquidationFee = liquidator fee + protocol fee
    // debt = collateral * (1 - liquidationFee)
    struct LoanConfiguration {
        uint32 collateralDecimal;
        uint32 debtDecimal;
        uint32 liquidationThreshold;
        uint32 liquidationFee;
        uint32 liquidationProtocolFee;
        uint32 liquidationTargetLtv;
    }

    event AssetRegistered(address indexed asset);
    event PositionUpdated(uint256 indexed positionId, uint256 collateralAmount, uint256 debtAmount, Epoch unlockedAt);
    // todo: should give more information
    event PositionLiquidated(uint256 indexed positionId);

    error AlreadyExpired();
    error TooSmallDebt();
    error InvalidAccess();
    error UnpaidDebt();
    error LiquidationThreshold();
    error InvalidPair();
    error UnableToLiquidate();
}

interface ILoanPositionManager is ILoanPositionManagerTypes, IPositionManager {
    function treasury() external view returns (address);

    function oracle() external view returns (address);

    function minDebtValueInEth() external view returns (uint256);

    function getPosition(uint256 positionId) external view returns (LoanPosition memory);

    function isPairRegistered(address collateral, address debt) external view returns (bool);

    function getLoanConfiguration(address collateral, address debt) external view returns (LoanConfiguration memory);

    function getOwedCouponAmount(address user, uint256 couponId) external view returns (uint256);

    function getLiquidationStatus(uint256 positionId, uint256 maxRepayAmount)
        external
        view
        returns (uint256 liquidationAmount, uint256 repayAmount, uint256 protocolFeeAmount);

    function mint(address collateralToken, address debtToken) external returns (uint256 positionId);

    function adjustPosition(uint256 positionId, uint256 collateralAmount, uint256 debtAmount, Epoch expiredWith)
        external
        returns (
            Coupon[] memory couponsToPay,
            Coupon[] memory couponsToRefund,
            int256 collateralDelta,
            int256 debtDelta
        );

    function liquidate(uint256 positionId, uint256 maxRepayAmount)
        external
        returns (uint256 liquidationAmount, uint256 repayAmount, uint256 protocolFeeAmount);

    function claimOwedCoupons(CouponKey[] memory couponKeys, bytes calldata data) external;

    function setLoanConfiguration(
        address collateral,
        address debt,
        uint32 liquidationThreshold,
        uint32 liquidationFee,
        uint32 liquidationProtocolFee,
        uint32 liquidationTargetLtv
    ) external;
}
