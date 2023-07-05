// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/extensions/IERC1155MetadataURI.sol";

interface ICouponPool is IERC1155MetadataURI {
    function totalSupply(uint256 id) external view returns (uint256);

    function exists(uint256 id) external view returns (bool);
}
