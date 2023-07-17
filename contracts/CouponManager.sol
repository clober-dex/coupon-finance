// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC1155MetadataURI} from "@openzeppelin/contracts/token/ERC1155/extensions/IERC1155MetadataURI.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ERC1155Supply} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";

import {Types} from "./Types.sol";
import {Epoch} from "./libraries/Epoch.sol";
import {ERC1155Permit} from "./libraries/ERC1155Permit.sol";
import {ICouponManager} from "./interfaces/ICouponManager.sol";

contract CouponManager is ERC1155Permit, ERC1155Supply, ICouponManager {
    using Epoch for Types.Epoch;

    address public immutable override minter;

    string public override baseURI;

    constructor(address minter_, string memory uri_) ERC1155Permit(uri_, "Coupon", "1") {
        minter = minter_;
    }

    // View Functions //
    function uri(uint256 id) public view override(ERC1155, IERC1155MetadataURI) returns (string memory) {
        revert("not implemented");
    }

    function currentEpoch() external view returns (Types.Epoch) {
        return Epoch.current();
    }

    function epochEndTime(Types.Epoch epoch) external pure returns (uint256) {
        return epoch.endTime();
    }

    function totalSupply(uint256 id) public view override(ERC1155Supply, ICouponManager) returns (uint256) {
        return super.totalSupply(id);
    }

    function exists(uint256 id) public view override(ERC1155Supply, ICouponManager) returns (bool) {
        return super.exists(id);
    }

    // User Functions
    function safeBatchTransferFrom(
        address from,
        address to,
        Types.Coupon[] calldata coupons,
        bytes calldata data
    ) external {
        revert("not implemented");
    }

    function burnExpiredCoupons(Types.CouponKey[] calldata couponKeys) external {
        revert("not implemented");
    }

    // Admin Functions //
    function mintBatch(address to, Types.Coupon[] calldata coupons, bytes memory data) external {
        revert("not implemented");
    }

    function burnBatch(address user, Types.Coupon[] calldata coupons) external {
        revert("not implemented");
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal override(ERC1155, ERC1155Supply) {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }
}
