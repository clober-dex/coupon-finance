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
import {ReentrancyGuard} from "./ReentrancyGuard.sol";

abstract contract Controller is ERC1155Holder, CloberMarketSwapCallbackReceiver, Ownable, ReentrancyGuard {
    error Access();
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

    modifier wrapETH() {
        if (msg.value > 0) {
            _weth.deposit{value: msg.value}();
        }
        _;
    }

    function _callManager(Currency currency, uint256 amountToPay, uint256 earnedAmount) internal virtual;

    function _execute(
        Currency currency,
        Coupon[] memory couponsToBuy,
        Coupon[] memory couponsToSell,
        uint256 amountToPay,
        uint256 earnedAmount
    ) internal {
        if (couponsToBuy.length > 0) {
            Coupon memory lastCoupon = couponsToBuy[couponsToBuy.length - 1];
            assembly {
                mstore(couponsToBuy, sub(mload(couponsToBuy), 1))
            }

            CloberOrderBook market = CloberOrderBook(_couponMarkets[lastCoupon.id()]);
            bytes memory data = abi.encode(couponsToBuy, new Coupon[](0), amountToPay);
            uint256 dy = lastCoupon.amount - IERC20(market.baseToken()).balanceOf(address(this));
            market.marketOrder(address(this), type(uint16).max, type(uint64).max, dy, 1, data);
        } else if (couponsToSell.length > 0) {
            Coupon memory lastCoupon = couponsToSell[couponsToSell.length - 1];
            assembly {
                mstore(couponsToSell, sub(mload(couponsToSell), 1))
            }

            CloberOrderBook market = CloberOrderBook(_couponMarkets[lastCoupon.id()]);
            bytes memory data = abi.encode(new Coupon[](0), couponsToSell, earnedAmount);
            market.marketOrder(address(this), 0, 0, lastCoupon.amount, 2, data);
        } else {
            _callManager(currency, amountToPay, earnedAmount);
        }
    }

    function cloberMarketSwapCallback(
        address inputToken,
        address,
        uint256 inputAmount,
        uint256 outputAmount,
        bytes calldata data
    ) external payable {
        // check if caller is registered market
        if (_cloberMarketFactory.getMarketHost(msg.sender) == address(0)) {
            revert Access();
        }

        (Coupon[] memory buyCoupons, Coupon[] memory sellCoupons, uint256 amountToPay, uint256 earnedAmount) =
            abi.decode(data, (Coupon[], Coupon[], uint256, uint256));

        address asset = CloberOrderBook(msg.sender).quoteToken();
        if (asset == inputToken) {
            amountToPay += inputAmount;
        } else {
            earnedAmount += outputAmount;
        }

        _execute(Currency.wrap(asset), buyCoupons, sellCoupons, amountToPay, earnedAmount);

        // transfer input tokens
        if (inputAmount > 0) {
            Currency.wrap(inputToken).transfer(msg.sender, inputAmount);
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
        if (leftAmount == 0) return;
        if (currency.unwrap() == address(_weth)) {
            _weth.withdraw(leftAmount);
            currency = CurrencyLibrary.NATIVE;
        }
        currency.transfer(to, leftAmount);
    }

    function _ensureBalance(Currency currency, address user, uint256 amount) internal {
        uint256 thisBalance = currency.balanceOfSelf();
        if (amount > thisBalance) {
            currency.transferFrom(user, address(this), amount - thisBalance);
        }
    }

    function _wrapCoupons(Coupon[] memory coupons) internal {
        // wrap 1155 to 20
        _couponManager.safeBatchTransferFrom(
            address(this),
            address(_wrapped1155Factory),
            coupons,
            Wrapped1155MetadataBuilder.buildWrapped1155BatchMetadata(coupons)
        );
    }

    function _unwrapCoupons(Coupon[] memory coupons) internal {
        if (coupons.length > 0) {
            uint256[] memory tokenIds = new uint256[](coupons.length);
            uint256[] memory amounts = new uint256[](coupons.length);
            for (uint256 i = 0; i < coupons.length; i++) {
                tokenIds[i] = coupons[i].id();
                amounts[i] = coupons[i].amount;
            }
            _wrapped1155Factory.batchUnwrap(
                address(_couponManager),
                tokenIds,
                amounts,
                address(this),
                Wrapped1155MetadataBuilder.buildWrapped1155BatchMetadata(coupons)
            );
        }
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
