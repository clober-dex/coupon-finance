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

    function testFromTimestamp() public {
        assertEq(EpochLibrary.fromTimestamp(0).unwrap(), 0);
        assertEq(EpochLibrary.fromTimestamp(1).unwrap(), 0);
        assertEq(EpochLibrary.fromTimestamp(1689578537).unwrap(), 12 * (2023 - 1970) + 7 - 1); // 17 Jul 2023 07:22:17 GMT
        assertEq(EpochLibrary.fromTimestamp(1961625600).unwrap(), 12 * (2032 - 1970) + 2 - 1); // 29 Feb 2032 00:00:00 GMT
        assertEq(EpochLibrary.fromTimestamp(1961711999).unwrap(), 12 * (2032 - 1970) + 2 - 1); // 29 Feb 2032 23:59:59 GMT
        assertEq(EpochLibrary.fromTimestamp(1961712000).unwrap(), 12 * (2032 - 1970) + 3 - 1); // 1  Mar 2032 00:00:00 GMT
    }

    function testCurrent() public {
        vm.warp(1961712000); // 1 Mar 2032 00:00:00 GMT
        assertEq(EpochLibrary.current().unwrap(), 12 * (2032 - 1970) + 3 - 1);
    }

    function testIsExpired() public {
        vm.warp(1961712000); // 1 Mar 2032 00:00:00 GMT
        assertEq(EpochLibrary.wrap(12 * (2032 - 1970) + 3).isExpired(), false);
        assertEq(EpochLibrary.wrap(12 * (2032 - 1970) + 3 - 1).isExpired(), false);
        assertEq(EpochLibrary.wrap(12 * (2032 - 1970) + 3 - 2).isExpired(), true);
    }

    function testStartTime() public {
        assertEq(EpochLibrary.wrap(0).startTime(), 0);
        assertEq(EpochLibrary.wrap(1).startTime(), 2678400); // 31 days
        assertEq(EpochLibrary.wrap(12).startTime(), 31536000); // 365 days
        assertEq(EpochLibrary.wrap(13).startTime(), 34214400); // 396 days
        assertEq(EpochLibrary.wrap(24).startTime(), 63072000); // 730 days
        assertEq(EpochLibrary.wrap(25).startTime(), 65750400); // 761 days
        // 1 Mar 2032 00:00:00 GMT
        assertEq(EpochLibrary.wrap(12 * (2032 - 1970) + 3 - 1).startTime(), 1961712000);
    }

    function testEndTime() public {
        assertEq(EpochLibrary.wrap(0).endTime(), 2678400); // 31 days
        assertEq(EpochLibrary.wrap(1).endTime(), 5097600); // 59 days
        assertEq(EpochLibrary.wrap(12).endTime(), 34214400); // 396 days
        assertEq(EpochLibrary.wrap(13).endTime(), 36633600); // 424 days
        assertEq(EpochLibrary.wrap(24).endTime(), 65750400); // 761 days
        assertEq(EpochLibrary.wrap(25).endTime(), 68256000); // 790 days
        // 1 APR 2032 00:00:00 GMT
        assertEq(EpochLibrary.wrap(12 * (2032 - 1970) + 3 - 1).endTime(), 1964390400);
    }

    function testLong() public {
        assertEq(EpochLibrary.wrap(0).long(), 2678400); // 31 days
        assertEq(EpochLibrary.wrap(1).long(), 2419200); // 28 days
        assertEq(EpochLibrary.wrap(12).long(), 2678400); // 31 days
        assertEq(EpochLibrary.wrap(13).long(), 2419200); // 28 days
        assertEq(EpochLibrary.wrap(24).long(), 2678400); // 31 days
        assertEq(EpochLibrary.wrap(25).long(), 2505600); // 29 days
        assertEq(EpochLibrary.wrap(27).long(), 2592000); // 30 days
        // 1 Mar 2032 00:00:00 GMT
        assertEq(EpochLibrary.wrap(12 * (2032 - 1970) + 3 - 1).long(), 2678400);
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
}
