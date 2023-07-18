// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

import {Types} from "../Types.sol";
import {IERC721Permit} from "./IERC721Permit.sol";

interface IBondPositionEvents {
    event AssetRegistered(address indexed asset);
    event PositionUpdated(uint256 indexed tokenId, uint256 amount, Types.Epoch expiredWith);
}

interface IBondPosition is IERC721Metadata, IERC721Permit, IBondPositionEvents {
    // View Functions //
    function baseURI() external view returns (string memory);

    function nextId() external view returns (uint256);

    function coupon() external view returns (address);

    function assetPool() external view returns (address);

    function bonds(uint256 tokenId) external view returns (Types.Bond memory);

    function isAssetRegistered(address asset) external view returns (bool);

    // User Functions //
    function mint(
        address asset,
        uint256 amount,
        uint16 lockEpochs,
        address recipient,
        bytes calldata data
    ) external returns (uint256);

    function adjustPosition(uint256 tokenId, int256 amount, int16 lockEpochs, bytes calldata data) external;

    function burnExpiredPosition(uint256 tokenId) external;

    // Admin Functions //
    function registerAsset(address asset) external;
}
