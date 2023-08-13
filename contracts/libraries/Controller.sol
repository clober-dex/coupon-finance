// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
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
import {Wrapped1155MetadataBuilder} from "./Wrapped1155MetadataBuilder.sol";
import {IERC721Permit} from "../interfaces/IERC721Permit.sol";
import {ISubstitute} from "../interfaces/ISubstitute.sol";
import {IAaveTokenSubstitute} from "../interfaces/IAaveTokenSubstitute.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";

abstract contract Controller is ERC1155Holder, CloberMarketSwapCallbackReceiver, Ownable, ReentrancyGuard {
    error ValueTransferFailed();
    error InvalidAccess();
    error InvalidMarket();
    error ControllerSlippage();

    using SafeERC20 for IERC20;
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

    function _executeCouponTrade(
        address user,
        address token,
        Coupon[] memory couponsToBuy,
        Coupon[] memory couponsToSell,
        uint256 amountToPay,
        uint256 maxPayInterest,
        uint256 leftRequiredInterest
    ) internal {
        if (couponsToBuy.length > 0) {
            Coupon memory lastCoupon = couponsToBuy[couponsToBuy.length - 1];
            assembly {
                mstore(couponsToBuy, sub(mload(couponsToBuy), 1))
            }
            bytes memory data =
                abi.encode(user, couponsToBuy, new Coupon[](0), amountToPay, maxPayInterest, leftRequiredInterest);
            assembly {
                mstore(couponsToBuy, add(mload(couponsToBuy), 1))
            }

            CloberOrderBook market = CloberOrderBook(_couponMarkets[lastCoupon.id()]);
            uint256 dy = lastCoupon.amount - IERC20(market.baseToken()).balanceOf(address(this));
            market.marketOrder(address(this), type(uint16).max, type(uint64).max, dy, 1, data);
        } else if (couponsToSell.length > 0) {
            Coupon memory lastCoupon = couponsToSell[couponsToSell.length - 1];
            assembly {
                mstore(couponsToSell, sub(mload(couponsToSell), 1))
            }
            bytes memory data =
                abi.encode(user, new Coupon[](0), couponsToSell, amountToPay, maxPayInterest, leftRequiredInterest);
            assembly {
                mstore(couponsToSell, add(mload(couponsToSell), 1))
            }

            CloberOrderBook market = CloberOrderBook(_couponMarkets[lastCoupon.id()]);
            market.marketOrder(address(this), 0, 0, lastCoupon.amount, 2, data);
        } else {
            if (leftRequiredInterest > 0) revert ControllerSlippage();
            _ensureBalance(token, user, amountToPay);
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
        if (_cloberMarketFactory.getMarketHost(msg.sender) == address(0)) revert InvalidAccess();

        (
            address user,
            Coupon[] memory buyCoupons,
            Coupon[] memory sellCoupons,
            uint256 amountToPay,
            uint256 maxPayInterest,
            uint256 leftRequiredInterest
        ) = abi.decode(data, (address, Coupon[], Coupon[], uint256, uint256, uint256));

        address asset = CloberOrderBook(msg.sender).quoteToken();
        if (asset == inputToken) {
            if (maxPayInterest < inputAmount) revert ControllerSlippage();
            maxPayInterest -= inputAmount;
            amountToPay += inputAmount;
        } else {
            if (leftRequiredInterest > outputAmount) {
                leftRequiredInterest -= outputAmount;
            } else {
                leftRequiredInterest = 0;
            }
        }

        _executeCouponTrade(user, asset, buyCoupons, sellCoupons, amountToPay, maxPayInterest, leftRequiredInterest);

        // transfer input tokens
        if (inputAmount > 0) {
            IERC20(inputToken).safeTransfer(msg.sender, inputAmount);
        }
    }

    function _permitERC20(address token, uint256 amount, PermitParams calldata p) internal {
        if (!p.isEmpty()) {
            IERC20Permit(ISubstitute(token).underlyingToken()).permit(
                msg.sender, address(this), amount, p.deadline, p.v, p.r, p.s
            );
        }
    }

    function _permitERC721(IERC721Permit permitNFT, uint256 positionId, PermitParams calldata p) internal {
        if (!p.isEmpty()) {
            permitNFT.permit(address(this), positionId, p.deadline, p.v, p.r, p.s);
        }
    }

    function _burnAllSubstitute(address substitute, address to) internal {
        uint256 leftAmount = IERC20(substitute).balanceOf(address(this));
        if (leftAmount == 0) return;

        address underlyingToken = ISubstitute(substitute).underlyingToken();
        uint256 burnableAmount = ISubstitute(substitute).burnableAmount();
        if (burnableAmount < leftAmount) {
            IAaveTokenSubstitute(substitute).burnToAToken(leftAmount - burnableAmount, to);
            leftAmount = burnableAmount;
        }
        if (underlyingToken == address(_weth)) {
            ISubstitute(substitute).burn(leftAmount, address(this));
            _weth.withdraw(leftAmount);
            (bool success,) = payable(to).call{value: leftAmount}("");
            if (!success) revert ValueTransferFailed();
        } else {
            ISubstitute(substitute).burn(leftAmount, to);
        }
    }

    function _ensureBalance(address token, address user, uint256 amount) internal {
        address underlyingToken = ISubstitute(token).underlyingToken();
        uint256 thisBalance = IERC20(token).balanceOf(address(this));
        uint256 underlyingBalance = IERC20(underlyingToken).balanceOf(address(this));
        if (amount > thisBalance + underlyingBalance) {
            unchecked {
                IERC20(underlyingToken).safeTransferFrom(user, address(this), amount - thisBalance - underlyingBalance);
                underlyingBalance = amount - thisBalance;
            }
        }
        if (underlyingBalance > 0) {
            IERC20(underlyingToken).approve(token, underlyingBalance);
            ISubstitute(token).mint(underlyingBalance, address(this));
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
