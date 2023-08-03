// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ERC1155Holder, ERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {IAssetPool} from "./interfaces/IAssetPool.sol";
import {ILiquidateCallbackReceiver} from "./interfaces/ILiquidateCallbackReceiver.sol";
import {ILoanPositionCallbackReceiver} from "./interfaces/ILoanPositionCallbackReceiver.sol";
import {ICouponOracle} from "./interfaces/ICouponOracle.sol";
import {ICouponManager} from "./interfaces/ICouponManager.sol";
import {ILoanPositionManager} from "./interfaces/ILoanPositionManager.sol";
import {ERC721Permit, IERC165} from "./libraries/ERC721Permit.sol";
import {ReentrancyGuard} from "./libraries/ReentrancyGuard.sol";
import {CouponKey, CouponKeyLibrary} from "./libraries/CouponKey.sol";
import {Coupon, CouponLibrary} from "./libraries/Coupon.sol";
import {LockData, LockDataLibrary} from "./libraries/LockData.sol";
import {Epoch, EpochLibrary} from "./libraries/Epoch.sol";
import {LoanPosition, LoanPositionLibrary} from "./libraries/LoanPosition.sol";

contract LoanPositionManager is ILoanPositionManager, ERC721Permit, Ownable, ERC1155Holder {
    using SafeCast for uint256;
    using SafeERC20 for IERC20;
    using Strings for uint256;
    using LoanPositionLibrary for LoanPosition;
    using CouponKeyLibrary for CouponKey;
    using CouponLibrary for Coupon;
    using EpochLibrary for Epoch;
    using LockDataLibrary for LockData;

    uint256 private constant _RATE_PRECISION = 10 ** 6;

    address private immutable _couponManager;
    address public immutable override assetPool;
    address public immutable override oracle;
    address public immutable override treasury;
    uint256 public immutable override minDebtValueInEth;

    string public override baseURI;
    uint256 public override nextId = 1;

    mapping(address user => mapping(uint256 couponId => uint256)) private _couponOwed;
    mapping(bytes32 => LoanConfiguration) private _loanConfiguration;
    mapping(uint256 id => LoanPosition) private _positionMap;

    LockData public override lockData;

    mapping(address locker => mapping(uint256 assetId => int256 delta)) public override assetDelta;
    mapping(uint256 positionId => bool) public override unsettledPosition;

    constructor(
        address couponManager_,
        address assetPool_,
        address oracle_,
        address treasury_,
        uint256 minDebtValueInEth_,
        string memory baseURI_
    ) ERC721Permit("Loan Position", "LP", "1") {
        _couponManager = couponManager_;
        assetPool = assetPool_;
        oracle = oracle_;
        baseURI = baseURI_;
        treasury = treasury_;
        minDebtValueInEth = minDebtValueInEth_;
    }

    modifier onlyByLocker() {
        address locker = lockData.getActiveLock();
        if (msg.sender != locker) revert LockedBy(locker);
        _;
    }

    function getPosition(uint256 tokenId) external view returns (LoanPosition memory) {
        return _positionMap[tokenId];
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

    function lock(bytes calldata data) external returns (bytes memory result) {
        lockData.push(msg.sender);

        result = ILoanPositionLocker(msg.sender).lockAcquired(data);

        if (lockData.length == 1) {
            if (lockData.nonzeroDeltaCount != 0) revert NotSettled();
            delete lockData;
        } else {
            lockData.pop();
        }
    }

    function _markUnsettled(uint256 positionId) internal {
        if (unsettledPosition[positionId]) return;
        unsettledPosition[positionId] = true;
        unchecked {
            lockData.nonzeroDeltaCount++;
        }
    }

    function _markSettled(uint256 positionId) internal {
        if (!unsettledPosition[positionId]) return;
        delete unsettledPosition[positionId];
        unchecked {
            lockData.nonzeroDeltaCount--;
        }
    }

    function _accountDelta(uint256 assetId, int256 delta) internal {
        if (delta == 0) return;

        address locker = lockData.getActiveLock();
        int256 current = assetDelta[locker][assetId];
        int256 next = current + delta;

        unchecked {
            if (next == 0) {
                lockData.nonzeroDeltaCount--;
            } else if (current == 0) {
                lockData.nonzeroDeltaCount++;
            }
        }

        assetDelta[locker][assetId] = next;
    }

    function mint(address collateralToken, address debtToken) external onlyByLocker returns (uint256 positionId) {
        if (_isPairUnregistered(collateralToken, debtToken)) {
            revert InvalidPair();
        }

        _positionMap[(positionId = nextId++)] = LoanPositionLibrary.empty(collateralToken, debtToken);

        _mint(msg.sender, positionId);
        _markUnsettled(positionId);
    }

    function adjustPosition(uint256 positionId, uint256 collateralAmount, uint256 debtAmount, Epoch expiredWith)
        external
        onlyByLocker
        returns (
            Coupon[] memory couponsToPay,
            Coupon[] memory couponsToRefund,
            int256 collateralDelta,
            int256 debtDelta
        )
    {
        if (!_isApprovedOrOwner(msg.sender, positionId)) revert InvalidAccess();
        _markUnsettled(positionId);

        Epoch lastExpiredEpoch = EpochLibrary.lastExpiredEpoch();
        LoanPosition memory oldPosition = _positionMap[positionId];
        _positionMap[positionId].collateralAmount = collateralAmount;

        if (Epoch.wrap(0) < oldPosition.expiredWith && oldPosition.expiredWith <= lastExpiredEpoch) {
            // Only unexpired position can adjust debtAmount
            if (oldPosition.debtAmount != debtAmount) revert AlreadyExpired();
        } else {
            if (oldPosition.expiredWith == Epoch.wrap(0)) {
                oldPosition.expiredWith = lastExpiredEpoch;
            }
            _positionMap[positionId].debtAmount = debtAmount;
            _positionMap[positionId].expiredWith = debtAmount == 0 ? lastExpiredEpoch : expiredWith;

            (couponsToPay, couponsToRefund) = oldPosition.calculateCouponRequirement(_positionMap[positionId]);
        }

        unchecked {
            if (couponsToRefund.length > 0) {
                for (uint256 i = 0; i < couponsToRefund.length; ++i) {
                    _accountDelta(couponsToRefund[i].id(), -couponsToRefund[i].amount.toInt256());
                }
            }
            if (debtAmount > oldPosition.debtAmount) {
                debtDelta = (debtAmount - oldPosition.debtAmount).toInt256();
                _accountDelta(uint256(uint160(oldPosition.debtToken)), -debtDelta);
            }
            if (collateralAmount < oldPosition.collateralAmount) {
                collateralDelta = -(oldPosition.collateralAmount - collateralAmount).toInt256();
                _accountDelta(uint256(uint160(oldPosition.collateralToken)), collateralDelta);
            }
            if (debtAmount < oldPosition.debtAmount) {
                debtDelta = -(oldPosition.debtAmount - debtAmount).toInt256();
                _accountDelta(uint256(uint160(oldPosition.debtToken)), -debtDelta);
            }
            if (collateralAmount > oldPosition.collateralAmount) {
                collateralDelta = (collateralAmount - oldPosition.collateralAmount).toInt256();
                _accountDelta(uint256(uint160(oldPosition.collateralToken)), collateralDelta);
            }
            if (couponsToPay.length > 0) {
                for (uint256 i = 0; i < couponsToPay.length; ++i) {
                    _accountDelta(couponsToPay[i].id(), couponsToPay[i].amount.toInt256());
                }
            }
        }
    }

    function settlePosition(uint256 positionId) external onlyByLocker {
        if (!_isApprovedOrOwner(msg.sender, positionId)) revert InvalidAccess();
        LoanPosition memory position = _positionMap[positionId];

        // todo: check if this statement is necessary, this already checked in adjustPosition
        if (position.debtAmount > 0 && position.expiredWith <= EpochLibrary.lastExpiredEpoch()) {
            revert UnpaidDebt();
        }

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

        _markSettled(positionId);

        if (position.debtAmount == 0 && position.collateralAmount == 0) {
            _burn(positionId);
        }

        emit PositionUpdated(positionId, position.collateralAmount, position.debtAmount, position.expiredWith);
    }

    function withdrawToken(address token, address to, uint256 amount) external onlyByLocker {
        _accountDelta(uint256(uint160(token)), amount.toInt256());
        IAssetPool(assetPool).withdraw(token, amount, to);
    }

    function withdrawCoupons(Coupon[] calldata coupons, address to, bytes calldata data) external onlyByLocker {
        unchecked {
            for (uint256 i = 0; i < coupons.length; ++i) {
                _accountDelta(coupons[i].id(), coupons[i].amount.toInt256());
            }
            ICouponManager(_couponManager).safeBatchTransferFrom(address(this), to, coupons, data);
        }
    }

    function depositToken(address token, uint256 amount) external onlyByLocker {
        if (amount == 0) return;
        IERC20(token).safeTransferFrom(msg.sender, assetPool, amount);
        IAssetPool(assetPool).deposit(token, amount);
        _accountDelta(uint256(uint160(token)), -amount.toInt256());
    }

    function depositCoupons(Coupon[] calldata coupons) external onlyByLocker {
        unchecked {
            ICouponManager(_couponManager).safeBatchTransferFrom(msg.sender, address(this), coupons, "");
            for (uint256 i = 0; i < coupons.length; ++i) {
                _accountDelta(coupons[i].id(), -coupons[i].amount.toInt256());
            }
        }
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
            // @dev `decimal` is always less than or equal to 18
            minDebtAmount = (minDebtValueInEth * prices[2]) / 10 ** (18 - debtDecimal) / prices[1];
            if (debtDecimal > collateralDecimal) {
                collateralPriceWithPrecisionComplement = prices[0] * 10 ** (debtDecimal - collateralDecimal);
                debtPriceWithPrecisionComplement = prices[1];
            } else {
                collateralPriceWithPrecisionComplement = prices[0];
                debtPriceWithPrecisionComplement = prices[1] * 10 ** (collateralDecimal - debtDecimal);
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

            if (position.expiredWith.isExpired()) {
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

                if (collateralValue * loanConfig.liquidationThreshold >= debtValueMulRatePrecision) {
                    return (0, 0, 0);
                }

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

    function getLiquidationStatus(uint256 tokenId, uint256 maxRepayAmount)
        external
        view
        returns (LiquidationStatus memory)
    {
        (uint256 liquidationAmount, uint256 repayAmount, uint256 protocolFeeAmount) =
            _getLiquidationAmount(_positionMap[tokenId], maxRepayAmount > 0 ? maxRepayAmount : type(uint256).max);
        return LiquidationStatus({
            liquidationAmount: liquidationAmount,
            repayAmount: repayAmount,
            protocolFeeAmount: protocolFeeAmount
        });
    }

    function liquidate(uint256 tokenId, uint256 maxRepayAmount, bytes calldata data) external {
        unchecked {
            LoanPosition memory position = _positionMap[tokenId];
            (uint256 liquidationAmount, uint256 repayAmount, uint256 protocolFeeAmount) =
                _getLiquidationAmount(position, maxRepayAmount > 0 ? maxRepayAmount : type(uint256).max);

            if (liquidationAmount == 0 && repayAmount == 0) revert UnableToLiquidate();

            Epoch currentEpoch = EpochLibrary.current();
            uint256 validEpochLength;
            if (position.expiredWith >= currentEpoch) {
                validEpochLength = position.expiredWith.sub(currentEpoch) + 1;
            }

            position.collateralAmount -= liquidationAmount;
            position.debtAmount -= repayAmount;
            if (position.debtAmount == 0) {
                position.expiredWith = currentEpoch.sub(1);
                _positionMap[tokenId].expiredWith = position.expiredWith;
            }
            _positionMap[tokenId].collateralAmount = position.collateralAmount;
            _positionMap[tokenId].debtAmount = position.debtAmount;

            IAssetPool(assetPool).withdraw(position.collateralToken, liquidationAmount - protocolFeeAmount, msg.sender);
            IAssetPool(assetPool).withdraw(position.collateralToken, protocolFeeAmount, treasury);

            if (validEpochLength > 0) {
                address couponOwner = ownerOf(tokenId);
                Coupon[] memory coupons = new Coupon[](validEpochLength);
                for (uint256 i = 0; i < validEpochLength; ++i) {
                    coupons[i] = CouponLibrary.from(position.debtToken, currentEpoch.add(uint8(i)), repayAmount);
                }
                try ICouponManager(_couponManager).safeBatchTransferFrom(address(this), couponOwner, coupons, data) {}
                catch {
                    for (uint256 i = 0; i < validEpochLength; ++i) {
                        _couponOwed[couponOwner][coupons[i].id()] += coupons[i].amount;
                    }
                }
            }

            if (data.length > 0) {
                ILiquidateCallbackReceiver(msg.sender).couponFinanceLiquidateCallback(
                    tokenId,
                    position.collateralToken,
                    position.debtToken,
                    liquidationAmount - protocolFeeAmount,
                    repayAmount,
                    data
                );
            }
            IERC20(position.debtToken).safeTransferFrom(msg.sender, assetPool, repayAmount);
            IAssetPool(assetPool).deposit(position.debtToken, repayAmount);

            emit PositionLiquidated(tokenId);
            emit PositionUpdated(tokenId, position.collateralAmount, position.debtAmount, position.expiredWith);
        }
    }

    function claimOwedCoupons(CouponKey[] memory couponKeys, bytes calldata data) external {
        unchecked {
            uint256 length = couponKeys.length;
            uint256[] memory ids = new uint256[](length);
            uint256[] memory amounts = new uint256[](length);
            for (uint256 i = 0; i < length; ++i) {
                uint256 id = couponKeys[i].toId();
                ids[i] = id;
                amounts[i] = _couponOwed[msg.sender][id];
                _couponOwed[msg.sender][id] = 0;
            }
            ICouponManager(_couponManager).safeBatchTransferFrom(address(this), msg.sender, ids, amounts, data);
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
        bytes32 hash = _buildLoanPairId(collateral, debt);
        if (_loanConfiguration[hash].liquidationThreshold > 0) revert InvalidPair();
        _loanConfiguration[hash] = LoanConfiguration({
            collateralDecimal: IERC20Metadata(collateral).decimals(),
            debtDecimal: IERC20Metadata(debt).decimals(),
            liquidationThreshold: liquidationThreshold,
            liquidationFee: liquidationFee,
            liquidationProtocolFee: liquidationProtocolFee,
            liquidationTargetLtv: liquidationTargetLtv
        });
    }

    function nonces(uint256 tokenId) external view returns (uint256) {
        return _positionMap[tokenId].nonce;
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function _getAndIncrementNonce(uint256 tokenId) internal override returns (uint256) {
        return _positionMap[tokenId].getAndIncrementNonce();
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721Permit, ERC1155Receiver, IERC165)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _isPairUnregistered(address collateral, address debt) internal view returns (bool) {
        return _loanConfiguration[_buildLoanPairId(collateral, debt)].liquidationThreshold == 0;
    }
}

interface ILoanPositionLocker {
    function lockAcquired(bytes calldata data) external returns (bytes memory);
}
