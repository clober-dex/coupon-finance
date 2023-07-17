// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {Types} from "../../../../contracts/Types.sol";
import {BokkyPooBahsDateTimeLibrary} from "../../../../contracts/libraries/BokkyPooBahsDateTimeLibrary.sol";
import {Epoch} from "../../../../contracts/libraries/Epoch.sol";

contract EpochUnitTest is Test {
    using Epoch for Types.Epoch;

    function testFromMonths() public {
        assertEq(Epoch.fromMonths(0).unwrap(), 0);
        assertEq(Epoch.fromMonths(1).unwrap(), 1);
        assertEq(Epoch.fromMonths(type(uint16).max).unwrap(), type(uint16).max);
    }

    function testFromMonthsOverflow() public {
        vm.expectRevert("Epoch: Overflow");
        Epoch.fromMonths(uint256(type(uint16).max) + 1);
    }

    function testFromTimestamp() public {
        assertEq(Epoch.fromTimestamp(0).unwrap(), 0);
        assertEq(Epoch.fromTimestamp(1).unwrap(), 0);
        assertEq(Epoch.fromTimestamp(1689578537).unwrap(), 12 * (2023 - 1970) + 7 - 1); // 17 Jul 2023 07:22:17 GMT
        assertEq(Epoch.fromTimestamp(1961625600).unwrap(), 12 * (2032 - 1970) + 2 - 1); // 29 Feb 2032 00:00:00 GMT
        assertEq(Epoch.fromTimestamp(1961711999).unwrap(), 12 * (2032 - 1970) + 2 - 1); // 29 Feb 2032 23:59:59 GMT
        assertEq(Epoch.fromTimestamp(1961712000).unwrap(), 12 * (2032 - 1970) + 3 - 1); // 1  Mar 2032 00:00:00 GMT
    }

    function testCurrent() public {
        vm.warp(1961712000); // 1 Mar 2032 00:00:00 GMT
        assertEq(Epoch.current().unwrap(), 12 * (2032 - 1970) + 3 - 1);
    }

    function testStartTime() public {
        assertEq(Epoch.fromMonths(0).startTime(), 0);
        assertEq(Epoch.fromMonths(1).startTime(), 2678400); // 31 days
        assertEq(Epoch.fromMonths(12).startTime(), 31536000); // 365 days
        assertEq(Epoch.fromMonths(13).startTime(), 34214400); // 396 days
        assertEq(Epoch.fromMonths(24).startTime(), 63072000); // 730 days
        assertEq(Epoch.fromMonths(25).startTime(), 65750400); // 761 days
        // 1 Mar 2032 00:00:00 GMT
        assertEq(Epoch.fromMonths(12 * (2032 - 1970) + 3 - 1).startTime(), 1961712000);
    }

    function testEndTime() public {
        assertEq(Epoch.fromMonths(0).endTime(), 2678399); // 31 days - 1 second
        assertEq(Epoch.fromMonths(1).endTime(), 5097599); // 59 days - 1 second
        assertEq(Epoch.fromMonths(12).endTime(), 34214399); // 396 days - 1 second
        assertEq(Epoch.fromMonths(13).endTime(), 36633599); // 424 days - 1 second
        assertEq(Epoch.fromMonths(24).endTime(), 65750399); // 761 days - 1 second
        assertEq(Epoch.fromMonths(25).endTime(), 68255999); // 790 days - 1 second
        // 1 APR 2032 00:00:00 GMT - 1 second
        assertEq(Epoch.fromMonths(12 * (2032 - 1970) + 3 - 1).endTime(), 1964390399);
    }

    function testLong() public {
        assertEq(Epoch.fromMonths(0).long(), 2678400); // 31 days
        assertEq(Epoch.fromMonths(1).long(), 2419200); // 28 days
        assertEq(Epoch.fromMonths(12).long(), 2678400); // 31 days
        assertEq(Epoch.fromMonths(13).long(), 2419200); // 28 days
        assertEq(Epoch.fromMonths(24).long(), 2678400); // 31 days
        assertEq(Epoch.fromMonths(25).long(), 2505600); // 29 days
        assertEq(Epoch.fromMonths(27).long(), 2592000); // 30 days
        // 1 Mar 2032 00:00:00 GMT
        assertEq(Epoch.fromMonths(12 * (2032 - 1970) + 3 - 1).long(), 2678400);
    }

    function testAdd() public {
        Types.Epoch a = Epoch.fromMonths(1234);
        assertEq(a.add(324).unwrap(), 1558);
    }
}
