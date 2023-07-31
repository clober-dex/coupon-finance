// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IBondPositionCallbackReceiver} from "./IBondPositionCallbackReceiver.sol";
import {PermitParams} from "../libraries/PermitParams.sol";
import {CouponKey} from "../libraries/CouponKey.sol";
import {Currency} from "../libraries/Currency.sol";

interface IDepositController is IBondPositionCallbackReceiver {
    function deposit(
        Currency currency,
        uint256 amount,
        uint16 lockEpochs,
        uint256 minInterestEarned,
        PermitParams calldata tokenPermitParams
    ) external payable returns (uint256);

    function withdraw(
        uint256 positionId,
        uint256 withdrawAmount,
        uint256 maxInterestPaid,
        PermitParams calldata positionPermitParams
    ) external;

    function collect(uint256 positionId, PermitParams calldata positionPermitParams) external;

    function getCouponMarket(CouponKey memory couponKey) external view returns (address);

    function setCouponMarket(CouponKey memory couponKey, address cloberMarket) external;
}
