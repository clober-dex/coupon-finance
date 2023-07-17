// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {Types} from "./Types.sol";
import {IBondPosition} from "./interfaces/IBondPosition.sol";
import {ERC721Permit} from "./libraries/ERC721Permit.sol";

contract BondPosition is IBondPosition, ERC721Permit {
    address public immutable override coupon;
    address public immutable override assetPool;

    string public override baseURI;
    uint256 public override nextId = 1;

    mapping(address asset => bool) public override isAssetRegistered;
    mapping(uint256 id => Types.Bond) private _bondMap;

    constructor(address coupon_, address assetPool_, string memory baseURI_) ERC721Permit("Bond Position", "BP", "1") {
        coupon = coupon_;
        assetPool = assetPool_;
        baseURI = baseURI_;
    }

    function bonds(uint256 tokenId) external view returns (Types.Bond memory) {
        return _bondMap[tokenId];
    }

    function mint(
        address asset,
        uint256 amount,
        uint256 lockEpochs,
        address recipient,
        bytes calldata data
    ) external returns (uint256) {
        revert("not implemented");
    }

    function adjustPosition(uint256 tokenId, int256 amount, int256 lockEpochs, bytes calldata data) external {
        revert("not implemented");
    }

    function _getAndIncrementNonce(uint256 tokenId) internal override returns (uint256) {
        return _bondMap[tokenId].nonce++;
    }
}
