// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Epoch, EpochLibrary} from "./Epoch.sol";
import {Coupon, CouponLibrary} from "./Coupon.sol";

struct LoanPosition {
    uint64 nonce;
    Epoch expiredWith;
    bool isSettled;
    address collateralToken;
    address debtToken;
    uint256 collateralAmount;
    uint256 debtAmount;
}

library LoanPositionLibrary {
    error UnmatchedPosition();
    error InvalidPositionEpoch();

    using EpochLibrary for Epoch;

    function getAndIncrementNonce(LoanPosition storage positionStorage) internal returns (uint64 nonce) {
        nonce = positionStorage.nonce++;
    }

    function calculateCouponRequirement(LoanPosition memory oldPosition, LoanPosition memory newPosition)
        internal
        view
        returns (Coupon[] memory, Coupon[] memory)
    {
        if (
            !(
                oldPosition.collateralToken == newPosition.collateralToken
                    && oldPosition.debtToken == newPosition.debtToken && oldPosition.nonce == newPosition.nonce
            )
        ) revert UnmatchedPosition();

        Epoch latestExpiredEpoch = EpochLibrary.lastExpiredEpoch();
        if (latestExpiredEpoch > newPosition.expiredWith || latestExpiredEpoch > oldPosition.expiredWith) {
            revert InvalidPositionEpoch();
        }

        uint256 burnCouponsLength = newPosition.expiredWith.sub(latestExpiredEpoch);
        uint256 mintCouponsLength = oldPosition.expiredWith.sub(latestExpiredEpoch);
        unchecked {
            uint256 minCount = Math.min(burnCouponsLength, mintCouponsLength);
            if (newPosition.debtAmount > oldPosition.debtAmount) {
                mintCouponsLength -= minCount;
            } else if (newPosition.debtAmount < oldPosition.debtAmount) {
                burnCouponsLength -= minCount;
            } else {
                burnCouponsLength -= minCount;
                mintCouponsLength -= minCount;
            }
        }

        Coupon[] memory burnCoupons = new Coupon[](burnCouponsLength);
        Coupon[] memory mintCoupons = new Coupon[](mintCouponsLength);
        burnCouponsLength = 0;
        mintCouponsLength = 0;
        uint256 farthestExpiredEpochs = newPosition.expiredWith.max(oldPosition.expiredWith).sub(latestExpiredEpoch);
        unchecked {
            Epoch epoch = latestExpiredEpoch;
            for (uint256 i = 0; i < farthestExpiredEpochs; ++i) {
                epoch = epoch.add(1);
                uint256 newAmount = newPosition.expiredWith < epoch ? 0 : newPosition.debtAmount;
                uint256 oldAmount = oldPosition.expiredWith < epoch ? 0 : oldPosition.debtAmount;
                if (newAmount > oldAmount) {
                    burnCoupons[burnCouponsLength++] =
                        CouponLibrary.from(oldPosition.debtToken, epoch, newAmount - oldAmount);
                } else if (newAmount < oldAmount) {
                    mintCoupons[mintCouponsLength++] =
                        CouponLibrary.from(oldPosition.debtToken, epoch, oldAmount - newAmount);
                }
            }
        }
        return (burnCoupons, mintCoupons);
    }
}
