// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC1155MetadataURI} from "@openzeppelin/contracts/token/ERC1155/extensions/IERC1155MetadataURI.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ERC1155Supply} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";

import {Errors} from "./Errors.sol";
import {Types} from "./Types.sol";
import {CouponKey} from "./libraries/CouponKey.sol";
import {Coupon} from "./libraries/Coupon.sol";
import {Epoch} from "./libraries/Epoch.sol";
import {ERC1155Permit} from "./libraries/ERC1155Permit.sol";
import {ICouponManager} from "./interfaces/ICouponManager.sol";

contract CouponManager is ERC1155Permit, ERC1155Supply, ICouponManager {
    using CouponKey for Types.CouponKey;
    using Coupon for Types.Coupon;
    using Epoch for Types.Epoch;

    address public immutable override minter;

    string public override baseURI;

    constructor(address minter_, string memory uri_) ERC1155Permit(uri_, "Coupon", "1") {
        minter = minter_;
        baseURI = uri_;
    }

    modifier onlyMinter() {
        if (msg.sender != minter) {
            revert(Errors.ACCESS);
        }
        _;
    }

    // View Functions //
    function uri(uint256 id) public view override(ERC1155, IERC1155MetadataURI) returns (string memory) {
        revert("not implemented"); // TODO
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
        (uint256[] memory ids, uint256[] memory amounts) = _splitCoupons(coupons);
        safeBatchTransferFrom(from, to, ids, amounts, data);
    }

    function burnExpiredCoupons(Types.CouponKey[] calldata couponKeys) external {
        uint256[] memory ids = new uint256[](couponKeys.length);
        uint256[] memory amounts = new uint256[](couponKeys.length);
        Types.Epoch current = Epoch.current();
        uint256 count;
        for (uint256 i = 0; i < couponKeys.length; ++i) {
            if (couponKeys[i].epoch.compare(current) >= 0) {
                continue;
            }
            uint256 id = couponKeys[i].toId();
            uint256 amount = balanceOf(msg.sender, id);
            if (amount == 0) {
                continue;
            }
            count++;
            ids[i] = id;
            amounts[i] = amount;
        }
        assembly {
            mstore(ids, count)
            mstore(amounts, count)
        }
        _burnBatch(msg.sender, ids, amounts);
    }

    // Admin Functions //
    function mintBatch(address to, Types.Coupon[] calldata coupons, bytes memory data) external onlyMinter {
        (uint256[] memory ids, uint256[] memory amounts) = _splitCoupons(coupons);
        _mintBatch(to, ids, amounts, data);
    }

    function burnBatch(address user, Types.Coupon[] calldata coupons) external onlyMinter {
        (uint256[] memory ids, uint256[] memory amounts) = _splitCoupons(coupons);
        _burnBatch(user, ids, amounts);
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

    function _splitCoupons(
        Types.Coupon[] calldata coupons
    ) internal pure returns (uint256[] memory ids, uint256[] memory amounts) {
        ids = new uint256[](coupons.length);
        amounts = new uint256[](coupons.length);
        unchecked {
            for (uint256 i = 0; i < coupons.length; ++i) {
                ids[i] = coupons[i].key.toId();
                amounts[i] = coupons[i].amount;
            }
        }
    }
}
