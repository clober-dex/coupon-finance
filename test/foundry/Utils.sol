// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Coupon} from "../../contracts/libraries/Coupon.sol";

library ERC20Utils {
    function amount(IERC20 token, uint256 ethers) internal view returns (uint256) {
        return ethers * 10 ** (IERC20Metadata(address(token)).decimals());
    }
}

library Utils {
    function toArr(Coupon memory coupon) internal pure returns (Coupon[] memory arr) {
        arr = new Coupon[](1);
        arr[0] = coupon;
    }

    function toArr(address account) internal pure returns (address[] memory arr) {
        arr = new address[](1);
        arr[0] = account;
    }

    function toArr(address account0, address account1) internal pure returns (address[] memory arr) {
        arr = new address[](2);
        arr[0] = account0;
        arr[1] = account1;
    }

    function toArr(address account0, address account1, address account2) internal pure returns (address[] memory arr) {
        arr = new address[](3);
        arr[0] = account0;
        arr[1] = account1;
        arr[2] = account2;
    }

    function toArr(address[] memory arr) internal pure returns (address[][] memory nested) {
        nested = new address[][](1);
        nested[0] = arr;
    }

    function toArr(address[] memory arr0, address[] memory arr1) internal pure returns (address[][] memory nested) {
        nested = new address[][](2);
        nested[0] = arr0;
        nested[1] = arr1;
    }

    function toArr(address[] memory arr0, address[] memory arr1, address[] memory arr2)
        internal
        pure
        returns (address[][] memory nested)
    {
        nested = new address[][](3);
        nested[0] = arr0;
        nested[1] = arr1;
        nested[2] = arr2;
    }

    function toArr(uint256 n0) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](1);
        arr[0] = n0;
    }

    function toArr(uint256 n0, uint256 n1) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](2);
        arr[0] = n0;
        arr[1] = n1;
    }

    function toArr(uint256 n0, uint256 n1, uint256 n2) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](3);
        arr[0] = n0;
        arr[1] = n1;
        arr[2] = n2;
    }
}

library ForkUtils {
    function fork(Vm vm, uint256 blockNumber) public {
        uint256 newFork = vm.createFork(vm.envString("FORK_URL"));
        vm.selectFork(newFork);
        vm.rollFork(blockNumber);
    }
}
