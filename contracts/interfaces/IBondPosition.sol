// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

import {Types} from "../Types.sol";
import {IERC721Permit} from "./IERC721Permit.sol";

interface IBondPosition is IERC721Permit, IERC721Metadata {
    function baseURI() external view returns (string memory);

    function coupon() external view returns (address);

    function assetPool() external view returns (address);

    function nextId() external view returns (uint256);

    function mint(
        address asset,
        uint256 amount,
        uint256 lockEpochs,
        address recipient
    ) external payable returns (uint256);

    function mintWithPermit(
        address asset,
        uint256 amount,
        uint256 lockEpochs,
        address recipient,
        Types.PermitParams calldata permitParams
    ) external returns (uint256);

    function increaseBond(uint256 tokenId, uint256 amount, address recipient) external payable;

    function increaseBondWithPermit(
        uint256 tokenId,
        uint256 amount,
        address recipient,
        Types.PermitParams calldata permitParams
    ) external payable;

    function decreaseBond(uint256 tokenId, uint256 amount, address recipient) external;

    function increaseLockEpochs(uint256 tokenId, uint256 epochs, address recipient) external;

    function decreaseLockEpochs(uint256 tokenId, uint256 epochs, address recipient) external;

    function burn(uint256 tokenId, address recipient) external;
}
