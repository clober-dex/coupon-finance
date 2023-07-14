// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {ERC721Permit} from "./libraries/ERC721Permit.sol";
import {ReentrancyGuard} from "./libraries/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Types} from "./Types.sol";
import {ILoanPosition} from "./interfaces/ILoanPosition.sol";
import {IAssetPool} from "./interfaces/IAssetPool.sol";
import {ILiquidateCallbackReceiver} from "./interfaces/ILiquidateCallbackReceiver.sol";

import {IAaveOracle} from "./external/aave-v3/IAaveOracle.sol";

contract LoanPosition is ILoanPosition, ERC721Permit {
    using SafeERC20 for IERC20;

    uint256 private constant _RATE_PRECISION = 10 ** 6;

    address public immutable override coupon;
    address public immutable override assetPool;
    address public immutable override oracle;
    address public immutable override treasury;

    string public override baseURI;
    uint256 public override nextId;

    mapping(address user => mapping(uint256 couponId => uint256)) public override couponOwed;
    mapping(address asset => Types.AssetLoanConfiguration) private _assetConfig;
    mapping(uint256 id => Types.Loan) private _loanMap;

    constructor(
        address coupon_,
        address assetPool_,
        address oracle_,
        address treasury_,
        string memory baseURI_
    ) ERC721Permit("Loan Position", "LP", "1") {
        coupon = coupon_;
        assetPool = assetPool_;
        oracle = oracle_;
        baseURI = baseURI_;
        treasury = treasury_;
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

    function _getAssetConfig(
        address asset,
        address collateral
    ) private view returns (Types.AssetLoanConfiguration memory) {
        Types.AssetLoanConfiguration memory debtAssetConfig = _assetConfig[asset];
        Types.AssetLoanConfiguration memory collateralAssetConfig = _assetConfig[collateral];

        if (collateralAssetConfig.liquidationThreshold == 0) return debtAssetConfig;
        if (debtAssetConfig.liquidationThreshold == 0) return collateralAssetConfig;

        if (debtAssetConfig.liquidationFee > collateralAssetConfig.liquidationFee) {
            collateralAssetConfig.liquidationFee = debtAssetConfig.liquidationFee;
        }
        if (debtAssetConfig.liquidationProtocolFee > collateralAssetConfig.liquidationProtocolFee) {
            collateralAssetConfig.liquidationProtocolFee = debtAssetConfig.liquidationProtocolFee;
        }
        if (debtAssetConfig.liquidationThreshold < collateralAssetConfig.liquidationThreshold) {
            collateralAssetConfig.liquidationThreshold = debtAssetConfig.liquidationThreshold;
        }
        if (debtAssetConfig.liquidationTargetLtv < collateralAssetConfig.liquidationTargetLtv) {
            collateralAssetConfig.liquidationTargetLtv = debtAssetConfig.liquidationTargetLtv;
        }
        return collateralAssetConfig;
    }

    function _getPriceWithPrecisionAndEthAmount(
        address debt,
        address collateral,
        uint256 ethAmount
    ) private view returns (uint256, uint256, uint256) {
        address[] memory assets = new address[](3);
        assets[0] = debt;
        assets[1] = collateral;
        assets[2] = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

        uint256 assetDecimal = _assetConfig[debt].decimal;
        uint256 collateralDecimal = _assetConfig[collateral].decimal;

        uint256[] memory prices = IAaveOracle(oracle).getAssetsPrices(assets);
        ethAmount = (ethAmount * prices[2]) / prices[0];
        if (assetDecimal > collateralDecimal) {
            return (prices[0], prices[1] * 10 ** (assetDecimal - collateralDecimal), ethAmount);
        }
        return (prices[0] * 10 ** (collateralDecimal - assetDecimal), prices[1], ethAmount);
    }

    function _getLiquidationAmount(
        Types.Loan memory loan,
        uint256 maxRepayAmount
    ) private view returns (uint256 liquidationAmount, uint256 repayAmount, uint256 protocolFeeAmount) {
        Types.AssetLoanConfiguration memory assetConfig = _getAssetConfig(loan.debtToken, loan.collateralToken);
        (uint256 assetPrice, uint256 collateralPrice, uint256 ethAmount) = _getPriceWithPrecisionAndEthAmount(
            loan.debtToken,
            loan.collateralToken,
            10 ** 17
        );

        if (block.timestamp > loan.expiredAt) {
            repayAmount = loan.debtAmount;
            if (repayAmount > maxRepayAmount) {
                repayAmount = maxRepayAmount;
            }

            // Todo: round up liquidation amount
            liquidationAmount =
                (repayAmount * assetPrice * _RATE_PRECISION) /
                collateralPrice /
                (_RATE_PRECISION - assetConfig.liquidationFee);
            protocolFeeAmount = (liquidationAmount * assetConfig.liquidationProtocolFee) / _RATE_PRECISION;
            return (liquidationAmount, repayAmount, protocolFeeAmount);
        }

        uint256 assetAmountInBaseCurrency = loan.debtAmount * assetPrice * _RATE_PRECISION;
        uint256 collateralAmountInBaseCurrency = loan.collateralAmount * collateralPrice * _RATE_PRECISION;

        unchecked {
            if (
                (collateralAmountInBaseCurrency / _RATE_PRECISION) * assetConfig.liquidationThreshold >
                assetAmountInBaseCurrency
            ) return (0, 0, 0);

            // Todo: round up liquidation amount
            liquidationAmount =
                (assetAmountInBaseCurrency -
                    (collateralAmountInBaseCurrency / _RATE_PRECISION) *
                    assetConfig.liquidationTargetLtv) /
                collateralPrice /
                (_RATE_PRECISION - assetConfig.liquidationFee - assetConfig.liquidationTargetLtv);

            repayAmount =
                (liquidationAmount * collateralPrice * (_RATE_PRECISION - assetConfig.liquidationFee)) /
                _RATE_PRECISION;

            uint256 newRepayAmount = Math.min(repayAmount, maxRepayAmount);
            if (loan.debtAmount <= newRepayAmount + ethAmount) {
                newRepayAmount = loan.debtAmount;
                require(newRepayAmount <= maxRepayAmount, "SMALL_LIQUIDATION");
            }

            if (newRepayAmount != repayAmount) {
                // Todo: round up liquidation amount
                liquidationAmount =
                    (newRepayAmount * assetPrice * _RATE_PRECISION) /
                    collateralPrice /
                    (_RATE_PRECISION - assetConfig.liquidationFee);
            }
            repayAmount = newRepayAmount;
            protocolFeeAmount = (liquidationAmount * assetConfig.liquidationProtocolFee) / _RATE_PRECISION;
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

        _loanMap[tokenId].collateralAmount = loan.collateralAmount - liquidationAmount;
        _loanMap[tokenId].debtAmount = loan.debtAmount - repayAmount;

        IAssetPool(assetPool).withdraw(loan.collateralToken, liquidationAmount - protocolFeeAmount, msg.sender);
        IAssetPool(assetPool).withdraw(loan.collateralToken, protocolFeeAmount, treasury);
        if (data.length > 0) {
            uint256 beforeDebtAmount = IERC20(loan.debtToken).balanceOf(address(this));
            ILiquidateCallbackReceiver(msg.sender).couponFinanceLiquidateCallback(
                tokenId,
                loan.collateralToken,
                loan.debtToken,
                liquidationAmount - protocolFeeAmount,
                repayAmount,
                data
            );
            uint256 afterDebtAmount = IERC20(loan.debtToken).balanceOf(address(this));
            require(afterDebtAmount - beforeDebtAmount >= repayAmount, "NOT_RECEIVED_DEBT");
        } else {
            IERC20(loan.debtToken).safeTransferFrom(msg.sender, address(this), repayAmount);
        }
        IAssetPool(assetPool).deposit(loan.debtToken, repayAmount);

        // Todo coupon has to be refund to ownerOf(tokenId)
    }

    function burn(uint256 tokenId) external {
        revert("not implemented");
    }

    function _getAndIncrementNonce(uint256 tokenId) internal override returns (uint256) {
        return _loanMap[tokenId].nonce++;
    }
}
