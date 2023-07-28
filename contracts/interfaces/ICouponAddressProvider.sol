// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {CouponKey} from "../libraries/CouponKey.sol";

interface ICouponAddressProvider {
    function markets(CouponKey memory couponKey) external view returns (address);

    function wrappedTokens(CouponKey memory couponKey) external view returns (address);
}
