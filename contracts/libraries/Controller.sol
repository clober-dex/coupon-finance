// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {CloberMarketFactory} from "../external/clober/CloberMarketFactory.sol";
import {IWETH9} from "../external/weth/IWETH9.sol";
import {IWrapped1155Factory} from "../external/wrapped1155/IWrapped1155Factory.sol";
import {ICouponManager} from "../interfaces/ICouponManager.sol";
import {PermitParams, PermitParamsLibrary} from "./PermitParams.sol";
import {Coupon, CouponLibrary} from "./Coupon.sol";
import {Currency, CurrencyLibrary} from "./Currency.sol";

abstract contract Controller is ERC1155Holder {
    using CurrencyLibrary for Currency;
    using PermitParamsLibrary for PermitParams;
    using CouponLibrary for Coupon;

    IWrapped1155Factory internal immutable _wrapped1155Factory;
    CloberMarketFactory internal immutable _cloberMarketFactory;
    ICouponManager internal immutable _couponManager;
    IWETH9 internal immutable _weth;

    constructor(address wrapped1155Factory, address cloberMarketFactory, address couponManager, address weth) {
        _wrapped1155Factory = IWrapped1155Factory(wrapped1155Factory);
        _cloberMarketFactory = CloberMarketFactory(cloberMarketFactory);
        _couponManager = ICouponManager(couponManager);
        _weth = IWETH9(weth);
    }

    receive() external payable {}
}
