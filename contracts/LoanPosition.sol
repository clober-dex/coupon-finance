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
import {Errors} from "./Errors.sol";
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
    ) private view returns (Types.AssetLoanConfiguration memory) {
        Types.AssetLoanConfiguration memory debtAssetConfig = _assetConfig[asset];
        Types.AssetLoanConfiguration memory collateralAssetConfig = _assetConfig[collateral];

        if (collateralAssetConfig.liquidationThreshold == 0) return debtAssetConfig;
        if (debtAssetConfig.liquidationThreshold == 0) return collateralAssetConfig;

        return
            Types.AssetLoanConfiguration({
                decimal: 0,
                liquidationFee: debtAssetConfig.liquidationFee > collateralAssetConfig.liquidationFee
                    ? debtAssetConfig.liquidationFee
                    : collateralAssetConfig.liquidationFee,
                liquidationProtocolFee: debtAssetConfig.liquidationProtocolFee >
                    collateralAssetConfig.liquidationProtocolFee
                    ? debtAssetConfig.liquidationProtocolFee
                    : collateralAssetConfig.liquidationProtocolFee,
                liquidationThreshold: debtAssetConfig.liquidationThreshold > collateralAssetConfig.liquidationThreshold
                    ? collateralAssetConfig.liquidationThreshold
                    : debtAssetConfig.liquidationThreshold,
                liquidationTargetLtv: debtAssetConfig.liquidationTargetLtv > collateralAssetConfig.liquidationTargetLtv
                    ? collateralAssetConfig.liquidationTargetLtv
                    : debtAssetConfig.liquidationTargetLtv
            });
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
        ethAmount = (ethAmount * prices[2]) / 10 ** (18 - assetDecimal) / prices[0];
        if (assetDecimal > collateralDecimal) {
            precisionComplement = 10 ** (assetDecimal - collateralDecimal);
            return (prices[0], prices[1] * precisionComplement, ethAmount);
        }
        precisionComplement = 10 ** (collateralDecimal - assetDecimal);
        return (prices[0] * precisionComplement, prices[1], ethAmount);
    }

    function _getLiquidationAmount(
        Types.Loan memory loan,
        uint256 maxRepayAmount
    ) private view returns (uint256 liquidationAmount, uint256 repayAmount, uint256 protocolFeeAmount) {
        Types.AssetLoanConfiguration memory config = _getAssetConfig(loan.debtToken, loan.collateralToken);
        (uint256 assetPrice, uint256 collateralPrice, uint256 minDebtValue) = _getPriceWithPrecisionAndEthAmountPerDebt(
            loan.debtToken,
            loan.collateralToken,
            minDebtValueInEth
        );

        if (block.timestamp > loan.expiredAt) {
            unchecked {
                if (maxRepayAmount >= loan.debtAmount) repayAmount = loan.debtAmount;
                else if (maxRepayAmount + minDebtValue > loan.debtAmount) {
                    require(loan.debtAmount >= minDebtValue, Errors.TOO_SMALL_DEBT);
                    repayAmount = loan.debtAmount - minDebtValue;
                } else repayAmount = maxRepayAmount;
            }

            liquidationAmount = Math.ceilDiv(
                repayAmount * assetPrice * _RATE_PRECISION,
                collateralPrice * (_RATE_PRECISION - config.liquidationFee)
            );
            unchecked {
                protocolFeeAmount = (liquidationAmount * config.liquidationProtocolFee) / _RATE_PRECISION;
                return (liquidationAmount - protocolFeeAmount, repayAmount, protocolFeeAmount);
            }
        }

        uint256 assetAmountInBaseCurrency = loan.debtAmount * assetPrice * _RATE_PRECISION;
        uint256 collateralAmountInBaseCurrency = loan.collateralAmount * collateralPrice * _RATE_PRECISION;

        unchecked {
            if (
                (collateralAmountInBaseCurrency / _RATE_PRECISION) * config.liquidationThreshold >
                assetAmountInBaseCurrency
            ) return (0, 0, 0);

            liquidationAmount = Math.ceilDiv(
                assetAmountInBaseCurrency -
                    (collateralAmountInBaseCurrency / _RATE_PRECISION) *
                    config.liquidationTargetLtv,
                collateralPrice * (_RATE_PRECISION - config.liquidationFee - config.liquidationTargetLtv)
            );
            repayAmount =
                (liquidationAmount * collateralPrice * (_RATE_PRECISION - config.liquidationFee)) /
                assetPrice /
                _RATE_PRECISION;

            // reuse newRepayAmount
            uint256 newRepayAmount = loan.debtAmount;

            if (newRepayAmount <= minDebtValue) {
                require(maxRepayAmount >= newRepayAmount, Errors.TOO_SMALL_DEBT);
            } else if (repayAmount > newRepayAmount || newRepayAmount < minDebtValue + repayAmount) {
                if (maxRepayAmount < newRepayAmount) {
                    newRepayAmount = Math.min(maxRepayAmount, newRepayAmount - minDebtValue);
                }
            } else {
                newRepayAmount = Math.min(maxRepayAmount, repayAmount);
            }

            if (newRepayAmount != repayAmount) {
                liquidationAmount = Math.ceilDiv(
                    newRepayAmount * assetPrice * _RATE_PRECISION,
                    collateralPrice * (_RATE_PRECISION - config.liquidationFee)
                );
                repayAmount = newRepayAmount;
            }

            if (liquidationAmount > loan.collateralAmount) liquidationAmount = loan.collateralAmount;
            protocolFeeAmount = (liquidationAmount * config.liquidationProtocolFee) / _RATE_PRECISION;
            return (liquidationAmount - protocolFeeAmount, repayAmount, protocolFeeAmount);
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
        return Types.LiquidationStatus({liquidationAmount: liquidationAmount, repayAmount: repayAmount});
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

        unchecked {
            address couponOwner = ownerOf(tokenId);
            Types.Epoch epoch = Epoch.current();
            uint256 length = Epoch.fromTimestamp(loan.expiredAt).sub(epoch) + 1;
            Types.Coupon[] memory coupons = new Types.Coupon[](length);
            for (uint256 i = 0; i < length; ++i) {
                coupons[i] = Coupon.from(loan.debtToken, epoch, repayAmount);
                epoch = epoch.add(1);
            }
            try ICouponManager(coupon).safeBatchTransferFrom(address(this), ownerOf(tokenId), coupons, data) {} catch {
                for (uint256 i = 0; i < length; ++i) {
                    couponOwed[couponOwner][coupons[i].id()] += coupons[i].amount;
                }
            }
        }
    }

    function claimOwedCoupons(Types.CouponKey[] memory couponKeys, bytes calldata data) external {
        uint256 length = couponKeys.length;
        Types.Coupon[] memory coupons = new Types.Coupon[](length);
        for (uint256 i = 0; i < length; ++i) {
            coupons[i].key = couponKeys[i];
            coupons[i].amount = couponOwed[msg.sender][couponKeys[i].toId()];
        }
        ICouponManager(coupon).safeBatchTransferFrom(address(this), msg.sender, coupons, data);
    }

    function burn(uint256 tokenId) external {
        revert("not implemented");
    }

    function _getAndIncrementNonce(uint256 tokenId) internal override returns (uint256) {
        return _loanMap[tokenId].nonce++;
    }
}
