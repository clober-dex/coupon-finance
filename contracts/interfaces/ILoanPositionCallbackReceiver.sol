// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {Types} from "../Types.sol";

interface ILoanPositionCallbackReceiver {
    function loanPositionAdjustCallback(
        uint256 tokenId,
        Types.LoanPosition memory position,
        int256 collateralPositionChange,
        int256 debtPositionChange,
        Types.Coupon[] memory couponsMinted,
        Types.Coupon[] memory couponsToBurn,
        bytes calldata data
    ) external;
}
