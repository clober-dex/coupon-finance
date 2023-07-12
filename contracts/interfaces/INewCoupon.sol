// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IERC1155MetadataURI} from "@openzeppelin/contracts/token/ERC1155/extensions/IERC1155MetadataURI.sol";

import {Types} from "../Types.sol";

interface INewCoupon is IERC1155MetadataURI {
    // View Functions //
    function startedAt() external view returns (uint256);

    function epochDuration() external view returns (uint256);

    function currentEpoch() external view returns (uint256);

    function assetPool() external view returns (address);

    function epochEndTime(uint256 epoch) external view returns (uint256);

    function isOperator(address operator) external view returns (bool);

    function baseURI() external view returns (string memory);

    function totalSupply(uint256 id) external view returns (uint256);

    function exists(uint256 id) external view returns (bool);

    function isAssetRegistered(address asset) external view returns (bool);

    function getAssetConfiguration(address asset) external view returns (Types.AssetConfiguration memory);

    function getReserveStatus(address asset) external view returns (Types.Reserve memory);

    // Admin Functions //
    function mintBatch(address to, Types.Coupon[] calldata coupons, bytes memory data) external;

    function burnBatch(address user, Types.Coupon[] calldata coupons) external;

    function registerAsset(address asset, Types.AssetConfiguration calldata config) external;
}