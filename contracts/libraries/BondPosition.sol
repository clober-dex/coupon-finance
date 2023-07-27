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
    error UnmatchedPosition();

    using EpochLibrary for Epoch;

    function empty(address asset) internal pure returns (BondPosition memory position) {
        position = BondPosition({asset: asset, nonce: 0, expiredWith: EpochLibrary.wrap(0), amount: 0});
    }

    function from(address asset, Epoch expiredWith, uint256 amount)
        internal
        pure
        returns (BondPosition memory position)
    {
        position = BondPosition({asset: asset, nonce: 0, expiredWith: expiredWith, amount: amount});
    }

    function getAndIncrementNonce(BondPosition storage positionStorage) internal returns (uint64 nonce) {
        nonce = positionStorage.nonce++;
    }

    function calculateCouponRequirement(BondPosition memory oldPosition, BondPosition memory newPosition)
        internal
        view
        returns (Coupon[] memory, Coupon[] memory)
    {
        if (!(oldPosition.asset == newPosition.asset && oldPosition.nonce == newPosition.nonce)) {
            revert UnmatchedPosition();
        }

        Epoch latestExpiredEpoch = EpochLibrary.current().sub(1);
        uint256 mintCouponsLength = newPosition.expiredWith.sub(latestExpiredEpoch);
        uint256 burnCouponsLength = oldPosition.expiredWith.sub(latestExpiredEpoch);
        unchecked {
            uint256 minCount = Math.min(mintCouponsLength, burnCouponsLength);
            if (newPosition.amount > oldPosition.amount) {
                burnCouponsLength -= minCount;
            } else if (newPosition.amount < oldPosition.amount) {
                mintCouponsLength -= minCount;
            } else {
                mintCouponsLength -= minCount;
                burnCouponsLength -= minCount;
            }
        }

        Coupon[] memory mintCoupons = new Coupon[](mintCouponsLength);
        Coupon[] memory burnCoupons = new Coupon[](burnCouponsLength);
        mintCouponsLength = 0;
        burnCouponsLength = 0;
        uint16 farthestExpiredEpochs = newPosition.expiredWith.max(oldPosition.expiredWith).sub(latestExpiredEpoch);
        unchecked {
            for (uint16 i = 0; i < farthestExpiredEpochs; ++i) {
                latestExpiredEpoch = latestExpiredEpoch.add(1); // reuse latestExpiredEpoch as epoch
                uint256 newAmount = newPosition.expiredWith.compare(latestExpiredEpoch) < 0 ? 0 : newPosition.amount;
                uint256 oldAmount = oldPosition.expiredWith.compare(latestExpiredEpoch) < 0 ? 0 : oldPosition.amount;
                if (newAmount > oldAmount) {
                    mintCoupons[mintCouponsLength++] =
                        CouponLibrary.from(oldPosition.asset, latestExpiredEpoch, newAmount - oldAmount);
                } else if (newAmount < oldAmount) {
                    burnCoupons[burnCouponsLength++] =
                        CouponLibrary.from(oldPosition.asset, latestExpiredEpoch, oldAmount - newAmount);
                }
            }
        }
        return (mintCoupons, burnCoupons);
    }

    function compareEpoch(BondPosition memory position1, BondPosition memory position2)
        internal
        pure
        returns (int256)
    {
        return position1.expiredWith.compare(position2.expiredWith);
    }
}
