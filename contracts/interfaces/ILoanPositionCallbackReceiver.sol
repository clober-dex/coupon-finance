// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {Types} from "../Types.sol";

interface ILoanPositionCallbackReceiver {
    function loanPositionAdjustCallback(
        uint256 tokenId,
        Types.LoanPosition memory oldPosition,
        Types.LoanPosition memory newPosition,
        Types.Coupon[] memory couponsToPay,
        Types.Coupon[] memory couponsRefunded,
        bytes calldata data
    ) external;
}
