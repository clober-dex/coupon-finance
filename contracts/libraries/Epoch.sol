// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

type Epoch is uint16;

library EpochLibrary {
    error EpochOverflow();

    uint256 internal constant MONTHS_PER_EPOCH = 1;
    uint256 constant SECONDS_PER_DAY = 24 * 60 * 60;
    int256 constant OFFSET19700101 = 2440588;

    function wrap(uint16 epoch) internal pure returns (Epoch) {
        return Epoch.wrap(epoch);
    }

    function unwrap(Epoch epoch) internal pure returns (uint16) {
        return Epoch.unwrap(epoch);
    }

    function startTime(Epoch epoch) internal pure returns (uint256) {
        uint256 currentEpoch = Epoch.unwrap(epoch);
        if (currentEpoch == 0) return 0;
        currentEpoch -= 1;
        return _daysFromMonth(MONTHS_PER_EPOCH * currentEpoch) * SECONDS_PER_DAY;
    }

    function endTime(Epoch epoch) internal pure returns (uint256) {
        return _daysFromMonth(MONTHS_PER_EPOCH * Epoch.unwrap(epoch)) * SECONDS_PER_DAY;
    }

    function isExpired(Epoch epoch) internal view returns (bool) {
        return endTime(epoch) <= block.timestamp;
    }

    function current() internal view returns (Epoch) {
        uint256 epoch = _daysToMonth(block.timestamp / SECONDS_PER_DAY) / MONTHS_PER_EPOCH;
        if (epoch > type(uint16).max) revert EpochOverflow();
        return Epoch.wrap(uint16(epoch));
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

    function compare(Epoch a, Epoch b) internal pure returns (int256) {
        unchecked {
            return Epoch.unwrap(a) > Epoch.unwrap(b)
                ? int256(1)
                : Epoch.unwrap(a) < Epoch.unwrap(b) ? int256(-1) : int256(0);
        }
    }

    function max(Epoch a, Epoch b) internal pure returns (Epoch) {
        return compare(a, b) > 0 ? a : b;
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
    function _daysToMonth(uint256 _days) private pure returns (uint256) {
        require(_days < MONTHS_PER_EPOCH * 2 << 21);

        unchecked {
            int256 __days = int256(_days);

            int256 L = __days + 68569 + OFFSET19700101;
            int256 N = (4 * L) / 146097;
            L = L - (146097 * N + 3) / 4;
            int256 _year = (4000 * (L + 1)) / 1461001;
            L = L - (1461 * _year) / 4 + 31;
            int256 _month = (80 * L) / 2447;
            L = _month / 11;
            _month = _month + 2 - 12 * L;
            _year = 100 * (N - 49) + _year + L;

            return uint256((_year - 1970) * 12 + _month - 1);
        }
    }

    function _daysFromMonth(uint256 months) internal pure returns (uint256) {
        require(months < MONTHS_PER_EPOCH * 2 << 16);
        unchecked {
            uint256 year = months / 12 + 1970;
            months = (months % 12) << 4;
            if (((year % 4 == 0) && (year % 100 != 0)) || (year % 400 == 0)) {
                months = 0x016E014F0131011200F400D500B600980079005B003C001F >> months;
            } else {
                months = 0x016D014E0130011100F300D400B500970078005A003B001F >> months;
            }
            return
                (months & 0xffff) + 365 * (year - 1970) + (year - 1969) / 4 - (year - 1901) / 100 + (year - 1601) / 400;
        }
    }
}
