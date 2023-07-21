// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Errors} from "../Errors.sol";
import {Epoch, EpochLibrary} from "./Epoch.sol";
import {Coupon, CouponLibrary} from "./Coupon.sol";

struct LoanPosition {
    uint64 nonce;
    Epoch expiredWith;
    address collateralToken;
    address debtToken;
    uint256 collateralAmount;
    uint256 debtAmount;
}

library LoanPositionLibrary {
    using EpochLibrary for Epoch;

    function empty(address collateralToken, address debtToken) internal pure returns (LoanPosition memory position) {
        position = LoanPosition({
            nonce: 0,
            expiredWith: EpochLibrary.wrap(0),
            collateralToken: collateralToken,
            debtToken: debtToken,
            collateralAmount: 0,
            debtAmount: 0
        });
    }

    function from(
        Epoch expiredWith,
        address collateralToken,
        address debtToken,
        uint256 collateralAmount,
        uint256 debtAmount
    ) internal pure returns (LoanPosition memory position) {
        position = LoanPosition({
            nonce: 0,
            expiredWith: expiredWith,
            collateralToken: collateralToken,
            debtToken: debtToken,
            collateralAmount: collateralAmount,
            debtAmount: debtAmount
        });
    }

    function getAndIncrementNonce(LoanPosition storage positionStorage) internal returns (uint64 nonce) {
        nonce = positionStorage.nonce++;
    }

    function calculateCouponRequirement(
        LoanPosition memory oldPosition,
        LoanPosition memory newPosition
    ) internal view returns (Coupon[] memory, Coupon[] memory) {
        require(
            oldPosition.collateralToken == newPosition.collateralToken &&
                oldPosition.debtToken == newPosition.debtToken &&
                oldPosition.nonce == newPosition.nonce,
            Errors.INVALID_INPUT
        );

        Epoch latestExpiredEpoch = EpochLibrary.current().sub(1);
        uint256 payCouponsLength = newPosition.expiredWith.sub(latestExpiredEpoch);
        uint256 refundCouponsLength = oldPosition.expiredWith.sub(latestExpiredEpoch);
        unchecked {
            uint256 minCount = Math.min(payCouponsLength, refundCouponsLength);
            if (newPosition.debtAmount > oldPosition.debtAmount) {
                refundCouponsLength -= minCount;
            } else if (newPosition.debtAmount < oldPosition.debtAmount) {
                payCouponsLength -= minCount;
            } else {
                payCouponsLength -= minCount;
                refundCouponsLength -= minCount;
            }
        }

        Coupon[] memory payCoupons = new Coupon[](payCouponsLength);
        Coupon[] memory refundCoupons = new Coupon[](refundCouponsLength);
        payCouponsLength = 0;
        refundCouponsLength = 0;
        uint256 farthestExpiredEpochs = newPosition.expiredWith.max(oldPosition.expiredWith).sub(latestExpiredEpoch);
        unchecked {
            for (uint256 i = 0; i < farthestExpiredEpochs; ++i) {
                latestExpiredEpoch = latestExpiredEpoch.add(1); // reuse minEpoch as latestExpiredEpoch
                uint256 newAmount = newPosition.expiredWith.compare(latestExpiredEpoch) < 0
                    ? 0
                    : newPosition.debtAmount;
                uint256 oldAmount = oldPosition.expiredWith.compare(latestExpiredEpoch) < 0
                    ? 0
                    : oldPosition.debtAmount;
                if (newAmount > oldAmount) {
                    payCoupons[payCouponsLength++] = CouponLibrary.from(
                        oldPosition.debtToken,
                        latestExpiredEpoch,
                        newAmount - oldAmount
                    );
                } else if (newAmount < oldAmount) {
                    refundCoupons[refundCouponsLength++] = CouponLibrary.from(
                        oldPosition.debtToken,
                        latestExpiredEpoch,
                        oldAmount - newAmount
                    );
                }
            }
        }
        return (payCoupons, refundCoupons);
    }

    function compareEpoch(LoanPosition memory position1, LoanPosition memory position2) internal pure returns (int256) {
        return position1.expiredWith.compare(position2.expiredWith);
    }
}
