// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {ICouponOracle} from "../../../../contracts/interfaces/ICouponOracle.sol";
import {CouponOracle} from "../../../../contracts/CouponOracle.sol";
import {ForkUtils, Utils} from "../../Utils.sol";
import {Constants} from "../../Constants.sol";
import {MockFallbackOracle} from "./MockFallbackOracle.sol";
import {InvalidPriceFeed} from "./InvalidPriceFeed.sol";

contract CouponOracleUnitTest is Test {
    InvalidPriceFeed public invalidPriceFeed;
    MockFallbackOracle public mockFallbackOracle;
    CouponOracle public couponOracle;

    function setUp() public {
        ForkUtils.fork(vm, Constants.FORK_BLOCK_NUMBER);

        invalidPriceFeed = new InvalidPriceFeed();
        mockFallbackOracle = new MockFallbackOracle();
        couponOracle = new CouponOracle(Utils.toArr(Constants.WETH), Utils.toArr(Constants.ETH_CHAINLINK_FEED));
    }

    function testSetFeeds() public {
        assertEq(couponOracle.getFeed(Constants.USDC), address(0), "FEED_NOT_SET");

        couponOracle.setFeeds(Utils.toArr(Constants.USDC), Utils.toArr(Constants.USDC_CHAINLINK_FEED));

        assertEq(couponOracle.getFeed(Constants.USDC), Constants.USDC_CHAINLINK_FEED, "FEED_SET");
    }

    function testSetFeedsOwnership() public {
        vm.prank(address(0x123));
        vm.expectRevert("Ownable: caller is not the owner");
        couponOracle.setFeeds(Utils.toArr(Constants.USDC), Utils.toArr(Constants.USDC_CHAINLINK_FEED));
    }

    function testSetFeedsLengthMismatch() public {
        vm.expectRevert(abi.encodeWithSelector(ICouponOracle.LengthMismatch.selector));
        couponOracle.setFeeds(
            Utils.toArr(Constants.USDC), Utils.toArr(Constants.USDC_CHAINLINK_FEED, Constants.USDC_CHAINLINK_FEED)
        );
    }

    function testSetFeedsInvalidDecimals() public {
        invalidPriceFeed.setDecimals(18);
        vm.expectRevert(abi.encodeWithSelector(ICouponOracle.InvalidDecimals.selector));
        couponOracle.setFeeds(Utils.toArr(Constants.USDC), Utils.toArr(address(invalidPriceFeed)));
    }

    function testSetFallbackOracle() public {
        assertEq(couponOracle.fallbackOracle(), address(0), "FALLBACK_ORACLE_NOT_SET");

        couponOracle.setFallbackOracle(address(mockFallbackOracle));

        assertEq(couponOracle.fallbackOracle(), address(mockFallbackOracle), "FALLBACK_ORACLE_SET");
    }

    function testSetFallbackOracleOwnership() public {
        vm.prank(address(0x123));
        vm.expectRevert("Ownable: caller is not the owner");
        couponOracle.setFallbackOracle(address(mockFallbackOracle));
    }

    function testGetPrice() public {
        uint256 price = couponOracle.getAssetPrice(Constants.WETH);
        assertEq(price, 186211909640, "PRICE");

        uint256[] memory prices = couponOracle.getAssetsPrices(Utils.toArr(Constants.WETH));
        assertEq(prices.length, 1, "PRICES_LENGTH");
        assertEq(prices[0], price, "PRICES_0");
    }

    function testGetPriceWhenFeedNotSet() public {
        couponOracle.setFallbackOracle(address(mockFallbackOracle));

        assertEq(couponOracle.getAssetPrice(Constants.WBTC), mockFallbackOracle.FALLBACK_PRICE(), "FALLBACK_PRICE");
    }

    function testGetPriceWhenPriceIsInvalid() public {
        couponOracle.setFallbackOracle(address(mockFallbackOracle));
        couponOracle.setFeeds(Utils.toArr(Constants.WETH), Utils.toArr(address(invalidPriceFeed)));
        invalidPriceFeed.setPrice(0);

        assertEq(couponOracle.getAssetPrice(Constants.WETH), mockFallbackOracle.FALLBACK_PRICE(), "FALLBACK_PRICE_0");

        invalidPriceFeed.setPrice(-1);
        assertEq(couponOracle.getAssetPrice(Constants.WETH), mockFallbackOracle.FALLBACK_PRICE(), "FALLBACK_PRICE_1");
    }

    function testGetPriceWhenFeedAndFallbackNotSet() public {
        vm.expectRevert();
        couponOracle.getAssetPrice(Constants.WBTC);
    }
}
