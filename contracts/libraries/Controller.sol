// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {CloberMarketFactory} from "../external/clober/CloberMarketFactory.sol";
import {IWETH9} from "../external/weth/IWETH9.sol";
import {IWrapped1155Factory} from "../external/wrapped1155/IWrapped1155Factory.sol";
import {CloberOrderBook} from "../external/clober/CloberOrderBook.sol";
import {ICouponManager} from "../interfaces/ICouponManager.sol";
import {PermitParams, PermitParamsLibrary} from "./PermitParams.sol";
import {Coupon, CouponLibrary} from "./Coupon.sol";
import {CouponKey, CouponKeyLibrary} from "./CouponKey.sol";
import {Currency, CurrencyLibrary} from "./Currency.sol";
import {Wrapped1155MetadataBuilder} from "./Wrapped1155MetadataBuilder.sol";

abstract contract Controller is ERC1155Holder, Ownable {
    error InvalidMarket();

    using CurrencyLibrary for Currency;
    using PermitParamsLibrary for PermitParams;
    using CouponKeyLibrary for CouponKey;
    using CouponLibrary for Coupon;

    IWrapped1155Factory internal immutable _wrapped1155Factory;
    CloberMarketFactory internal immutable _cloberMarketFactory;
    ICouponManager internal immutable _couponManager;
    IWETH9 internal immutable _weth;

    mapping(uint256 couponId => address market) internal _couponMarkets;

    constructor(address wrapped1155Factory, address cloberMarketFactory, address couponManager, address weth) {
        _wrapped1155Factory = IWrapped1155Factory(wrapped1155Factory);
        _cloberMarketFactory = CloberMarketFactory(cloberMarketFactory);
        _couponManager = ICouponManager(couponManager);
        _weth = IWETH9(weth);
    }

    function getCouponMarket(CouponKey memory couponKey) external view returns (address) {
        return _couponMarkets[couponKey.toId()];
    }

    function setCouponMarket(CouponKey memory couponKey, address cloberMarket) external onlyOwner {
        bytes memory wrappedCouponMetadata = Wrapped1155MetadataBuilder.buildWrapped1155Metadata(couponKey);
        uint256 id = couponKey.toId();
        address wrappedCoupon = _wrapped1155Factory.getWrapped1155(address(_couponManager), id, wrappedCouponMetadata);
        CloberMarketFactory.MarketInfo memory marketInfo = _cloberMarketFactory.getMarketInfo(cloberMarket);
        if (marketInfo.host == address(0)) revert InvalidMarket();
        if (CloberOrderBook(cloberMarket).baseToken() != wrappedCoupon) revert InvalidMarket();
        if (CloberOrderBook(cloberMarket).quoteToken() != couponKey.asset) revert InvalidMarket();
        _couponMarkets[id] = cloberMarket;
    }

    receive() external payable {}
}
