// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Types} from "../../contracts/Types.sol";

library ERC20Utils {
    function amount(IERC20 token, uint256 ethers) internal view returns (uint256) {
        return ethers * 10 ** (IERC20Metadata(address(token)).decimals());
    }
}

library Utils {
    function toArray(Types.Coupon memory coupon) internal pure returns (Types.Coupon[] memory arr) {
        arr = new Types.Coupon[](1);
        arr[0] = coupon;
    }
}

library ForkUtils {
    function fork(Vm vm, uint256 blockNumber) public {
        uint256 newFork = vm.createFork(vm.envString("FORK_TEST_NODE_URL"));
        vm.selectFork(newFork);
        vm.rollFork(blockNumber);
    }
}
