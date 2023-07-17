// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {Types} from "../Types.sol";
import {CouponKey} from "./CouponKey.sol";

library Coupon {
    using CouponKey for Types.CouponKey;

    function from(address asset, uint16 epoch, uint256 amount) internal pure returns (Types.Coupon memory) {
        return Types.Coupon({key: Types.CouponKey({asset: asset, epoch: Types.Epoch.wrap(epoch)}), amount: amount});
    }

    function from(address asset, Types.Epoch epoch, uint256 amount) internal pure returns (Types.Coupon memory) {
        return Types.Coupon({key: Types.CouponKey({asset: asset, epoch: epoch}), amount: amount});
    }

    function from(Types.CouponKey memory couponKey, uint256 amount) internal pure returns (Types.Coupon memory) {
        return Types.Coupon({key: couponKey, amount: amount});
    }

    function id(Types.Coupon memory coupon) internal pure returns (uint256) {
        return coupon.key.toId();
    }
}
