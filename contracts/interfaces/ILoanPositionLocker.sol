// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

interface ILoanPositionLocker {
    function loanPositionLockAcquired(bytes calldata data) external returns (bytes memory);
}
