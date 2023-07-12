// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

import {Types} from "../Types.sol";
import {IERC721Permit} from "./IERC721Permit.sol";

interface IBondPosition is IERC721Metadata, IERC721Permit {
    // View Functions //
    function baseURI() external view returns (string memory);

    function coupon() external view returns (address);

    function nextId() external view returns (uint256);

    function bonds(uint256 tokenId) external view returns (Types.Bond memory);

    function isAssetRegistered(address asset) external view returns (bool);

    function mint(
        address asset,
        uint256 amount,
        uint256 lockEpochs,
        address recipient,
        bytes calldata data
    ) external returns (uint256);

    function adjustPosition(
        uint256 tokenId,
        int256 amountAmount,
        int256 lockEpochs,
        address recipient,
        bytes calldata data
    ) external;
}
