// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {ERC721Permit} from "./libraries/ERC721Permit.sol";
import {ReentrancyGuard} from "./libraries/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Types} from "./Types.sol";
import {ILoanPosition} from "./interfaces/ILoanPosition.sol";
import {IAssetPool} from "./interfaces/IAssetPool.sol";
import {ILiquidateCallbackReceiver} from "./interfaces/ILiquidateCallbackReceiver.sol";
import {ICouponOracle} from "./interfaces/ICouponOracle.sol";
import {Coupon} from "./libraries/Coupon.sol";
import {Epoch} from "./libraries/Epoch.sol";
import {ICouponManager} from "./interfaces/ICouponManager.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract LoanPosition is ILoanPosition, ERC721Permit, Ownable {
    using SafeERC20 for IERC20;
    using Coupon for Types.Coupon;
    using Epoch for Types.Epoch;

    uint256 private constant _RATE_PRECISION = 10 ** 6;

    address public immutable override coupon;
    address public immutable override assetPool;
    address public immutable override oracle;
    address public immutable override treasury;
    uint256 public immutable override minDebtValueInEth;

    string public override baseURI;
    uint256 public override nextId = 1;

    mapping(address user => mapping(uint256 couponId => uint256)) public override couponOwed;
    mapping(address asset => Types.AssetLoanConfiguration) private _assetConfig;
    mapping(uint256 id => Types.Loan) private _loanMap;

    constructor(
        address coupon_,
        address assetPool_,
        address oracle_,
        address treasury_,
        uint256 minDebtValueInEth_,
        string memory baseURI_
    ) ERC721Permit("Loan Position", "LP", "1") {
        coupon = coupon_;
        assetPool = assetPool_;
        oracle = oracle_;
        baseURI = baseURI_;
        treasury = treasury_;
        minDebtValueInEth = minDebtValueInEth_;
    }

    function loans(uint256 tokenId) external view returns (Types.Loan memory) {
        return _loanMap[tokenId];
    }

    function isAssetRegistered(address asset) external view returns (bool) {
        return _assetConfig[asset].liquidationThreshold > 0;
    }

    function getLoanConfiguration(address asset) external view returns (Types.AssetLoanConfiguration memory) {
        return _assetConfig[asset];
    }

    function setLoanConfiguration(address asset, Types.AssetLoanConfiguration memory config) external onlyOwner {
        require(_assetConfig[asset].liquidationThreshold == 0, "INITIALIZED");
        config.decimal = IERC20Metadata(asset).decimals();
        _assetConfig[asset] = config;
    }

    function _getAssetConfig(
        address asset,
        address collateral
    )
        private
        view
        returns (
            uint256 liquidationThreshold,
            uint256 liquidationFee,
            uint256 liquidationProtocolFee,
            uint256 liquidationTargetLtv
        )
    {
        Types.AssetLoanConfiguration memory debtAssetConfig = _assetConfig[asset];
        Types.AssetLoanConfiguration memory collateralAssetConfig = _assetConfig[collateral];

        if (collateralAssetConfig.liquidationThreshold == 0)
            return (
                debtAssetConfig.liquidationFee,
                debtAssetConfig.liquidationProtocolFee,
                debtAssetConfig.liquidationThreshold,
                debtAssetConfig.liquidationTargetLtv
            );
        if (debtAssetConfig.liquidationThreshold == 0)
            return (
                collateralAssetConfig.liquidationFee,
                collateralAssetConfig.liquidationProtocolFee,
                collateralAssetConfig.liquidationThreshold,
                collateralAssetConfig.liquidationTargetLtv
            );

        return (
            Math.max(debtAssetConfig.liquidationFee, collateralAssetConfig.liquidationFee),
            Math.max(debtAssetConfig.liquidationProtocolFee, collateralAssetConfig.liquidationProtocolFee),
            Math.min(debtAssetConfig.liquidationThreshold, collateralAssetConfig.liquidationThreshold),
            Math.min(debtAssetConfig.liquidationTargetLtv, collateralAssetConfig.liquidationTargetLtv)
        );
    }

    function _getPriceWithPrecisionAndEthAmountPerDebt(
        address debt,
        address collateral,
        uint256 ethAmount
    ) private view returns (uint256, uint256, uint256) {
        uint256 assetDecimal = _assetConfig[debt].decimal;
        uint256 collateralDecimal = _assetConfig[collateral].decimal;

        address[] memory assets = new address[](3);
        assets[0] = debt;
        assets[1] = collateral;
        assets[2] = address(0);

        uint256[] memory prices = ICouponOracle(oracle).getAssetsPrices(assets);
        uint256 precisionComplement;
        if (assetDecimal > collateralDecimal) {
            precisionComplement = 10 ** (assetDecimal - collateralDecimal);
            return (
                prices[0],
                prices[1] * precisionComplement,
                (ethAmount * prices[2] * precisionComplement) / prices[0]
            );
        }
        precisionComplement = 10 ** (collateralDecimal - assetDecimal);
        return (prices[0] * precisionComplement, prices[1], (ethAmount * prices[2]) / prices[0] / precisionComplement);
    }

    function _getLiquidationAmount(
        Types.Loan memory loan,
        uint256 maxRepayAmount
    ) private view returns (uint256 liquidationAmount, uint256 repayAmount, uint256 protocolFeeAmount) {
        (
            uint256 liquidationFee,
            uint256 liquidationProtocolFee,
            uint256 liquidationThreshold,
            uint256 liquidationTargetLtv
        ) = _getAssetConfig(loan.debtToken, loan.collateralToken);
        (uint256 assetPrice, uint256 collateralPrice, uint256 minDebtValue) = _getPriceWithPrecisionAndEthAmountPerDebt(
            loan.debtToken,
            loan.collateralToken,
            minDebtValueInEth
        );

        if (block.timestamp > loan.expiredAt) {
            repayAmount = loan.debtAmount;
            if (repayAmount > maxRepayAmount) {
                repayAmount = maxRepayAmount;
            }

            liquidationAmount = Math.ceilDiv(
                repayAmount * assetPrice * _RATE_PRECISION,
                collateralPrice * (_RATE_PRECISION - liquidationFee)
            );
            unchecked {
                protocolFeeAmount = (liquidationAmount * liquidationProtocolFee) / _RATE_PRECISION;
                liquidationAmount -= protocolFeeAmount;
            }
            return (liquidationAmount, repayAmount, protocolFeeAmount);
        }

        uint256 assetAmountInBaseCurrency = loan.debtAmount * assetPrice * _RATE_PRECISION;
        uint256 collateralAmountInBaseCurrency = loan.collateralAmount * collateralPrice * _RATE_PRECISION;

        unchecked {
            if ((collateralAmountInBaseCurrency / _RATE_PRECISION) * liquidationThreshold > assetAmountInBaseCurrency)
                return (0, 0, 0);

            liquidationAmount = Math.ceilDiv(
                assetAmountInBaseCurrency - (collateralAmountInBaseCurrency / _RATE_PRECISION) * liquidationTargetLtv,
                collateralPrice * (_RATE_PRECISION - liquidationFee - liquidationTargetLtv)
            );

            repayAmount =
                (liquidationAmount * collateralPrice * (_RATE_PRECISION - liquidationFee)) /
                assetPrice /
                _RATE_PRECISION;

            uint256 newRepayAmount = Math.min(repayAmount, maxRepayAmount);
            if (loan.debtAmount <= newRepayAmount + minDebtValue) {
                newRepayAmount = loan.debtAmount;
                require(newRepayAmount <= maxRepayAmount, "SMALL_LIQUIDATION");
            }

            if (newRepayAmount != repayAmount) {
                liquidationAmount = Math.ceilDiv(
                    newRepayAmount * assetPrice * _RATE_PRECISION,
                    _RATE_PRECISION - liquidationFee
                );
            }
            repayAmount = newRepayAmount;
            protocolFeeAmount = (liquidationAmount * liquidationProtocolFee) / _RATE_PRECISION;
            liquidationAmount -= protocolFeeAmount;
        }
    }

    function getLiquidationStatus(
        uint256 tokenId,
        uint256 maxRepayAmount
    ) external view returns (Types.LiquidationStatus memory) {
        (uint256 liquidationAmount, uint256 repayAmount, ) = _getLiquidationAmount(
            _loanMap[tokenId],
            maxRepayAmount > 0 ? maxRepayAmount : type(uint256).max
        );
        return
            Types.LiquidationStatus({
                available: liquidationAmount > 0,
                liquidationAmount: liquidationAmount,
                repayAmount: repayAmount
            });
    }

    function mint(
        address collateralToken,
        address debtToken,
        uint256 loanEpochs,
        uint256 collateralAmount,
        uint256 debtAmount,
        address recipient,
        bytes calldata data
    ) external returns (uint256) {
        revert("not implemented");
    }

    function adjustPosition(
        uint256 tokenId,
        int256 debtAmount,
        int256 collateralAmount,
        int256 loanEpochs,
        bytes calldata data
    ) external {
        revert("not implemented");
    }

    function liquidate(uint256 tokenId, uint256 maxRepayAmount, bytes calldata data) external {
        Types.Loan memory loan = _loanMap[tokenId];
        (uint256 liquidationAmount, uint256 repayAmount, uint256 protocolFeeAmount) = _getLiquidationAmount(
            loan,
            maxRepayAmount > 0 ? maxRepayAmount : type(uint256).max
        );

        require(liquidationAmount > 0, "LIQUIDATION_FAIL");

        unchecked {
            _loanMap[tokenId].collateralAmount = loan.collateralAmount - liquidationAmount - protocolFeeAmount;
            _loanMap[tokenId].debtAmount = loan.debtAmount - repayAmount;
        }

        IAssetPool(assetPool).withdraw(loan.collateralToken, liquidationAmount, msg.sender);
        IAssetPool(assetPool).withdraw(loan.collateralToken, protocolFeeAmount, treasury);
        if (data.length > 0) {
            ILiquidateCallbackReceiver(msg.sender).couponFinanceLiquidateCallback(
                tokenId,
                loan.collateralToken,
                loan.debtToken,
                liquidationAmount,
                repayAmount,
                data
            );
        }
        IERC20(loan.debtToken).safeTransferFrom(msg.sender, assetPool, repayAmount);
        IAssetPool(assetPool).deposit(loan.debtToken, repayAmount);

        // Todo check if ownerOf(tokenId) is contract
        Types.Epoch epoch = Epoch.current();
        uint256 length = Epoch.fromTimestamp(loan.expiredAt).sub(epoch) + 1;
        Types.Coupon[] memory coupons = new Types.Coupon[](length);
        for (uint256 i = 0; i < length; ++i) {
            coupons[i] = Coupon.from(loan.debtToken, epoch, repayAmount);
            epoch = epoch.add(1);
        }
        ICouponManager(coupon).safeBatchTransferFrom(address(this), ownerOf(tokenId), coupons, data);
    }

    function burn(uint256 tokenId) external {
        revert("not implemented");
    }

    function _getAndIncrementNonce(uint256 tokenId) internal override returns (uint256) {
        return _loanMap[tokenId].nonce++;
    }
}
