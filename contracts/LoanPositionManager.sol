// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ILoanPositionManager} from "./interfaces/ILoanPositionManager.sol";
import {IAssetPool} from "./interfaces/IAssetPool.sol";
import {ILiquidateCallbackReceiver} from "./interfaces/ILiquidateCallbackReceiver.sol";
import {ICouponOracle} from "./interfaces/ICouponOracle.sol";
import {ICouponManager} from "./interfaces/ICouponManager.sol";
import {ERC721Permit} from "./libraries/ERC721Permit.sol";
import {ReentrancyGuard} from "./libraries/ReentrancyGuard.sol";
import {CouponKey} from "./libraries/CouponKey.sol";
import {Coupon} from "./libraries/Coupon.sol";
import {Epoch} from "./libraries/Epoch.sol";
import {Types} from "./Types.sol";
import {Errors} from "./Errors.sol";

contract LoanPositionManager is ILoanPositionManager, ERC721Permit, Ownable {
    using SafeERC20 for IERC20;
    using CouponKey for Types.CouponKey;
    using Coupon for Types.Coupon;
    using Epoch for Types.Epoch;

    uint256 private constant _RATE_PRECISION = 10 ** 6;

    address public immutable override couponManager;
    address public immutable override assetPool;
    address public immutable override oracle;
    address public immutable override treasury;
    uint256 public immutable override minDebtValueInEth;

    string public override baseURI;
    uint256 public override nextId = 1;

    mapping(address user => mapping(uint256 couponId => uint256)) public override couponOwed;
    mapping(address asset => Types.AssetLoanConfiguration) private _assetConfig;
    mapping(uint256 id => Types.LoanPosition) private _positionMap;

    constructor(
        address couponManager_,
        address assetPool_,
        address oracle_,
        address treasury_,
        uint256 minDebtValueInEth_,
        string memory baseURI_
    ) ERC721Permit("Loan Position", "LP", "1") {
        couponManager = couponManager_;
        assetPool = assetPool_;
        oracle = oracle_;
        baseURI = baseURI_;
        treasury = treasury_;
        minDebtValueInEth = minDebtValueInEth_;
    }

    function getPosition(uint256 tokenId) external view returns (Types.LoanPosition memory) {
        return _positionMap[tokenId];
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
        Types.LoanPosition memory position,
        uint256 maxRepayAmount
    ) private view returns (uint256 liquidationAmount, uint256 repayAmount, uint256 protocolFeeAmount) {
        Types.AssetLoanConfiguration memory config = _getAssetConfig(position.debtToken, position.collateralToken);
        (uint256 assetPrice, uint256 collateralPrice, uint256 minDebtValue) = _getPriceWithPrecisionAndEthAmountPerDebt(
            position.debtToken,
            position.collateralToken,
            minDebtValueInEth
        );

        if (position.expiredWith.isExpired()) {
            unchecked {
                if (maxRepayAmount >= position.debtAmount) repayAmount = position.debtAmount;
                else if (maxRepayAmount + minDebtValue > position.debtAmount) {
                    require(position.debtAmount >= minDebtValue, Errors.TOO_SMALL_DEBT);
                    repayAmount = position.debtAmount - minDebtValue;
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

        uint256 assetAmountInBaseCurrency = position.debtAmount * assetPrice * _RATE_PRECISION;
        uint256 collateralAmountInBaseCurrency = position.collateralAmount * collateralPrice * _RATE_PRECISION;

        unchecked {
            if (
                (collateralAmountInBaseCurrency / _RATE_PRECISION) * config.liquidationThreshold >=
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
            uint256 newRepayAmount = position.debtAmount;

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

            if (liquidationAmount > position.collateralAmount) liquidationAmount = position.collateralAmount;
            protocolFeeAmount = (liquidationAmount * config.liquidationProtocolFee) / _RATE_PRECISION;
            return (liquidationAmount - protocolFeeAmount, repayAmount, protocolFeeAmount);
        }
    }

    function getLiquidationStatus(
        uint256 tokenId,
        uint256 maxRepayAmount
    ) external view returns (Types.LiquidationStatus memory) {
        (uint256 liquidationAmount, uint256 repayAmount, ) = _getLiquidationAmount(
            _positionMap[tokenId],
            maxRepayAmount > 0 ? maxRepayAmount : type(uint256).max
        );
        return Types.LiquidationStatus({liquidationAmount: liquidationAmount, repayAmount: repayAmount});
    }

    // Todo Progressing
    function mint(
        address collateralToken,
        address debtToken,
        uint256 collateralAmount,
        uint256 debtAmount,
        uint256 loanEpochs,
        address recipient,
        bytes calldata data
    ) external returns (uint256) {
        uint256 currentId = nextId;

        {
            Types.AssetLoanConfiguration memory config = _getAssetConfig(debtToken, collateralToken);
            (
                uint256 assetPrice,
                uint256 collateralPrice,
                uint256 minDebtValue
            ) = _getPriceWithPrecisionAndEthAmountPerDebt(debtToken, collateralToken, minDebtValueInEth);

            require(minDebtValue <= debtAmount, Errors.TOO_SMALL_DEBT);
            require(
                (collateralAmount * collateralPrice) * config.liquidationThreshold >=
                    debtAmount * assetPrice * _RATE_PRECISION,
                Errors.LIQUIDATION_THRESHOLD
            );
        }

        Types.Epoch expiredWith = Epoch.wrap(uint16(loanEpochs));

        unchecked {
            Types.Epoch epoch = Epoch.current();
            uint256 length = expiredWith.sub(epoch);
            Types.Coupon[] memory coupons = new Types.Coupon[](length);
            for (uint256 i = 0; i < length; ++i) {
                coupons[i] = Coupon.from(debtToken, epoch, debtAmount);
                epoch = epoch.add(1);
            }
            ICouponManager(couponManager).safeBatchTransferFrom(msg.sender, address(this), coupons, new bytes(0));
        }

        _positionMap[currentId] = Types.LoanPosition({
            nonce: 0,
            collateralToken: collateralToken,
            debtToken: debtToken,
            collateralAmount: collateralAmount,
            debtAmount: debtAmount,
            expiredWith: expiredWith
        });

        emit PositionUpdated(nextId, collateralAmount, debtAmount, expiredWith);

        if (data.length > 0) {} else {
            if (debtAmount > 0) {
                IAssetPool(assetPool).withdraw(debtToken, debtAmount, recipient);
            }

            if (collateralAmount > 0) {
                IERC20(collateralToken).safeTransferFrom(msg.sender, assetPool, collateralAmount);
                IAssetPool(assetPool).deposit(collateralToken, collateralAmount);
            }
        }

        _mint(recipient, currentId);

        nextId = currentId + 1;
        return currentId;
    }

    function adjustPosition(
        uint256 tokenId,
        uint256 collateralAmount,
        uint256 debtAmount,
        Types.Epoch expiredWith,
        bytes calldata data
    ) external {
        revert("not implemented");
    }

    function liquidate(uint256 tokenId, uint256 maxRepayAmount, bytes calldata data) external {
        Types.LoanPosition memory position = _positionMap[tokenId];
        (uint256 liquidationAmount, uint256 repayAmount, uint256 protocolFeeAmount) = _getLiquidationAmount(
            position,
            maxRepayAmount > 0 ? maxRepayAmount : type(uint256).max
        );

        require(liquidationAmount > 0, "LIQUIDATION_FAIL");

        unchecked {
            _positionMap[tokenId].collateralAmount = position.collateralAmount - liquidationAmount - protocolFeeAmount;
            _positionMap[tokenId].debtAmount = position.debtAmount - repayAmount;
        }

        IAssetPool(assetPool).withdraw(position.collateralToken, liquidationAmount, msg.sender);
        IAssetPool(assetPool).withdraw(position.collateralToken, protocolFeeAmount, treasury);
        if (data.length > 0) {
            ILiquidateCallbackReceiver(msg.sender).couponFinanceLiquidateCallback(
                tokenId,
                position.collateralToken,
                position.debtToken,
                liquidationAmount,
                repayAmount,
                data
            );
        }
        IERC20(position.debtToken).safeTransferFrom(msg.sender, assetPool, repayAmount);
        IAssetPool(assetPool).deposit(position.debtToken, repayAmount);

        // Todo enhance performance
        unchecked {
            address couponOwner = ownerOf(tokenId);
            Types.Epoch epoch = Epoch.current();
            if (epoch.compare(position.expiredWith) <= 0) {
                uint256 length = position.expiredWith.sub(epoch);
                Types.Coupon[] memory coupons = new Types.Coupon[](length);
                for (uint256 i = 0; i < length; ++i) {
                    coupons[i] = Coupon.from(position.debtToken, epoch, repayAmount);
                    epoch = epoch.add(1);
                }
                try
                    ICouponManager(couponManager).safeBatchTransferFrom(address(this), ownerOf(tokenId), coupons, data)
                {} catch {
                    for (uint256 i = 0; i < length; ++i) {
                        couponOwed[couponOwner][coupons[i].id()] += coupons[i].amount;
                    }
                }
            }
        }
        emit PositionLiquidated(tokenId);
    }

    function claimOwedCoupons(Types.CouponKey[] memory couponKeys, bytes calldata data) external {
        uint256 length = couponKeys.length;
        uint256[] memory ids = new uint256[](length);
        uint256[] memory amounts = new uint256[](length);
        for (uint256 i = 0; i < length; ++i) {
            uint256 id = couponKeys[i].toId();
            ids[i] = id;
            amounts[i] = couponOwed[msg.sender][id];
            couponOwed[msg.sender][id] = 0;
        }
        ICouponManager(couponManager).safeBatchTransferFrom(address(this), msg.sender, ids, amounts, data);
    }

    function burn(uint256 tokenId) external {
        revert("not implemented");
    }

    function _getAndIncrementNonce(uint256 tokenId) internal override returns (uint256) {
        return _positionMap[tokenId].nonce++;
    }

    // Todo implement ERC1155Holder?
    function onERC1155Received(address, address, uint256, uint256, bytes memory) public returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }
}
