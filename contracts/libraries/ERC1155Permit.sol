// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

import {IERC1155Permit} from "../interfaces/IERC1155Permit.sol";

contract ERC1155Permit is ERC1155, IERC1155Permit, EIP712 {
    mapping(address => uint256) public override nonces;

    bytes32 public constant override PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address operator,bool approved,uint256 nonce,uint256 deadline)");

    constructor(string memory uri_, string memory name, string memory version) ERC1155(uri_) EIP712(name, version) {}

    function permit(
        address owner,
        address operator,
        bool approved,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {
        require(block.timestamp <= deadline, "Permit expired");

        bytes32 structHash;
        unchecked {
            structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, operator, approved, nonces[owner]++, deadline));
        }

        bytes32 digest = _hashTypedDataV4(structHash);

        if (Address.isContract(owner)) {
            require(IERC1271(owner).isValidSignature(digest, abi.encodePacked(r, s, v)) == 0x1626ba7e, "Unauthorized");
        } else {
            address signer = ECDSA.recover(digest, v, r, s);
            require(signer == owner, "Unauthorized");
        }

        _setApprovalForAll(owner, operator, approved);
    }

    function DOMAIN_SEPARATOR() external view override returns (bytes32) {
        return _domainSeparatorV4();
    }
}