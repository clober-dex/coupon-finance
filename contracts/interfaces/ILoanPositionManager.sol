// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

import {IERC721Permit} from "./IERC721Permit.sol";
import {CouponKey} from "../libraries/CouponKey.sol";
import {Epoch} from "../libraries/Epoch.sol";
import {LoanPosition} from "../libraries/LoanPosition.sol";

interface ILoanPositionManagerTypes {
    struct LiquidationStatus {
        uint256 liquidationAmount;
        uint256 repayAmount;
        uint256 protocolFeeAmount;
    }

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
    event PositionUpdated(uint256 indexed tokenId, uint256 collateralAmount, uint256 debtAmount, Epoch unlockedAt);
    event PositionLiquidated(uint256 indexed tokenId);

    error EmptyInput();
    error InvalidEpoch();
    error TooSmallDebt();
    error InvalidAccess();
    error UnpaidDebt();
    error LiquidationThreshold();
    error InvalidPair();
    error UnableToLiquidate();
}

interface ILoanPositionManager is IERC721Metadata, IERC721Permit, ILoanPositionManagerTypes {
    function baseURI() external view returns (string memory);

    function treasury() external view returns (address);

    function oracle() external view returns (address);

    function nextId() external view returns (uint256);

    function couponManager() external view returns (address);

    function assetPool() external view returns (address);

    function minDebtValueInEth() external view returns (uint256);

    function getPosition(uint256 tokenId) external view returns (LoanPosition memory);

    function isPairRegistered(address collateral, address debt) external view returns (bool);

    function getLoanConfiguration(address collateral, address debt) external view returns (LoanConfiguration memory);

    function getOwedCouponAmount(address user, uint256 couponId) external view returns (uint256);

    function getLiquidationStatus(uint256 tokenId, uint256 maxRepayAmount)
        external
        view
        returns (LiquidationStatus memory);

    function mint(
        address collateralToken,
        address debtToken,
        uint256 collateralAmount,
        uint256 debtAmount,
        uint16 loanEpochs,
        address recipient,
        bytes calldata data
    ) external returns (uint256);

    function adjustPosition(
        uint256 tokenId,
        uint256 collateralAmount,
        uint256 debtAmount,
        Epoch expiredWith,
        bytes calldata data
    ) external;

    function liquidate(uint256 tokenId, uint256 maxRepayAmount, bytes calldata data) external;

    function claimOwedCoupons(CouponKey[] memory couponKeys, bytes calldata data) external;

    function burn(uint256 tokenId) external;

    function setLoanConfiguration(
        address collateral,
        address debt,
        uint32 liquidationThreshold,
        uint32 liquidationFee,
        uint32 liquidationProtocolFee,
        uint32 liquidationTargetLtv
    ) external;
}
