// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ERC1155Holder, ERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {ILoanPositionManager} from "./interfaces/ILoanPositionManager.sol";
import {IAssetPool} from "./interfaces/IAssetPool.sol";
import {ILiquidateCallbackReceiver} from "./interfaces/ILiquidateCallbackReceiver.sol";
import {ILoanPositionCallbackReceiver} from "./interfaces/ILoanPositionCallbackReceiver.sol";
import {ICouponOracle} from "./interfaces/ICouponOracle.sol";
import {ICouponManager} from "./interfaces/ICouponManager.sol";
import {ERC721Permit, IERC165} from "./libraries/ERC721Permit.sol";
import {ReentrancyGuard} from "./libraries/ReentrancyGuard.sol";
import {CouponKey, CouponKeyLibrary} from "./libraries/CouponKey.sol";
import {Coupon, CouponLibrary} from "./libraries/Coupon.sol";
import {Epoch, EpochLibrary} from "./libraries/Epoch.sol";
import {LoanPosition, LoanPositionLibrary} from "./libraries/LoanPosition.sol";
import {Errors} from "./Errors.sol";

contract LoanPositionManager is ILoanPositionManager, ERC721Permit, Ownable, ERC1155Holder {
    using SafeERC20 for IERC20;
    using Strings for uint256;
    using LoanPositionLibrary for LoanPosition;
    using CouponKeyLibrary for CouponKey;
    using CouponLibrary for Coupon;
    using EpochLibrary for Epoch;

    uint256 private constant _RATE_PRECISION = 10 ** 6;

    address public immutable override couponManager;
    address public immutable override assetPool;
    address public immutable override oracle;
    address public immutable override treasury;
    uint256 public immutable override minDebtValueInEth;

    string public override baseURI;
    uint256 public override nextId = 1;

    mapping(address user => mapping(uint256 couponId => uint256)) private _couponOwed;
    mapping(bytes32 => LoanConfiguration) private _loanConfiguration;
    mapping(uint256 id => LoanPosition) private _positionMap;

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

    function getPosition(uint256 tokenId) external view returns (LoanPosition memory) {
        return _positionMap[tokenId];
    }

    function isPairRegistered(address collateral, address debt) external view returns (bool) {
        return !_isPairUnregistered(collateral, debt);
    }

    function getLoanConfiguration(address asset) external view returns (AssetLoanConfiguration memory) {
        return _assetConfig[asset];
    }

    function getOwedCouponAmount(address user, uint256 couponId) external view returns (uint256) {
        return _couponOwed[user][couponId];
    }

    function setLoanConfiguration(address asset, AssetLoanConfiguration memory config) external onlyOwner {
        require(_assetConfig[asset].liquidationThreshold == 0, "INITIALIZED");
        config.decimal = IERC20Metadata(asset).decimals();
        _assetConfig[asset] = config;


    function getLoanConfiguration(address collateral, address debt) external view returns (LoanConfiguration memory) {
        return _loanConfiguration[keccak256(abi.encodePacked(collateral, debt))];
    }

    function setLoanConfiguration(
        address collateral,
        address debt,
        uint32 liquidationThreshold,
        uint32 liquidationFee,
        uint32 liquidationProtocolFee,
        uint32 liquidationTargetLtv
    ) external onlyOwner {
        bytes32 hash = keccak256(abi.encodePacked(collateral, debt));
        require(_loanConfiguration[hash].liquidationThreshold == 0, "INITIALIZED");
        _loanConfiguration[hash] = LoanConfiguration({
            collateralDecimal: IERC20Metadata(collateral).decimals(),
            debtDecimal: IERC20Metadata(debt).decimals(),
            liquidationThreshold: liquidationThreshold,
            liquidationFee: liquidationFee,
            liquidationProtocolFee: liquidationProtocolFee,
            liquidationTargetLtv: liquidationTargetLtv
        });
    }

    function _getPriceWithPrecisionComplementAndEthAmountPerDebt(
        address collateral,
        address debt,
        LoanConfiguration memory loanConfig,
        uint256 ethAmount
    ) private view returns (uint256, uint256, uint256) {
        uint256 collateralDecimal = loanConfig.collateralDecimal;
        uint256 debtDecimal = loanConfig.debtDecimal;

        address[] memory assets = new address[](3);
        assets[0] = collateral;
        assets[1] = debt;
        assets[2] = address(0);

        uint256[] memory prices = ICouponOracle(oracle).getAssetsPrices(assets);
        uint256 precisionComplement;
        ethAmount = (ethAmount * prices[2]) / 10 ** (18 - debtDecimal) / prices[1];
        if (debtDecimal > collateralDecimal) {
            precisionComplement = 10 ** (debtDecimal - collateralDecimal);
            return (prices[0] * precisionComplement, prices[1], ethAmount);
        }
        precisionComplement = 10 ** (collateralDecimal - debtDecimal);
        return (prices[0], prices[1] * precisionComplement, ethAmount);
    }

    function _getLiquidationAmount(
        LoanPosition memory position,
        uint256 maxRepayAmount
    ) private view returns (uint256 liquidationAmount, uint256 repayAmount, uint256 protocolFeeAmount) {
        LoanConfiguration memory loanConfig = _loanConfiguration[
            keccak256(abi.encodePacked(position.collateralToken, position.debtToken))
        ];
        (
            uint256 collateralPrice,
            uint256 debtPrice,
            uint256 minDebtValue
        ) = _getPriceWithPrecisionComplementAndEthAmountPerDebt(
                position.collateralToken,
                position.debtToken,
                loanConfig,
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
                repayAmount * debtPrice * _RATE_PRECISION,
                collateralPrice * (_RATE_PRECISION - loanConfig.liquidationFee)
            );
            unchecked {
                protocolFeeAmount = (liquidationAmount * loanConfig.liquidationProtocolFee) / _RATE_PRECISION;
                return (liquidationAmount - protocolFeeAmount, repayAmount, protocolFeeAmount);
            }
        }

        uint256 collateralAmountInBaseCurrency = position.collateralAmount * collateralPrice;
        uint256 debtAmountInBaseCurrencyMulRatePrecision = position.debtAmount * debtPrice * _RATE_PRECISION;

        unchecked {
            if (
                collateralAmountInBaseCurrency * loanConfig.liquidationThreshold >=
                debtAmountInBaseCurrencyMulRatePrecision
            ) return (0, 0, 0);

            liquidationAmount = Math.ceilDiv(
                debtAmountInBaseCurrencyMulRatePrecision -
                    collateralAmountInBaseCurrency *
                    loanConfig.liquidationTargetLtv,
                collateralPrice * (_RATE_PRECISION - loanConfig.liquidationFee - loanConfig.liquidationTargetLtv)
            );
            repayAmount =
                (liquidationAmount * collateralPrice * (_RATE_PRECISION - loanConfig.liquidationFee)) /
                debtPrice /
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
                    newRepayAmount * debtPrice * _RATE_PRECISION,
                    collateralPrice * (_RATE_PRECISION - loanConfig.liquidationFee)
                );
                repayAmount = newRepayAmount;
            }

            if (liquidationAmount > position.collateralAmount) liquidationAmount = position.collateralAmount;
            protocolFeeAmount = (liquidationAmount * loanConfig.liquidationProtocolFee) / _RATE_PRECISION;
            return (liquidationAmount - protocolFeeAmount, repayAmount, protocolFeeAmount);
        }
    }

    function getLiquidationStatus(
        uint256 tokenId,
        uint256 maxRepayAmount
    ) external view returns (LiquidationStatus memory) {
        (uint256 liquidationAmount, uint256 repayAmount, ) = _getLiquidationAmount(
            _positionMap[tokenId],
            maxRepayAmount > 0 ? maxRepayAmount : type(uint256).max
        );
        return LiquidationStatus({liquidationAmount: liquidationAmount, repayAmount: repayAmount});
    }

    function _validatePosition(LoanPosition memory position, Epoch latestExpiredEpoch) internal view {
        if (position.debtAmount > 0 && position.expiredWith.compare(latestExpiredEpoch) <= 0) {
            revert(Errors.UNPAID_DEBT);
        }

        LoanConfiguration memory loanConfig = _loanConfiguration[
            keccak256(abi.encodePacked(position.collateralToken, position.debtToken))
        ];
        (
            uint256 collateralPrice,
            uint256 debtPrice,
            uint256 minDebtValue
        ) = _getPriceWithPrecisionComplementAndEthAmountPerDebt(
                position.collateralToken,
                position.debtToken,
                loanConfig,
                minDebtValueInEth
            );

        require(position.debtAmount == 0 || minDebtValue <= position.debtAmount, Errors.TOO_SMALL_DEBT);
        require(
            (position.collateralAmount * collateralPrice) * loanConfig.liquidationThreshold >=
                position.debtAmount * debtPrice * _RATE_PRECISION,
            Errors.LIQUIDATION_THRESHOLD
        );
    }

    function mint(
        address collateralToken,
        address debtToken,
        uint256 collateralAmount,
        uint256 debtAmount,
        uint16 loanEpochs,
        address recipient,
        bytes calldata data
    ) external returns (uint256 tokenId) {
        if (_isPairUnregistered(collateralToken, debtToken)) {
            revert(Errors.UNREGISTERED_PAIR);
        }
        require(loanEpochs > 0 && debtAmount > 0, Errors.EMPTY_INPUT);
        tokenId = nextId++;

        Epoch currentEpoch = EpochLibrary.current();

        LoanPosition memory position = LoanPositionLibrary.from(
            currentEpoch.add(loanEpochs - 1),
            collateralToken,
            debtToken,
            collateralAmount,
            debtAmount
        );
        _validatePosition(position, currentEpoch.sub(1));
        Coupon[] memory coupons = new Coupon[](loanEpochs);
        for (uint16 i = 0; i < loanEpochs; ++i) {
            coupons[i] = CouponLibrary.from(debtToken, currentEpoch.add(i), debtAmount);
        }

        _positionMap[tokenId] = position;
        emit PositionUpdated(tokenId, collateralAmount, debtAmount, position.expiredWith);

        _mint(recipient, tokenId);
        IAssetPool(assetPool).withdraw(debtToken, debtAmount, recipient);

        if (data.length > 0) {
            ILoanPositionCallbackReceiver(msg.sender).loanPositionAdjustCallback(
                tokenId,
                LoanPositionLibrary.empty(collateralToken, debtToken),
                position,
                coupons,
                new Coupon[](0),
                data
            );
        }

        IERC20(collateralToken).safeTransferFrom(msg.sender, assetPool, collateralAmount);
        IAssetPool(assetPool).deposit(collateralToken, collateralAmount);
        ICouponManager(couponManager).safeBatchTransferFrom(msg.sender, address(this), coupons, data);
    }

    function adjustPosition(
        uint256 tokenId,
        uint256 collateralAmount,
        uint256 debtAmount,
        Epoch expiredWith,
        bytes calldata data
    ) external {
        require(_isApprovedOrOwner(msg.sender, tokenId), Errors.ACCESS);

        LoanPosition memory oldPosition = _positionMap[tokenId];
        Epoch latestExpiredEpoch = EpochLibrary.current().sub(1);
        require(oldPosition.expiredWith.compare(latestExpiredEpoch) > 0, Errors.INVALID_EPOCH);

        LoanPosition memory newPosition = LoanPosition({
            nonce: oldPosition.nonce,
            expiredWith: debtAmount == 0 ? latestExpiredEpoch : expiredWith,
            collateralToken: oldPosition.collateralToken,
            debtToken: oldPosition.debtToken,
            collateralAmount: collateralAmount,
            debtAmount: debtAmount
        });

        _validatePosition(newPosition, latestExpiredEpoch);

        (Coupon[] memory couponsToPay, Coupon[] memory couponsToRefund) = oldPosition.calculateCouponRequirement(
            newPosition
        );

        _positionMap[tokenId] = newPosition;
        emit PositionUpdated(tokenId, newPosition.collateralAmount, newPosition.debtAmount, newPosition.expiredWith);

        if (couponsToRefund.length > 0) {
            ICouponManager(couponManager).safeBatchTransferFrom(address(this), msg.sender, couponsToRefund, data);
        }
        if (newPosition.debtAmount > oldPosition.debtAmount) {
            IAssetPool(assetPool).withdraw(
                newPosition.debtToken,
                newPosition.debtAmount - oldPosition.debtAmount,
                msg.sender
            );
        }
        if (newPosition.collateralAmount < oldPosition.collateralAmount) {
            IAssetPool(assetPool).withdraw(
                newPosition.collateralToken,
                oldPosition.collateralAmount - newPosition.collateralAmount,
                msg.sender
            );
        }

        if (data.length > 0) {
            ILoanPositionCallbackReceiver(msg.sender).loanPositionAdjustCallback(
                tokenId,
                oldPosition,
                newPosition,
                couponsToPay,
                couponsToRefund,
                data
            );
        }

        if (newPosition.debtAmount < oldPosition.debtAmount) {
            uint256 repayAmount = oldPosition.debtAmount - newPosition.debtAmount;
            IERC20(newPosition.debtToken).safeTransferFrom(msg.sender, assetPool, repayAmount);
            IAssetPool(assetPool).deposit(newPosition.debtToken, repayAmount);
        }
        if (newPosition.collateralAmount > oldPosition.collateralAmount) {
            uint256 addCollateralAmount = newPosition.collateralAmount - oldPosition.collateralAmount;
            IERC20(newPosition.collateralToken).safeTransferFrom(msg.sender, assetPool, addCollateralAmount);
            IAssetPool(assetPool).deposit(newPosition.collateralToken, addCollateralAmount);
        }
        if (couponsToPay.length > 0) {
            ICouponManager(couponManager).safeBatchTransferFrom(msg.sender, address(this), couponsToPay, data);
        }
    }

    function liquidate(uint256 tokenId, uint256 maxRepayAmount, bytes calldata data) external {
        LoanPosition memory position = _positionMap[tokenId];
        (uint256 liquidationAmount, uint256 repayAmount, uint256 protocolFeeAmount) = _getLiquidationAmount(
            position,
            maxRepayAmount > 0 ? maxRepayAmount : type(uint256).max
        );

        require(liquidationAmount > 0 || repayAmount > 0, "LIQUIDATION_FAIL");

        unchecked {
            Epoch currentEpoch = EpochLibrary.current();
            address couponOwner = ownerOf(tokenId);
            if (position.expiredWith.compare(currentEpoch) >= 0) {
                uint256 length = position.expiredWith.sub(currentEpoch) + 1;
                Coupon[] memory coupons = new Coupon[](length);
                for (uint16 i = 0; i < length; ++i) {
                    coupons[i] = CouponLibrary.from(position.debtToken, currentEpoch.add(i), repayAmount);
                }
                try
                    ICouponManager(couponManager).safeBatchTransferFrom(address(this), couponOwner, coupons, data)
                {} catch {
                    for (uint256 i = 0; i < length; ++i) {
                        _couponOwed[couponOwner][coupons[i].id()] += coupons[i].amount;
                    }
                }
            }
            position.collateralAmount -= liquidationAmount + protocolFeeAmount;
            position.debtAmount -= repayAmount;
            if (position.debtAmount == 0) position.expiredWith = currentEpoch.sub(1);
        }
        _positionMap[tokenId].collateralAmount = position.collateralAmount;
        _positionMap[tokenId].debtAmount = position.debtAmount;

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

        emit PositionLiquidated(tokenId);
        emit PositionUpdated(tokenId, position.collateralAmount, position.debtAmount, position.expiredWith);
    }

    function claimOwedCoupons(CouponKey[] memory couponKeys, bytes calldata data) external {
        uint256 length = couponKeys.length;
        uint256[] memory ids = new uint256[](length);
        uint256[] memory amounts = new uint256[](length);
        for (uint256 i = 0; i < length; ++i) {
            uint256 id = couponKeys[i].toId();
            ids[i] = id;
            amounts[i] = _couponOwed[msg.sender][id];
            _couponOwed[msg.sender][id] = 0;
        }
        ICouponManager(couponManager).safeBatchTransferFrom(address(this), msg.sender, ids, amounts, data);
    }

    function burn(uint256 tokenId) external {
        require(_isApprovedOrOwner(msg.sender, tokenId), Errors.ACCESS);
        LoanPosition memory position = _positionMap[tokenId];
        require(position.debtAmount == 0, Errors.UNPAID_DEBT);
        uint256 collateralAmount = position.collateralAmount;
        position.collateralAmount = 0;

        _positionMap[tokenId] = position;
        emit PositionUpdated(tokenId, 0, 0, position.expiredWith);

        IAssetPool(assetPool).withdraw(position.collateralToken, collateralAmount, msg.sender);

        _burn(tokenId);
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function _getAndIncrementNonce(uint256 tokenId) internal override returns (uint256) {
        return _positionMap[tokenId].getAndIncrementNonce();
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC721Permit, ERC1155Receiver, IERC165) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _isPairUnregistered(address collateral, address debt) internal view returns (bool) {
        return _loanConfiguration[keccak256(abi.encodePacked(collateral, debt))].liquidationThreshold == 0;
    }
}
