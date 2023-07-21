// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Types} from "../Types.sol";
import {Errors} from "../Errors.sol";
import {EpochLibrary} from "./Epoch.sol";
import {CouponLibrary} from "./Coupon.sol";

library LoanPositionLibrary {
    using EpochLibrary for Types.Epoch;

    function empty(
        address collateralToken,
        address debtToken
    ) internal pure returns (Types.LoanPosition memory position) {
        position = Types.LoanPosition({
            nonce: 0,
            expiredWith: EpochLibrary.wrap(0),
            collateralToken: collateralToken,
            debtToken: debtToken,
            collateralAmount: 0,
            debtAmount: 0
        });
    }

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

    function calculateCouponRequirement(
        Types.LoanPosition memory oldPosition,
        Types.LoanPosition memory newPosition
    ) internal view returns (Types.Coupon[] memory, Types.Coupon[] memory) {
        require(
            oldPosition.collateralToken == newPosition.collateralToken &&
                oldPosition.debtToken == newPosition.debtToken &&
                oldPosition.nonce == newPosition.nonce,
            Errors.INVALID_INPUT
        );

        Types.Epoch latestExpiredEpoch = EpochLibrary.current().sub(1);
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

        Types.Coupon[] memory payCoupons = new Types.Coupon[](payCouponsLength);
        Types.Coupon[] memory refundCoupons = new Types.Coupon[](refundCouponsLength);
        payCouponsLength = 0;
        refundCouponsLength = 0;
        uint256 farthestExpiredEpochs = newPosition.expiredWith.max(oldPosition.expiredWith).sub(latestExpiredEpoch);
        unchecked {
            for (uint256 i = 0; i < farthestExpiredEpochs; ++i) {
                latestExpiredEpoch = latestExpiredEpoch.add(1); // reuse minEpoch as epoch
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

    function compareEpoch(
        Types.LoanPosition memory position1,
        Types.LoanPosition memory position2
    ) internal pure returns (int256) {
        return position1.expiredWith.compare(position2.expiredWith);
    }
}
