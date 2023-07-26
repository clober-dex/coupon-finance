// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {Coupon} from "../libraries/Coupon.sol";
import {BondPosition} from "../libraries/BondPosition.sol";

interface IBondPositionCallbackReceiver {
    function bondPositionAdjustCallback(
        uint256 tokenId,
        BondPosition memory oldPosition,
        BondPosition memory newPosition,
        Coupon[] memory couponsMinted,
        Coupon[] memory couponsToBurn,
        bytes calldata data
    ) external;
}
