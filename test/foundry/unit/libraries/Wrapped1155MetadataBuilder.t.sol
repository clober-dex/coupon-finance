// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {IWrapped1155Factory} from "../../../../contracts/external/wrapped1155/IWrapped1155Factory.sol";
import {ICouponManager} from "../../../../contracts/interfaces/ICouponManager.sol";
import {Coupon, CouponLibrary} from "../../../../contracts/libraries/Coupon.sol";
import {CouponKey, CouponKeyLibrary} from "../../../../contracts/libraries/CouponKey.sol";
import {Epoch} from "../../../../contracts/libraries/Epoch.sol";
import {Wrapped1155MetadataBuilder} from "../../../../contracts/libraries/Wrapped1155MetadataBuilder.sol";
import {CouponManager} from "../../../../contracts/CouponManager.sol";
import {Constants} from "../../Constants.sol";
import {ForkUtils} from "../../Utils.sol";

contract Wrapped1155MetadataBuilderUnitTest is Test, ERC1155Holder {
    using CouponLibrary for Coupon;
    using CouponKeyLibrary for CouponKey;

    IWrapped1155Factory public wrapped1155Factory;
    ICouponManager public couponManager;

    function setUp() public {
        ForkUtils.fork(vm, Constants.FORK_BLOCK_NUMBER);

        wrapped1155Factory = IWrapped1155Factory(Constants.WRAPPED1155_FACTORY);
        couponManager = new CouponManager(address(this), "URI/");
    }

    function testBuildWrapped1155Metadata() public {
        CouponKey memory couponKey = CouponKey(Constants.USDC, Epoch.wrap(11));
        bytes memory metadata = Wrapped1155MetadataBuilder.buildWrapped1155Metadata(couponKey);

        address wrappedToken = wrapped1155Factory.requireWrapped1155(address(couponManager), couponKey.toId(), metadata);
        assertEq(IERC20Metadata(wrappedToken).name(), "USDC Bond Coupon (11)");
        assertEq(IERC20Metadata(wrappedToken).symbol(), "USDC-CP11");
        assertEq(IERC20Metadata(wrappedToken).decimals(), 6);
        assertEq(Wrapped1155Metadata(wrappedToken).factory(), address(wrapped1155Factory));
        assertEq(Wrapped1155Metadata(wrappedToken).multiToken(), address(couponManager));
        assertEq(Wrapped1155Metadata(wrappedToken).tokenId(), couponKey.toId());
    }

    function testBuildWrapped1155BatchMetadata() public {
        Coupon[] memory coupons = new Coupon[](3);
        coupons[0] = CouponLibrary.from(Constants.USDC, Epoch.wrap(11), 123);
        coupons[1] = CouponLibrary.from(Constants.WETH, Epoch.wrap(32), 123);
        coupons[2] = CouponLibrary.from(Constants.WBTC, Epoch.wrap(123), 4423);

        bytes memory metadata = Wrapped1155MetadataBuilder.buildWrapped1155BatchMetadata(coupons);
        couponManager.mintBatch(address(this), coupons, "");

        couponManager.safeBatchTransferFrom(address(this), address(wrapped1155Factory), coupons, metadata);
        address[] memory wrappedTokens = new address[](3);
        for (uint256 i = 0; i < wrappedTokens.length; ++i) {
            wrappedTokens[i] = wrapped1155Factory.getWrapped1155(
                address(couponManager),
                coupons[i].id(),
                Wrapped1155MetadataBuilder.buildWrapped1155Metadata(coupons[i].key)
            );
            assertEq(Wrapped1155Metadata(wrappedTokens[i]).factory(), address(wrapped1155Factory));
            assertEq(Wrapped1155Metadata(wrappedTokens[i]).multiToken(), address(couponManager));
            assertEq(Wrapped1155Metadata(wrappedTokens[i]).tokenId(), coupons[i].id());
        }
        assertEq(IERC20Metadata(wrappedTokens[0]).name(), "USDC Bond Coupon (11)");
        assertEq(IERC20Metadata(wrappedTokens[0]).symbol(), "USDC-CP11");
        assertEq(IERC20Metadata(wrappedTokens[0]).decimals(), 6);
        assertEq(IERC20Metadata(wrappedTokens[1]).name(), "WETH Bond Coupon (32)");
        assertEq(IERC20Metadata(wrappedTokens[1]).symbol(), "WETH-CP32");
        assertEq(IERC20Metadata(wrappedTokens[1]).decimals(), 18);
        assertEq(IERC20Metadata(wrappedTokens[2]).name(), "WBTC Bond Coupon (123)");
        assertEq(IERC20Metadata(wrappedTokens[2]).symbol(), "WBTC-CP123");
        assertEq(IERC20Metadata(wrappedTokens[2]).decimals(), 8);
    }
}

interface Wrapped1155Metadata {
    function factory() external view returns (address);
    function multiToken() external view returns (address);
    function tokenId() external view returns (uint256);
}
