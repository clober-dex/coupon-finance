// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IERC1155MetadataURI} from "@openzeppelin/contracts/token/ERC1155/extensions/IERC1155MetadataURI.sol";

import {CouponKey} from "../libraries/CouponKey.sol";
import {Coupon} from "../libraries/Coupon.sol";
import {Epoch} from "../libraries/Epoch.sol";

interface ICouponManager is IERC1155MetadataURI {
    error InvalidAccess();

    // View Functions //
    function isMinter(address account) external view returns (bool);

    function currentEpoch() external view returns (Epoch);

    function epochEndTime(Epoch epoch) external pure returns (uint256);

    function baseURI() external view returns (string memory);

    function totalSupply(uint256 id) external view returns (uint256);

    function exists(uint256 id) external view returns (bool);

    // User Functions
    function safeBatchTransferFrom(address from, address to, Coupon[] calldata coupons, bytes calldata data) external;

    function burnExpiredCoupons(CouponKey[] calldata couponKeys) external;

    // Admin Functions //
    function mintBatch(address to, Coupon[] calldata coupons, bytes memory data) external;

    function burnBatch(address user, Coupon[] calldata coupons) external;
}
