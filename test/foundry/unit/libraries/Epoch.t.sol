// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {Epoch, EpochLibrary} from "../../../../contracts/libraries/Epoch.sol";

contract EpochUnitTest is Test {
    using EpochLibrary for Epoch;

    function testCurrent() public {
        vm.warp(0);
        assertEq(Epoch.unwrap(EpochLibrary.current()), 0);

        vm.warp(1);
        assertEq(Epoch.unwrap(EpochLibrary.current()), 0);

        vm.warp(1689578537);
        assertEq(Epoch.unwrap(EpochLibrary.current()), 12 * (2023 - 1970) + 6); // 17 Jul 2023 07:22:17 GMT

        vm.warp(1961625600);
        assertEq(Epoch.unwrap(EpochLibrary.current()), 12 * (2032 - 1970) + 1); // 29 Feb 2032 00:00:00 GMT

        vm.warp(1961711999);
        assertEq(Epoch.unwrap(EpochLibrary.current()), 12 * (2032 - 1970) + 1); // 29 Feb 2032 23:59:59 GMT

        vm.warp(1961712000);
        assertEq(Epoch.unwrap(EpochLibrary.current()), 12 * (2032 - 1970) + 2); // 1 Mar 2032 00:00:00 GMT
    }

    function testStartTime() public {
        assertEq(Epoch.wrap(0).startTime(), 0);
        assertEq(Epoch.wrap(1).startTime(), 2678400); // 31 days
        assertEq(Epoch.wrap(12).startTime(), 31536000); // 365 days
        assertEq(Epoch.wrap(13).startTime(), 34214400); // 396 days
        assertEq(Epoch.wrap(24).startTime(), 63072000); // 730 days
        assertEq(Epoch.wrap(25).startTime(), 65750400); // 761 days
        // 1 Mar 2032 00:00:00 GMT
        assertEq(Epoch.wrap(12 * (2032 - 1970)).startTime(), 1956528000);
    }

    function testEndTime() public {
        assertEq(Epoch.wrap(0).endTime(), 2678400 - 1); // 1 months
        assertEq(Epoch.wrap(1).endTime(), 5097600 - 1); // 2 months
        assertEq(Epoch.wrap(2).endTime(), 7776000 - 1); // 3 months
        assertEq(Epoch.wrap(3).endTime(), 10368000 - 1); // 4 months
        assertEq(Epoch.wrap(5).endTime(), 15638400 - 1); // 6 months
        assertEq(Epoch.wrap(8).endTime(), 23587200 - 1); // 9 months
        assertEq(Epoch.wrap(13).endTime(), 36633600 - 1); // 14 months
        assertEq(Epoch.wrap(21).endTime(), 57801600 - 1); // 22 months
        assertEq(Epoch.wrap(34).endTime(), 92016000 - 1); // 35 months
        assertEq(Epoch.wrap(55).endTime(), 147225600 - 1); // 56 months
        assertEq(Epoch.wrap(89).endTime(), 236563200 - 1); // 90 months
        assertEq(Epoch.wrap(144).endTime(), 381369600 - 1); // 145 months
    }

    function testAdd() public {
        Epoch a = Epoch.wrap(123);
        assertEq(Epoch.unwrap(a.add(32)), 155);
    }

    function testSub() public {
        Epoch a = Epoch.wrap(123);
        assertEq(Epoch.unwrap(a.sub(32)), 91);
    }

    function testCompare() public {
        Epoch a = Epoch.wrap(124);
        Epoch b = Epoch.wrap(124);
        Epoch c = Epoch.wrap(125);
        assertEq(a == b, true);
        assertEq(a < c, true);
        assertEq(c > a, true);
    }

    function testMax() public {
        Epoch a = Epoch.wrap(124);
        Epoch b = Epoch.wrap(124);
        Epoch c = Epoch.wrap(125);
        assertEq(Epoch.unwrap(EpochLibrary.max(a, b)), Epoch.unwrap(a));
        assertEq(Epoch.unwrap(EpochLibrary.max(a, c)), Epoch.unwrap(c));
        assertEq(Epoch.unwrap(EpochLibrary.max(c, a)), Epoch.unwrap(c));
    }

    function testMaxEpoch() public {
        uint256 endTime = Epoch.wrap(type(uint16).max).endTime();
        assertEq(endTime, 172342857600 - 1);
        vm.warp(endTime);
        Epoch a = EpochLibrary.current();
        assertEq(Epoch.unwrap(a), type(uint16).max);
    }
}
