// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {Epoch} from "../../../../contracts/libraries/Epoch.sol";
import {CouponKey, CouponKeyLibrary} from "../../../../contracts/libraries/CouponKey.sol";

contract CouponKeyUnitTest is Test {
    using Strings for uint256;
    using CouponKeyLibrary for CouponKey;

    address public constant TOKEN = address(uint160(0x00_6b175474e89094c44da98b954eedeac495271d0f));

    function testToId() public {
        _checkId(TOKEN, 0, 0x6b175474e89094c44da98b954eedeac495271d0f000000000000000000000000);
        _checkId(TOKEN, 1, 0x6b175474e89094c44da98b954eedeac495271d0f000000000000000000000001);
        _checkId(TOKEN, type(uint8).max, 0x6b175474e89094c44da98b954eedeac495271d0f0000000000000000000000ff);
        _checkId(address(0), type(uint8).max, 0x00000000000000000000000000000000000000000000000000000000000000ff);
        _checkId(address(0), 0, 0x0000000000000000000000000000000000000000000000000000000000000);
        _checkId(address(1), type(uint8).max, 0x00000000000000000000000000000000000000010000000000000000000000ff);
        _checkId(address(1), 0, 0x0000000000000000000000000000000000000001000000000000000000000000);
    }

    function _checkId(address asset, uint8 epoch, uint256 expected) internal {
        uint256 id = CouponKey(asset, Epoch.wrap(epoch)).toId();
        assertEq(id, expected, id.toHexString());
    }
}
