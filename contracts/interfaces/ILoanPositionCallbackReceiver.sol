// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {Coupon} from "../libraries/Coupon.sol";
import {LoanPosition} from "../libraries/LoanPosition.sol";

interface ILoanPositionCallbackReceiver {
    function loanPositionAdjustCallback(
        uint256 tokenId,
        LoanPosition memory oldPosition,
        LoanPosition memory newPosition,
        Coupon[] memory couponsToPay,
        Coupon[] memory couponsRefunded,
        bytes calldata data
    ) external;
}
