// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {Epoch, EpochLibrary} from "../../../../contracts/libraries/Epoch.sol";

contract EpochUnitTest is Test {
    using EpochLibrary for Epoch;

    function testFromMonths() public {
        assertEq(EpochLibrary.wrap(0).unwrap(), 0);
        assertEq(EpochLibrary.wrap(1).unwrap(), 1);
        assertEq(EpochLibrary.wrap(type(uint16).max).unwrap(), type(uint16).max);
    }

    function testCurrent() public {
        vm.warp(0);
        assertEq(EpochLibrary.current().unwrap(), 0);

        vm.warp(1);
        assertEq(EpochLibrary.current().unwrap(), 0);

        vm.warp(1689578537);
        assertEq(EpochLibrary.current().unwrap(), 2 * (2023 - 1970) + 1); // 17 Jul 2023 07:22:17 GMT

        vm.warp(1961625600);
        assertEq(EpochLibrary.current().unwrap(), 2 * (2032 - 1970)); // 29 Feb 2032 00:00:00 GMT

        vm.warp(1961711999);
        assertEq(EpochLibrary.current().unwrap(), 2 * (2032 - 1970)); // 29 Feb 2032 23:59:59 GMT

        vm.warp(1961712000);
        assertEq(EpochLibrary.current().unwrap(), 2 * (2032 - 1970)); // 1 Mar 2032 00:00:00 GMT

        vm.warp(1961712000);
        assertEq(EpochLibrary.current().unwrap(), 2 * (2032 - 1970)); // 1  Mar 2032 00:00:00 GMT
    }

    function testIsExpired() public {
        vm.warp(1961712000); // 1 Mar 2032 00:00:00 GMT
        assertEq(EpochLibrary.wrap(2 * (2032 - 1970)).isExpired(), false);
        assertEq(EpochLibrary.wrap(2 * (2032 - 1970) + 1).isExpired(), false);
        assertEq(EpochLibrary.wrap(2 * (2032 - 1970) - 1).isExpired(), true);
    }

    function testStartTime() public {
        assertEq(EpochLibrary.wrap(0).startTime(), 0);
        assertEq(EpochLibrary.wrap(1).startTime(), 15638400); // 31 days
        assertEq(EpochLibrary.wrap(12).startTime(), 189302400); // 365 days
        assertEq(EpochLibrary.wrap(13).startTime(), 205027200); // 396 days
        assertEq(EpochLibrary.wrap(24).startTime(), 378691200); // 730 days
        assertEq(EpochLibrary.wrap(25).startTime(), 394329600); // 761 days
        // 1 Mar 2032 00:00:00 GMT
        assertEq(EpochLibrary.wrap(2 * (2032 - 1970)).startTime(), 1956528000);
    }

    function testEndTime() public {
        assertEq(EpochLibrary.wrap(0).endTime(), 15638400); // 6 months
        assertEq(EpochLibrary.wrap(1).endTime(), 31536000); // 12 months
        assertEq(EpochLibrary.wrap(2).endTime(), 47174400); // 18 months
        assertEq(EpochLibrary.wrap(3).endTime(), 63072000); // 24 months
        assertEq(EpochLibrary.wrap(5).endTime(), 94694400); // 36 months
        assertEq(EpochLibrary.wrap(8).endTime(), 141868800); // 54 months
        assertEq(EpochLibrary.wrap(13).endTime(), 220924800); // 84 months
        assertEq(EpochLibrary.wrap(21).endTime(), 347155200); // 132 months
        assertEq(EpochLibrary.wrap(34).endTime(), 552096000); // 210 months
        assertEq(EpochLibrary.wrap(55).endTime(), 883612800); // 336 months
        assertEq(EpochLibrary.wrap(89).endTime(), 1420070400); // 540 months
        assertEq(EpochLibrary.wrap(144).endTime(), 2287785600); // 870 months
    }

    function testLong() public {
        assertEq(EpochLibrary.wrap(0).long(), 15638400); // 181 days
        assertEq(EpochLibrary.wrap(1).long(), 15897600); // 184 days
        assertEq(EpochLibrary.wrap(12).long(), 15724800); // 182 days
        assertEq(EpochLibrary.wrap(13).long(), 15897600); // 184 days
        assertEq(EpochLibrary.wrap(24).long(), 15638400); // 181 days
        assertEq(EpochLibrary.wrap(25).long(), 15897600); // 184 days
        assertEq(EpochLibrary.wrap(27).long(), 15897600); // 184 days
    }

    function testAdd() public {
        Epoch a = EpochLibrary.wrap(1234);
        assertEq(a.add(324).unwrap(), 1558);
    }

    function testSub() public {
        Epoch a = EpochLibrary.wrap(1234);
        assertEq(a.sub(324).unwrap(), 910);
    }

    function testCompare() public {
        Epoch a = EpochLibrary.wrap(1234);
        Epoch b = EpochLibrary.wrap(1234);
        Epoch c = EpochLibrary.wrap(1235);
        assertEq(a.compare(b), 0);
        assertEq(a.compare(c), -1);
        assertEq(c.compare(a), 1);
    }

    function testMax() public {
        Epoch a = EpochLibrary.wrap(1234);
        Epoch b = EpochLibrary.wrap(1234);
        Epoch c = EpochLibrary.wrap(1235);
        assertEq(EpochLibrary.max(a, b).unwrap(), a.unwrap());
        assertEq(EpochLibrary.max(a, c).unwrap(), c.unwrap());
        assertEq(EpochLibrary.max(c, a).unwrap(), c.unwrap());
    }

    function testMaxEpoch() public {
        uint256 endTime = EpochLibrary.wrap(type(uint16).max).endTime();
        assertEq(endTime, 1034058182400);
        vm.warp(endTime - 1);
        Epoch a = EpochLibrary.current();
        assertEq(a.unwrap(), type(uint16).max);
    }
}
