// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Epoch, EpochLibrary} from "./Epoch.sol";
import {Coupon, CouponLibrary} from "./Coupon.sol";

struct BondPosition {
    address asset;
    uint64 nonce;
    Epoch expiredWith;
    uint256 amount;
}

library BondPositionLibrary {
    using EpochLibrary for Epoch;

    function from(
        address asset,
        Epoch expiredWith,
        uint256 amount
    ) internal pure returns (BondPosition memory position) {
        position = BondPosition({asset: asset, nonce: 0, expiredWith: expiredWith, amount: amount});
    }

    function getAndIncrementNonce(BondPosition storage positionStorage) internal returns (uint64 nonce) {
        nonce = positionStorage.nonce++;
    }

    function adjustPosition(
        BondPosition memory position,
        uint256 amount,
        Epoch expiredWith,
        Epoch latestExpiredEpoch
    ) internal pure returns (BondPosition memory, Coupon[] memory, Coupon[] memory) {
        position = clone(position);
        if (amount == 0) {
            expiredWith = latestExpiredEpoch;
        } else {
            if (latestExpiredEpoch.compare(expiredWith) >= 0) {
                expiredWith = latestExpiredEpoch;
            }
        }

        (uint256 mintCouponsLength, uint256 burnCouponsLength) = _calculateCouponCount(
            position,
            amount,
            expiredWith,
            latestExpiredEpoch
        );
        Coupon[] memory mintCoupons = new Coupon[](mintCouponsLength);
        Coupon[] memory burnCoupons = new Coupon[](burnCouponsLength);
        mintCouponsLength = 0;
        burnCouponsLength = 0;
        uint16 farthestExpiredEpochs = expiredWith.max(position.expiredWith).sub(latestExpiredEpoch);
        for (uint16 i = 0; i < farthestExpiredEpochs; ++i) {
            latestExpiredEpoch = latestExpiredEpoch.add(1); // reuse minEpoch as epoch
            (uint256 mintAmount, uint256 burnAmount) = _calculateCouponAmount(
                position,
                amount,
                expiredWith,
                latestExpiredEpoch
            );
            if (mintAmount > 0) {
                mintCoupons[mintCouponsLength++] = CouponLibrary.from(position.asset, latestExpiredEpoch, mintAmount);
            }
            if (burnAmount > 0) {
                burnCoupons[burnCouponsLength++] = CouponLibrary.from(position.asset, latestExpiredEpoch, burnAmount);
            }
        }
        position.amount = amount;
        position.expiredWith = expiredWith;
        return (position, mintCoupons, burnCoupons);
    }

    function _calculateCouponCount(
        BondPosition memory position,
        uint256 amount,
        Epoch expiredWith,
        Epoch latestExpiredEpoch
    ) private pure returns (uint256 mintCount, uint256 burnCount) {
        mintCount = expiredWith.sub(latestExpiredEpoch);
        burnCount = position.expiredWith.sub(latestExpiredEpoch);
        unchecked {
            uint256 minCount = Math.min(mintCount, burnCount);
            if (amount > position.amount) {
                burnCount -= minCount;
            } else if (amount < position.amount) {
                mintCount -= minCount;
            } else {
                mintCount -= minCount;
                burnCount -= minCount;
            }
        }
    }

    function _calculateCouponAmount(
        BondPosition memory position,
        uint256 amount,
        Epoch expiredWith,
        Epoch epoch
    ) private pure returns (uint256 mintAmount, uint256 burnAmount) {
        uint256 newAmount = expiredWith.compare(epoch) < 0 ? 0 : amount;
        uint256 oldAmount = position.expiredWith.compare(epoch) < 0 ? 0 : position.amount;
        if (newAmount > oldAmount) {
            mintAmount = newAmount - oldAmount;
        } else if (newAmount < oldAmount) {
            burnAmount = oldAmount - newAmount;
        }
    }

    function clone(BondPosition memory position) internal pure returns (BondPosition memory) {
        return
            BondPosition({
                asset: position.asset,
                nonce: position.nonce,
                expiredWith: position.expiredWith,
                amount: position.amount
            });
    }

    function compareEpoch(BondPosition memory position1, BondPosition memory position2) internal pure returns (int256) {
        return position1.expiredWith.compare(position2.expiredWith);
    }
}
