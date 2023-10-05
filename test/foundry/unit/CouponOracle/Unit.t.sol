// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {ICouponOracleTypes, ICouponOracle} from "../../../../contracts/interfaces/ICouponOracle.sol";
import {CouponOracle} from "../../../../contracts/CouponOracle.sol";
import {ForkUtils, Utils} from "../../Utils.sol";
import {Constants} from "../../Constants.sol";
import {MockFallbackOracle} from "./MockFallbackOracle.sol";
import {InvalidPriceFeed} from "./InvalidPriceFeed.sol";

contract CouponOracleUnitTest is Test, ICouponOracleTypes {
    InvalidPriceFeed public invalidPriceFeed;
    MockFallbackOracle public mockFallbackOracle;
    CouponOracle public couponOracle;

    function setUp() public {
        ForkUtils.fork(vm, Constants.FORK_BLOCK_NUMBER);

        invalidPriceFeed = new InvalidPriceFeed();
        mockFallbackOracle = new MockFallbackOracle();
        couponOracle = new CouponOracle(Constants.CHAINLINK_SEQUENCER_ORACLE, 3600, 3600);
        couponOracle.setFeeds(Utils.toArr(Constants.WETH), Utils.toArr(Utils.toArr(Constants.ETH_CHAINLINK_FEED)));
    }

    function testSetFeeds() public {
        assertEq(couponOracle.getFeeds(Constants.USDC).length, 0, "FEED_NOT_SET");

        vm.expectEmit(true, true, true, true);
        emit SetFeed(Constants.USDC, Utils.toArr(Constants.USDC_CHAINLINK_FEED));
        couponOracle.setFeeds(Utils.toArr(Constants.USDC), Utils.toArr(Utils.toArr(Constants.USDC_CHAINLINK_FEED)));

        assertEq(couponOracle.getFeeds(Constants.USDC).length, 1, "FEED_SET_LENGTH");
        assertEq(couponOracle.getFeeds(Constants.USDC)[0], Constants.USDC_CHAINLINK_FEED, "FEED_SET");
    }

    function testSetFeedsOwnership() public {
        vm.prank(address(0x123));
        vm.expectRevert("Ownable: caller is not the owner");
        couponOracle.setFeeds(Utils.toArr(Constants.USDC), Utils.toArr(Utils.toArr(Constants.USDC_CHAINLINK_FEED)));
    }

    function testSetFeedsLengthMismatch() public {
        vm.expectRevert(abi.encodeWithSelector(LengthMismatch.selector));
        couponOracle.setFeeds(
            Utils.toArr(Constants.USDC, Constants.WETH), Utils.toArr(Utils.toArr(Constants.USDC_CHAINLINK_FEED))
        );
    }

    function testSetFeedsAlreadySet() public {
        couponOracle.setFeeds(Utils.toArr(Constants.USDC), Utils.toArr(Utils.toArr(Constants.USDC_CHAINLINK_FEED)));
        vm.expectRevert(abi.encodeWithSelector(AssetFeedAlreadySet.selector));
        couponOracle.setFeeds(Utils.toArr(Constants.USDC), Utils.toArr(Utils.toArr(Constants.USDC_CHAINLINK_FEED)));
    }

    function testSetFallbackOracle() public {
        assertEq(couponOracle.fallbackOracle(), address(0), "FALLBACK_ORACLE_NOT_SET");

        vm.expectEmit(true, true, true, true);
        emit SetFallbackOracle(address(mockFallbackOracle));
        couponOracle.setFallbackOracle(address(mockFallbackOracle));

        assertEq(couponOracle.fallbackOracle(), address(mockFallbackOracle), "FALLBACK_ORACLE_SET");
    }

    function testSetFallbackOracleOwnership() public {
        vm.prank(address(0x123));
        vm.expectRevert("Ownable: caller is not the owner");
        couponOracle.setFallbackOracle(address(mockFallbackOracle));
    }

    function testSetSequencerOracle() public {
        vm.expectEmit(true, true, true, true);
        emit SetSequencerOracle(address(123));
        couponOracle.setSequencerOracle(address(123));

        assertEq(couponOracle.sequencerOracle(), address(123), "SEQUENCER_ORACLE_SET");
    }

    function testSetSequencerOracleOwnership() public {
        vm.prank(address(0x123));
        vm.expectRevert("Ownable: caller is not the owner");
        couponOracle.setSequencerOracle(address(123));
    }

    function testSetGracePeriod() public {
        vm.expectEmit(true, true, true, true);
        emit SetGracePeriod(1800);
        couponOracle.setGracePeriod(1800);

        assertEq(couponOracle.gracePeriod(), 1800, "GRACE_PERIOD_SET");
    }

    function testSetGracePeriodInvalidValue() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidGracePeriod.selector));
        couponOracle.setGracePeriod(1 minutes - 1);
        vm.expectRevert(abi.encodeWithSelector(InvalidGracePeriod.selector));
        couponOracle.setGracePeriod(1 days + 1);
    }

    function testSetGracePeriodOwnership() public {
        vm.prank(address(0x123));
        vm.expectRevert("Ownable: caller is not the owner");
        couponOracle.setGracePeriod(1800);
    }

    function testSetTimeout() public {
        vm.expectEmit(true, true, true, true);
        emit SetTimeout(1800);
        couponOracle.setTimeout(1800);

        assertEq(couponOracle.timeout(), 1800, "TIMEOUT_SET");
    }

    function testSetTimeoutInvalidValue() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidTimeout.selector));
        couponOracle.setTimeout(1 minutes - 1);
        vm.expectRevert(abi.encodeWithSelector(InvalidTimeout.selector));
        couponOracle.setTimeout(1 days + 1);
    }

    function testSetTimeoutOwnership() public {
        vm.prank(address(0x123));
        vm.expectRevert("Ownable: caller is not the owner");
        couponOracle.setTimeout(1800);
    }

    function testCompositeFeeds() public {
        couponOracle.setTimeout(1 days);
        address wstEth = 0x0fBcbaEA96Ce0cF7Ee00A8c19c3ab6f5Dc8E1921;
        address wstEthEthFeed = 0xb523AE262D20A936BC152e6023996e46FDC2A95D;
        couponOracle.setFeeds(
            Utils.toArr(wstEth), Utils.toArr(Utils.toArr(wstEthEthFeed, Constants.ETH_CHAINLINK_FEED))
        );

        uint256 price = couponOracle.getAssetPrice(wstEth);
        console.log(price);
    }

    function testGetPrice() public {
        uint256 price = couponOracle.getAssetPrice(Constants.WETH);
        assertEq(price, 184466348000, "PRICE");

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
        couponOracle.setFeeds(Utils.toArr(Constants.USDC), Utils.toArr(Utils.toArr(address(invalidPriceFeed))));
        invalidPriceFeed.setPrice(0);

        assertEq(couponOracle.getAssetPrice(Constants.USDC), mockFallbackOracle.FALLBACK_PRICE(), "FALLBACK_PRICE_0");

        invalidPriceFeed.setPrice(-1);
        assertEq(couponOracle.getAssetPrice(Constants.USDC), mockFallbackOracle.FALLBACK_PRICE(), "FALLBACK_PRICE_1");
    }

    function testGetPriceWhenTimeout() public {
        couponOracle.setFallbackOracle(address(mockFallbackOracle));

        vm.warp(block.timestamp + 3600);

        assertEq(couponOracle.getAssetPrice(Constants.USDC), mockFallbackOracle.FALLBACK_PRICE(), "FALLBACK_PRICE_0");
    }

    function testGetPriceWhenFeedAndFallbackNotSet() public {
        vm.expectRevert();
        couponOracle.getAssetPrice(Constants.WBTC);
    }

    function testIsSequencerValid() public {
        assertTrue(couponOracle.isSequencerValid(), "BEFORE_IS_SEQUENCER_VALID");

        uint256 lastUpdatedAt = 1668705995;
        vm.warp(lastUpdatedAt + 1);
        assertFalse(couponOracle.isSequencerValid(), "AFTER_IS_SEQUENCER_VALID_1");
        vm.warp(lastUpdatedAt + 3600);
        assertFalse(couponOracle.isSequencerValid(), "AFTER_IS_SEQUENCER_VALID_2");
        vm.warp(lastUpdatedAt + 3600 + 1);
        assertTrue(couponOracle.isSequencerValid(), "AFTER_IS_SEQUENCER_VALID_3");
    }
}
