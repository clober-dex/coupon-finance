// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IERC1155MetadataURI} from "@openzeppelin/contracts/token/ERC1155/extensions/IERC1155MetadataURI.sol";

import {Types} from "../Types.sol";

interface ICouponManager is IERC1155MetadataURI {
    // View Functions //
    function minter() external view returns (address);

    function currentEpoch() external view returns (Types.Epoch);

    function epochEndTime(Types.Epoch epoch) external pure returns (uint256);

    function baseURI() external view returns (string memory);

    function totalSupply(uint256 id) external view returns (uint256);

    function exists(uint256 id) external view returns (bool);

    // User Functions
    function safeBatchTransferFrom(
        address from,
        address to,
        Types.Coupon[] calldata coupons,
        bytes calldata data
    ) external;

    function burnExpiredCoupons(Types.CouponKey[] calldata couponKeys) external;

    // Admin Functions //
    function mintBatch(address to, Types.Coupon[] calldata coupons, bytes memory data) external;

    function burnBatch(address user, Types.Coupon[] calldata coupons) external;
}
