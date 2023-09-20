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
        assertEq(Epoch.unwrap(EpochLibrary.current()), 2 * (2023 - 1970) + 1); // 17 Jul 2023 07:22:17 GMT

        vm.warp(1961625600);
        assertEq(Epoch.unwrap(EpochLibrary.current()), 2 * (2032 - 1970)); // 29 Feb 2032 00:00:00 GMT

        vm.warp(1961711999);
        assertEq(Epoch.unwrap(EpochLibrary.current()), 2 * (2032 - 1970)); // 29 Feb 2032 23:59:59 GMT

        vm.warp(1961712000);
        assertEq(Epoch.unwrap(EpochLibrary.current()), 2 * (2032 - 1970)); // 1 Mar 2032 00:00:00 GMT

        vm.warp(1961712000);
        assertEq(Epoch.unwrap(EpochLibrary.current()), 2 * (2032 - 1970)); // 1  Mar 2032 00:00:00 GMT
    }

    function testStartTime() public {
        assertEq(Epoch.wrap(0).startTime(), 0);
        assertEq(Epoch.wrap(1).startTime(), 15638400); // 31 days
        assertEq(Epoch.wrap(12).startTime(), 189302400); // 365 days
        assertEq(Epoch.wrap(13).startTime(), 205027200); // 396 days
        assertEq(Epoch.wrap(24).startTime(), 378691200); // 730 days
        assertEq(Epoch.wrap(25).startTime(), 394329600); // 761 days
        // 1 Mar 2032 00:00:00 GMT
        assertEq(Epoch.wrap(2 * (2032 - 1970)).startTime(), 1956528000);
    }

    function testEndTime() public {
        assertEq(Epoch.wrap(0).endTime(), 15638400 - 1); // 6 months
        assertEq(Epoch.wrap(1).endTime(), 31536000 - 1); // 12 months
        assertEq(Epoch.wrap(2).endTime(), 47174400 - 1); // 18 months
        assertEq(Epoch.wrap(3).endTime(), 63072000 - 1); // 24 months
        assertEq(Epoch.wrap(5).endTime(), 94694400 - 1); // 36 months
        assertEq(Epoch.wrap(8).endTime(), 141868800 - 1); // 54 months
        assertEq(Epoch.wrap(13).endTime(), 220924800 - 1); // 84 months
        assertEq(Epoch.wrap(21).endTime(), 347155200 - 1); // 132 months
        assertEq(Epoch.wrap(34).endTime(), 552096000 - 1); // 210 months
        assertEq(Epoch.wrap(55).endTime(), 883612800 - 1); // 336 months
        assertEq(Epoch.wrap(89).endTime(), 1420070400 - 1); // 540 months
        assertEq(Epoch.wrap(144).endTime(), 2287785600 - 1); // 870 months
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
        uint256 endTime = Epoch.wrap(type(uint8).max).endTime();
        assertEq(endTime, 4039372800 - 1);
        vm.warp(endTime);
        Epoch a = EpochLibrary.current();
        assertEq(Epoch.unwrap(a), type(uint8).max);
    }
}
