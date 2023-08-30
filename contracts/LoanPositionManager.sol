// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IAssetPool} from "./interfaces/IAssetPool.sol";
import {ICouponOracle} from "./interfaces/ICouponOracle.sol";
import {ICouponManager} from "./interfaces/ICouponManager.sol";
import {IPositionManager} from "./interfaces/IPositionManager.sol";
import {ILoanPositionManager} from "./interfaces/ILoanPositionManager.sol";
import {CouponKey, CouponKeyLibrary} from "./libraries/CouponKey.sol";
import {Coupon, CouponLibrary} from "./libraries/Coupon.sol";
import {Epoch, EpochLibrary} from "./libraries/Epoch.sol";
import {LoanPosition, LoanPositionLibrary} from "./libraries/LoanPosition.sol";
import {PositionManager} from "./libraries/PositionManager.sol";

contract LoanPositionManager is ILoanPositionManager, PositionManager, Ownable {
    using LoanPositionLibrary for LoanPosition;
    using CouponKeyLibrary for CouponKey;
    using CouponLibrary for Coupon;
    using EpochLibrary for Epoch;

    uint256 private constant _RATE_PRECISION = 10 ** 6;

    address public immutable override oracle;
    address public immutable override treasury;
    uint256 public immutable override minDebtValueInEth;

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
    ) PositionManager(couponManager_, assetPool_, baseURI_, "Loan Position", "LP") {
        oracle = oracle_;
        treasury = treasury_;
        minDebtValueInEth = minDebtValueInEth_;
    }

    function getPosition(uint256 positionId) external view returns (LoanPosition memory) {
        return _positionMap[positionId];
    }

    function isPairRegistered(address collateral, address debt) external view returns (bool) {
        return !_isPairUnregistered(collateral, debt);
    }

    function getOwedCouponAmount(address user, uint256 couponId) external view returns (uint256) {
        return _couponOwed[user][couponId];
    }

    function getLoanConfiguration(address collateral, address debt) external view returns (LoanConfiguration memory) {
        return _loanConfiguration[_buildLoanPairId(collateral, debt)];
    }

    function mint(address collateralToken, address debtToken) external onlyByLocker returns (uint256 positionId) {
        if (_isPairUnregistered(collateralToken, debtToken)) revert InvalidPair();

        unchecked {
            positionId = nextId++;
        }
        _positionMap[positionId].collateralToken = collateralToken;
        _positionMap[positionId].debtToken = debtToken;

        _mint(msg.sender, positionId);
    }

    function adjustPosition(uint256 positionId, uint256 collateralAmount, uint256 debtAmount, Epoch expiredWith)
        external
        onlyByLocker
        modifyPosition(positionId)
        returns (Coupon[] memory couponsToBurn, Coupon[] memory couponsToMint, int256 collateralDelta, int256 debtDelta)
    {
        if (!_isApprovedOrOwner(msg.sender, positionId)) revert InvalidAccess();

        Epoch lastExpiredEpoch = EpochLibrary.lastExpiredEpoch();
        LoanPosition memory oldPosition = _positionMap[positionId];
        _positionMap[positionId].collateralAmount = collateralAmount;

        if (Epoch.wrap(0) < oldPosition.expiredWith && oldPosition.expiredWith <= lastExpiredEpoch) {
            // Only unexpired position can adjust debtAmount
            if (oldPosition.debtAmount != debtAmount) revert AlreadyExpired();
        } else {
            if (oldPosition.expiredWith == Epoch.wrap(0)) oldPosition.expiredWith = lastExpiredEpoch;
            _positionMap[positionId].debtAmount = debtAmount;
            _positionMap[positionId].expiredWith = debtAmount == 0 ? lastExpiredEpoch : expiredWith;

            (couponsToBurn, couponsToMint) = oldPosition.calculateCouponRequirement(_positionMap[positionId]);
        }

        unchecked {
            for (uint256 i = 0; i < couponsToMint.length; ++i) {
                _accountDelta(couponsToMint[i].id(), 0, couponsToMint[i].amount);
            }
            for (uint256 i = 0; i < couponsToBurn.length; ++i) {
                _accountDelta(couponsToBurn[i].id(), couponsToBurn[i].amount, 0);
            }
            collateralDelta = _accountDelta(
                uint256(uint160(oldPosition.collateralToken)), collateralAmount, oldPosition.collateralAmount
            );
            debtDelta = -_accountDelta(uint256(uint160(oldPosition.debtToken)), oldPosition.debtAmount, debtAmount);
        }
    }

    function settlePosition(uint256 positionId) public override(IPositionManager, PositionManager) onlyByLocker {
        super.settlePosition(positionId);
        LoanPosition memory position = _positionMap[positionId];

        if (position.debtAmount > 0 && position.expiredWith <= EpochLibrary.lastExpiredEpoch()) revert UnpaidDebt();

        LoanConfiguration memory loanConfig =
            _loanConfiguration[_buildLoanPairId(position.collateralToken, position.debtToken)];
        (
            uint256 collateralPriceWithPrecisionComplement,
            uint256 debtPriceWithPrecisionComplement,
            uint256 minDebtAmount
        ) = _calculatePricesAndMinDebtAmount(position.collateralToken, position.debtToken, loanConfig);

        if (position.debtAmount > 0 && minDebtAmount > position.debtAmount) revert TooSmallDebt();
        if (
            (position.collateralAmount * collateralPriceWithPrecisionComplement) * loanConfig.liquidationThreshold
                < position.debtAmount * debtPriceWithPrecisionComplement * _RATE_PRECISION
        ) revert LiquidationThreshold();

        if (position.debtAmount == 0 && position.collateralAmount == 0) _burn(positionId);

        emit UpdatePosition(positionId, position.collateralAmount, position.debtAmount, position.expiredWith);
    }

    function _buildLoanPairId(address collateral, address debt) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(collateral, debt));
    }

    function _calculatePricesAndMinDebtAmount(address collateral, address debt, LoanConfiguration memory loanConfig)
        private
        view
        returns (
            uint256 collateralPriceWithPrecisionComplement,
            uint256 debtPriceWithPrecisionComplement,
            uint256 minDebtAmount
        )
    {
        unchecked {
            uint256 collateralDecimal = loanConfig.collateralDecimal;
            uint256 debtDecimal = loanConfig.debtDecimal;

            address[] memory assets = new address[](3);
            assets[0] = collateral;
            assets[1] = debt;
            assets[2] = address(0);

            uint256[] memory prices = ICouponOracle(oracle).getAssetsPrices(assets);
            minDebtAmount = minDebtValueInEth * prices[2];
            collateralPriceWithPrecisionComplement = prices[0];
            debtPriceWithPrecisionComplement = prices[1];
            if (debtDecimal > 18) {
                minDebtAmount *= 10 ** (debtDecimal - 18);
            } else {
                minDebtAmount /= 10 ** (18 - debtDecimal);
            }
            minDebtAmount /= prices[1];
            if (debtDecimal > collateralDecimal) {
                collateralPriceWithPrecisionComplement *= 10 ** (debtDecimal - collateralDecimal);
            } else {
                debtPriceWithPrecisionComplement *= 10 ** (collateralDecimal - debtDecimal);
            }
        }
    }

    function _getLiquidationAmount(LoanPosition memory position, uint256 maxRepayAmount)
        private
        view
        returns (uint256 liquidationAmount, uint256 repayAmount, uint256 protocolFeeAmount)
    {
        unchecked {
            LoanConfiguration memory loanConfig =
                _loanConfiguration[_buildLoanPairId(position.collateralToken, position.debtToken)];
            (
                uint256 collateralPriceWithPrecisionComplement,
                uint256 debtPriceWithPrecisionComplement,
                uint256 minDebtAmount
            ) = _calculatePricesAndMinDebtAmount(position.collateralToken, position.debtToken, loanConfig);

            if (position.expiredWith.endTime() <= block.timestamp) {
                if (maxRepayAmount >= position.debtAmount) {
                    repayAmount = position.debtAmount;
                } else if (maxRepayAmount + minDebtAmount > position.debtAmount) {
                    if (position.debtAmount < minDebtAmount) revert TooSmallDebt();
                    repayAmount = position.debtAmount - minDebtAmount;
                } else {
                    repayAmount = maxRepayAmount;
                }

                liquidationAmount = Math.ceilDiv(
                    repayAmount * debtPriceWithPrecisionComplement * _RATE_PRECISION,
                    collateralPriceWithPrecisionComplement * (_RATE_PRECISION - loanConfig.liquidationFee)
                );
            } else {
                // Every 10^26 of collateralValue >= 1 USD, so it can't overflow.
                uint256 collateralValue = position.collateralAmount * collateralPriceWithPrecisionComplement;
                // Every 10^32 of debtValueMulRatePrecision >= 1 USD, so it can't overflow.
                uint256 debtValueMulRatePrecision =
                    position.debtAmount * debtPriceWithPrecisionComplement * _RATE_PRECISION;

                if (collateralValue * loanConfig.liquidationThreshold >= debtValueMulRatePrecision) return (0, 0, 0);

                liquidationAmount = Math.ceilDiv(
                    debtValueMulRatePrecision - collateralValue * loanConfig.liquidationTargetLtv,
                    collateralPriceWithPrecisionComplement
                        * (_RATE_PRECISION - loanConfig.liquidationFee - loanConfig.liquidationTargetLtv)
                );
                repayAmount = (
                    liquidationAmount * collateralPriceWithPrecisionComplement
                        * (_RATE_PRECISION - loanConfig.liquidationFee)
                ) / debtPriceWithPrecisionComplement / _RATE_PRECISION;

                // reuse newRepayAmount
                uint256 newRepayAmount = position.debtAmount;

                if (newRepayAmount <= minDebtAmount) {
                    if (maxRepayAmount < newRepayAmount) revert TooSmallDebt();
                } else if (repayAmount > newRepayAmount || newRepayAmount < minDebtAmount + repayAmount) {
                    if (maxRepayAmount < newRepayAmount) {
                        newRepayAmount = Math.min(maxRepayAmount, newRepayAmount - minDebtAmount);
                    }
                } else {
                    newRepayAmount = Math.min(maxRepayAmount, repayAmount);
                }

                if (newRepayAmount != repayAmount) {
                    liquidationAmount = Math.ceilDiv(
                        newRepayAmount * debtPriceWithPrecisionComplement * _RATE_PRECISION,
                        collateralPriceWithPrecisionComplement * (_RATE_PRECISION - loanConfig.liquidationFee)
                    );
                    repayAmount = newRepayAmount;
                }

                if (liquidationAmount > position.collateralAmount) liquidationAmount = position.collateralAmount;
            }
            protocolFeeAmount = (liquidationAmount * loanConfig.liquidationProtocolFee) / _RATE_PRECISION;
        }
    }

    function getLiquidationStatus(uint256 positionId, uint256 maxRepayAmount)
        external
        view
        returns (uint256, uint256, uint256)
    {
        return _getLiquidationAmount(_positionMap[positionId], maxRepayAmount > 0 ? maxRepayAmount : type(uint256).max);
    }

    // @dev We don't have to check the settlement of the position
    function liquidate(uint256 positionId, uint256 maxRepayAmount)
        external
        onlyByLocker
        returns (uint256 liquidationAmount, uint256 repayAmount, uint256 protocolFeeAmount)
    {
        if (!_isSettled(positionId)) revert NotSettled();
        unchecked {
            LoanPosition memory position = _positionMap[positionId];
            (liquidationAmount, repayAmount, protocolFeeAmount) =
                _getLiquidationAmount(position, maxRepayAmount > 0 ? maxRepayAmount : type(uint256).max);

            if (liquidationAmount == 0 && repayAmount == 0) revert UnableToLiquidate();

            Epoch currentEpoch = EpochLibrary.current();
            uint256 epochLength = position.expiredWith >= currentEpoch ? position.expiredWith.sub(currentEpoch) + 1 : 0;

            position.collateralAmount -= liquidationAmount;
            position.debtAmount -= repayAmount;
            if (position.debtAmount == 0) {
                position.expiredWith = currentEpoch.sub(1);
                _positionMap[positionId].expiredWith = position.expiredWith;
            }
            _positionMap[positionId].collateralAmount = position.collateralAmount;
            _positionMap[positionId].debtAmount = position.debtAmount;

            _accountDelta(uint256(uint160(position.collateralToken)), protocolFeeAmount, liquidationAmount);
            IAssetPool(assetPool).withdraw(position.collateralToken, protocolFeeAmount, treasury);
            _accountDelta(uint256(uint160(position.debtToken)), repayAmount, 0);

            if (epochLength > 0) {
                address couponOwner = ownerOf(positionId);
                Coupon[] memory coupons = new Coupon[](epochLength);
                for (uint256 i = 0; i < epochLength; ++i) {
                    coupons[i] = CouponLibrary.from(position.debtToken, currentEpoch.add(uint8(i)), repayAmount);
                }
                try ICouponManager(_couponManager).mintBatch(couponOwner, coupons, "") {}
                catch {
                    for (uint256 i = 0; i < epochLength; ++i) {
                        _couponOwed[couponOwner][coupons[i].id()] += coupons[i].amount;
                    }
                }
            }

            emit LiquidatePosition(positionId, msg.sender, liquidationAmount, repayAmount, protocolFeeAmount);
            emit UpdatePosition(positionId, position.collateralAmount, position.debtAmount, position.expiredWith);
        }
    }

    function claimOwedCoupons(CouponKey[] calldata couponKeys, bytes calldata data) external {
        unchecked {
            Coupon[] memory coupons = new Coupon[](couponKeys.length);
            for (uint256 i = 0; i < couponKeys.length; ++i) {
                uint256 id = couponKeys[i].toId();
                coupons[i] = Coupon(couponKeys[i], _couponOwed[msg.sender][id]);
                _couponOwed[msg.sender][id] = 0;
            }
            ICouponManager(_couponManager).mintBatch(msg.sender, coupons, data);
        }
    }

    function setLoanConfiguration(
        address collateral,
        address debt,
        uint32 liquidationThreshold,
        uint32 liquidationFee,
        uint32 liquidationProtocolFee,
        uint32 liquidationTargetLtv
    ) external onlyOwner {
        bytes32 pairId = _buildLoanPairId(collateral, debt);
        if (_loanConfiguration[pairId].liquidationThreshold > 0) revert InvalidPair();
        _loanConfiguration[pairId] = LoanConfiguration({
            collateralDecimal: IERC20Metadata(collateral).decimals(),
            debtDecimal: IERC20Metadata(debt).decimals(),
            liquidationThreshold: liquidationThreshold,
            liquidationFee: liquidationFee,
            liquidationProtocolFee: liquidationProtocolFee,
            liquidationTargetLtv: liquidationTargetLtv
        });
        emit SetLoanConfiguration(
            collateral, debt, liquidationThreshold, liquidationFee, liquidationProtocolFee, liquidationTargetLtv
        );
    }

    function nonces(uint256 positionId) external view returns (uint256) {
        return _positionMap[positionId].nonce;
    }

    function _getAndIncrementNonce(uint256 positionId) internal override returns (uint256) {
        return _positionMap[positionId].getAndIncrementNonce();
    }

    function _isPairUnregistered(address collateral, address debt) internal view returns (bool) {
        return _loanConfiguration[_buildLoanPairId(collateral, debt)].liquidationThreshold == 0;
    }

    function _isSettled(uint256 positionId) internal view override returns (bool) {
        return _positionMap[positionId].isSettled;
    }

    function _setPositionSettlement(uint256 positionId, bool settled) internal override {
        _positionMap[positionId].isSettled = settled;
    }
}
