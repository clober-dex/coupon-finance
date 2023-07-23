// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

type Epoch is uint16;

library EpochLibrary {
    uint256 internal constant MONTHS_PER_EPOCH = 1;
    uint256 constant SECONDS_PER_DAY = 24 * 60 * 60;
    int constant OFFSET19700101 = 2440588;

    function wrap(uint16 epoch) internal pure returns (Epoch) {
        return Epoch.wrap(epoch);
    }

    function fromMonths(uint256 months) internal pure returns (Epoch) {
        unchecked {
            months /= MONTHS_PER_EPOCH;
        }
        if (months > type(uint16).max) revert("Epoch: Overflow");
        return Epoch.wrap(uint16(months));
    }

    function fromTimestamp(uint256 timestamp) internal pure returns (Epoch) {
        return fromMonths(diffMonths(0, timestamp));
    }

    function current() internal view returns (Epoch) {
        return fromTimestamp(block.timestamp);
    }

    function isExpired(Epoch epoch) internal view returns (bool) {
        return endTime(epoch) <= block.timestamp;
    }

    function startTime(Epoch epoch) internal pure returns (uint256) {
        unchecked {
            return addMonths(0, MONTHS_PER_EPOCH * Epoch.unwrap(epoch));
        }
    }

    function endTime(Epoch epoch) internal pure returns (uint256) {
        unchecked {
            uint256 nextEpoch = uint256(Epoch.unwrap(epoch)) + 1;
            return addMonths(0, MONTHS_PER_EPOCH * nextEpoch);
        }
    }

    function long(Epoch epoch) internal pure returns (uint256) {
        unchecked {
            return endTime(epoch) - startTime(epoch);
        }
    }

    function add(Epoch epoch, uint16 epochs) internal pure returns (Epoch) {
        return Epoch.wrap(Epoch.unwrap(epoch) + epochs);
    }

    function sub(Epoch epoch, uint16 epochs) internal pure returns (Epoch) {
        return Epoch.wrap(Epoch.unwrap(epoch) - epochs);
    }

    function sub(Epoch e1, Epoch e2) internal pure returns (uint16) {
        return Epoch.unwrap(e1) - Epoch.unwrap(e2);
    }

    function unwrap(Epoch epoch) internal pure returns (uint16) {
        return Epoch.unwrap(epoch);
    }

    function compare(Epoch a, Epoch b) internal pure returns (int256) {
        unchecked {
            return
                Epoch.unwrap(a) > Epoch.unwrap(b) ? int256(1) : Epoch.unwrap(a) < Epoch.unwrap(b)
                    ? int256(-1)
                    : int256(0);
        }
    }

    function max(Epoch a, Epoch b) internal pure returns (Epoch) {
        return compare(a, b) > 0 ? a : b;
    }

    function diffMonths(uint fromTimestamp, uint toTimestamp) internal pure returns (uint _months) {
        require(fromTimestamp <= toTimestamp);
        (uint fromYear, uint fromMonth, ) = _daysToDate(fromTimestamp / SECONDS_PER_DAY);
        (uint toYear, uint toMonth, ) = _daysToDate(toTimestamp / SECONDS_PER_DAY);
        _months = toYear * 12 + toMonth - fromYear * 12 - fromMonth;
    }

    function addMonths(uint timestamp, uint _months) internal pure returns (uint newTimestamp) {
        (uint year, uint month, uint day) = _daysToDate(timestamp / SECONDS_PER_DAY);
        month += _months;
        year += (month - 1) / 12;
        month = ((month - 1) % 12) + 1;
        uint daysInMonth = _getDaysInMonth(year, month);
        if (day > daysInMonth) {
            day = daysInMonth;
        }
        newTimestamp = _daysFromDate(year, month, day) * SECONDS_PER_DAY + (timestamp % SECONDS_PER_DAY);
        require(newTimestamp >= timestamp);
    }

    // ------------------------------------------------------------------------
    // Calculate year/month/day from the number of days since 1970/01/01 using
    // the date conversion algorithm from
    //   http://aa.usno.navy.mil/faq/docs/JD_Formula.php
    // and adding the offset 2440588 so that 1970/01/01 is day 0
    //
    // int L = days + 68569 + offset
    // int N = 4 * L / 146097
    // L = L - (146097 * N + 3) / 4
    // year = 4000 * (L + 1) / 1461001
    // L = L - 1461 * year / 4 + 31
    // month = 80 * L / 2447
    // dd = L - 2447 * month / 80
    // L = month / 11
    // month = month + 2 - 12 * L
    // year = 100 * (N - 49) + year + L
    // ------------------------------------------------------------------------
    function _daysToDate(uint _days) internal pure returns (uint year, uint month, uint day) {
        int __days = int(_days);

        int L = __days + 68569 + OFFSET19700101;
        int N = (4 * L) / 146097;
        L = L - (146097 * N + 3) / 4;
        int _year = (4000 * (L + 1)) / 1461001;
        L = L - (1461 * _year) / 4 + 31;
        int _month = (80 * L) / 2447;
        int _day = L - (2447 * _month) / 80;
        L = _month / 11;
        _month = _month + 2 - 12 * L;
        _year = 100 * (N - 49) + _year + L;

        year = uint(_year);
        month = uint(_month);
        day = uint(_day);
    }

    function _getDaysInMonth(uint year, uint month) internal pure returns (uint daysInMonth) {
        if (month == 1 || month == 3 || month == 5 || month == 7 || month == 8 || month == 10 || month == 12) {
            daysInMonth = 31;
        } else if (month != 2) {
            daysInMonth = 30;
        } else {
            daysInMonth = _isLeapYear(year) ? 29 : 28;
        }
    }

    function _isLeapYear(uint year) internal pure returns (bool leapYear) {
        leapYear = ((year % 4 == 0) && (year % 100 != 0)) || (year % 400 == 0);
    }

    // ------------------------------------------------------------------------
    // Calculate the number of days from 1970/01/01 to year/month/day using
    // the date conversion algorithm from
    //   https://aa.usno.navy.mil/faq/JD_formula.html
    // and subtracting the offset 2440588 so that 1970/01/01 is day 0
    //
    // days = day
    //      - 32075
    //      + 1461 * (year + 4800 + (month - 14) / 12) / 4
    //      + 367 * (month - 2 - (month - 14) / 12 * 12) / 12
    //      - 3 * ((year + 4900 + (month - 14) / 12) / 100) / 4
    //      - offset
    // ------------------------------------------------------------------------
    function _daysFromDate(uint year, uint month, uint day) internal pure returns (uint _days) {
        require(year >= 1970);
        int _year = int(year);
        int _month = int(month);
        int _day = int(day);

        int __days = _day -
            32075 +
            (1461 * (_year + 4800 + (_month - 14) / 12)) /
            4 +
            (367 * (_month - 2 - ((_month - 14) / 12) * 12)) /
            12 -
            (3 * ((_year + 4900 + (_month - 14) / 12) / 100)) /
            4 -
            OFFSET19700101;

        _days = uint(__days);
    }
}
