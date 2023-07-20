// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Types} from "../Types.sol";
import {Errors} from "../Errors.sol";
import {Epoch} from "./Epoch.sol";
import {Coupon} from "./Coupon.sol";

library LoanPositionLibrary {
    using Epoch for Types.Epoch;

    function from(
        Types.Epoch expiredWith,
        address collateralToken,
        address debtToken,
        uint256 collateralAmount,
        uint256 debtAmount
    ) internal pure returns (Types.LoanPosition memory position) {
        position = Types.LoanPosition({
            nonce: 0,
            expiredWith: expiredWith,
            collateralToken: collateralToken,
            debtToken: debtToken,
            collateralAmount: collateralAmount,
            debtAmount: debtAmount
        });
    }

    function getAndIncrementNonce(Types.LoanPosition storage positionStorage) internal returns (uint64 nonce) {
        nonce = positionStorage.nonce++;
    }

    function adjustPosition(
        Types.LoanPosition memory position,
        uint256 collateralAmount,
        uint256 debtAmount,
        Types.Epoch expiredWith,
        Types.Epoch latestExpiredEpoch
    ) internal pure returns (Types.LoanPosition memory, Types.Coupon[] memory, Types.Coupon[] memory) {
        position = clone(position);
        position.collateralAmount = collateralAmount;
        if (debtAmount == 0) {
            expiredWith = latestExpiredEpoch;
        } else {
            if (latestExpiredEpoch.compare(expiredWith) >= 0) {
                revert(Errors.UNPAID_DEBT);
            }
        }

        (uint256 payCouponsLength, uint256 refundCouponsLength) = _calculateCouponCount(
            position,
            debtAmount,
            expiredWith,
            latestExpiredEpoch
        );
        Types.Coupon[] memory payCoupons = new Types.Coupon[](payCouponsLength);
        Types.Coupon[] memory refundCoupons = new Types.Coupon[](refundCouponsLength);
        payCouponsLength = 0;
        refundCouponsLength = 0;
        uint16 farthestExpiredEpochs = expiredWith.max(position.expiredWith).sub(latestExpiredEpoch);
        // reuse collateralAmount as i
        for (collateralAmount = 0; collateralAmount < farthestExpiredEpochs; ++collateralAmount) {
            latestExpiredEpoch = latestExpiredEpoch.add(1); // reuse minEpoch as epoch
            (uint256 payAmount, uint256 refundAmount) = _calculateCouponAmount(
                position,
                debtAmount,
                expiredWith,
                latestExpiredEpoch
            );
            if (payAmount > 0) {
                payCoupons[payCouponsLength++] = Coupon.from(position.debtToken, latestExpiredEpoch, payAmount);
            }
            if (refundAmount > 0) {
                refundCoupons[refundCouponsLength++] = Coupon.from(
                    position.debtToken,
                    latestExpiredEpoch,
                    refundAmount
                );
            }
        }
        position.debtAmount = debtAmount;
        position.expiredWith = expiredWith;
        return (position, payCoupons, refundCoupons);
    }

    function _calculateCouponCount(
        Types.LoanPosition memory position,
        uint256 amount,
        Types.Epoch expiredWith,
        Types.Epoch latestExpiredEpoch
    ) private pure returns (uint256 payCount, uint256 refundCount) {
        payCount = expiredWith.sub(latestExpiredEpoch);
        refundCount = position.expiredWith.sub(latestExpiredEpoch);
        unchecked {
            uint256 minCount = Math.min(payCount, refundCount);
            if (amount > position.debtAmount) {
                refundCount -= minCount;
            } else if (amount < position.debtAmount) {
                payCount -= minCount;
            } else {
                payCount -= minCount;
                refundCount -= minCount;
            }
        }
    }

    function _calculateCouponAmount(
        Types.LoanPosition memory position,
        uint256 amount,
        Types.Epoch expiredWith,
        Types.Epoch epoch
    ) private pure returns (uint256 payAmount, uint256 refundAmount) {
        uint256 newAmount = expiredWith.compare(epoch) < 0 ? 0 : amount;
        uint256 oldAmount = position.expiredWith.compare(epoch) < 0 ? 0 : position.debtAmount;
        if (newAmount > oldAmount) {
            payAmount = newAmount - oldAmount;
        } else if (newAmount < oldAmount) {
            refundAmount = oldAmount - newAmount;
        }
    }

    function clone(Types.LoanPosition memory position) internal pure returns (Types.LoanPosition memory) {
        return
            Types.LoanPosition({
                nonce: position.nonce,
                expiredWith: position.expiredWith,
                collateralToken: position.collateralToken,
                debtToken: position.debtToken,
                collateralAmount: position.collateralAmount,
                debtAmount: position.debtAmount
            });
    }

    function compareEpoch(
        Types.LoanPosition memory position1,
        Types.LoanPosition memory position2
    ) internal pure returns (int256) {
        return position1.expiredWith.compare(position2.expiredWith);
    }
}
