// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {CloberMarketSwapCallbackReceiver} from "../external/clober/CloberMarketSwapCallbackReceiver.sol";
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
import {IERC721Permit} from "../interfaces/IERC721Permit.sol";

abstract contract Controller is ERC1155Holder, CloberMarketSwapCallbackReceiver, Ownable {
    error InvalidMarket();
    error ControllerSlippage();

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

    function _sellCoupons(Coupon[] memory coupons, uint256 minEarnedAmount, Currency currency, address user)
        internal
        returns (uint256 earnedAmount)
    {
        // wrap 1155 to 20
        _couponManager.safeBatchTransferFrom(
            address(this),
            address(_wrapped1155Factory),
            coupons,
            Wrapped1155MetadataBuilder.buildWrapped1155BatchMetadata(coupons)
        );
        // sell
        earnedAmount = currency.balanceOfSelf();
        for (uint256 i = 0; i < coupons.length; ++i) {
            CloberOrderBook market = CloberOrderBook(_couponMarkets[coupons[i].id()]);
            market.marketOrder(address(this), 0, 0, coupons[i].amount, 2, abi.encode(user, false));
        }
        earnedAmount = currency.balanceOfSelf() - earnedAmount;
        if (earnedAmount < minEarnedAmount) {
            revert ControllerSlippage();
        }
    }

    function _buyCoupons(
        Coupon[] memory coupons,
        uint256 maxAmountToPay,
        address user,
        Currency currency,
        bool useNative
    ) internal {
        // buy
        uint256[] memory tokenIds = new uint256[](coupons.length);
        uint256[] memory amounts = new uint256[](coupons.length);
        uint256 paidAmount = useNative ? address(this).balance : IERC20(Currency.unwrap(currency)).balanceOf(user);
        for (uint256 i = 0; i < coupons.length; ++i) {
            CloberOrderBook market;
            {
                uint256 couponId = coupons[i].id();
                market = CloberOrderBook(_couponMarkets[couponId]);
                tokenIds[i] = couponId;
            }
            amounts[i] = coupons[i].amount;
            uint256 dy = coupons[i].amount - IERC20(market.baseToken()).balanceOf(address(this));
            market.marketOrder(address(this), type(uint16).max, type(uint64).max, dy, 1, abi.encode(user, useNative));
        }
        paidAmount =
            paidAmount - (useNative ? address(this).balance : IERC20(Currency.unwrap(currency)).balanceOf(user));
        if (paidAmount > maxAmountToPay) {
            revert ControllerSlippage();
        }

        // unwrap
        _wrapped1155Factory.batchUnwrap(
            address(_couponManager),
            tokenIds,
            amounts,
            address(this),
            Wrapped1155MetadataBuilder.buildWrapped1155BatchMetadata(coupons)
        );
    }

    function cloberMarketSwapCallback(address inputToken, address, uint256 inputAmount, uint256, bytes calldata data)
        external
        payable
    {
        // check if caller is registered market
        if (_cloberMarketFactory.getMarketHost(msg.sender) == address(0)) {
            revert("");
        }

        (address payer, bool useNative) = abi.decode(data, (address, bool));

        // transfer input tokens
        if (inputAmount > 0) {
            if (useNative) {
                IWETH9(inputToken).deposit{value: inputAmount}();
                IWETH9(inputToken).transfer(msg.sender, inputAmount);
            } else {
                Currency inputCurrency = Currency.wrap(inputToken);
                uint256 thisBalance = inputCurrency.balanceOfSelf();
                if (thisBalance < inputAmount) {
                    inputCurrency.transferFrom(payer, msg.sender, inputAmount - thisBalance);
                    inputCurrency.transfer(msg.sender, thisBalance);
                } else {
                    inputCurrency.transfer(msg.sender, inputAmount);
                }
            }
        }
    }

    function _permitERC20(Currency currency, uint256 amount, PermitParams calldata p) internal {
        if (!p.isEmpty()) {
            IERC20Permit(currency.unwrap()).permit(msg.sender, address(this), amount, p.deadline, p.v, p.r, p.s);
        }
    }

    function _permitERC721(IERC721Permit permitNFT, uint256 positionId, PermitParams calldata p) internal {
        if (!p.isEmpty()) {
            permitNFT.permit(address(this), positionId, p.deadline, p.v, p.r, p.s);
        }
    }

    function _flush(Currency currency, address to) internal {
        uint256 leftAmount = currency.balanceOfSelf();
        if (leftAmount == 0) {
            return;
        }
        if (currency.unwrap() == address(_weth)) {
            _weth.withdraw(leftAmount);
            currency = CurrencyLibrary.NATIVE;
        }
        currency.transfer(to, leftAmount);
    }

    function getCouponMarket(CouponKey memory couponKey) external view returns (address) {
        return _couponMarkets[couponKey.toId()];
    }

    function setCouponMarket(CouponKey memory couponKey, address cloberMarket) public virtual onlyOwner {
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
