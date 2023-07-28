// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {IDepositController} from "./interfaces/IDepositController.sol";
import {IBondPositionManager} from "./interfaces/IBondPositionManager.sol";
import {BondPosition} from "./libraries/BondPosition.sol";
import {Coupon} from "./libraries/Coupon.sol";
import {PermitParams} from "./libraries/PermitParams.sol";
import {Currency, CurrencyLibrary} from "./libraries/Currency.sol";
import {Controller} from "./libraries/Controller.sol";

contract DepositController is IDepositController, Controller {
    using CurrencyLibrary for Currency;

    IBondPositionManager private immutable _bondManager;

    constructor(
        address wrapped1155Factory,
        address cloberMarketFactory,
        address couponManager,
        address weth,
        address bondManager
    ) Controller(wrapped1155Factory, cloberMarketFactory, couponManager, weth) {
        _bondManager = IBondPositionManager(bondManager);
    }

    function deposit(
        Currency currency,
        uint256 amount,
        uint16 lockEpochs,
        uint256 minInterestEarned,
        PermitParams calldata tokenPermitParams
    ) external payable returns (uint256 positionId) {}

    function withdraw(
        uint256 positionId,
        uint256 withdrawAmount,
        uint256 maxInterestPaid,
        PermitParams calldata positionPermitParams
    ) external {}

    function collect(uint256 positionId, PermitParams calldata positionPermitParams) external {}

    function bondPositionAdjustCallback(
        uint256,
        BondPosition memory oldPosition,
        BondPosition memory newPosition,
        Coupon[] memory couponsMinted,
        Coupon[] memory couponsToBurn,
        bytes calldata data
    ) external {}
}
