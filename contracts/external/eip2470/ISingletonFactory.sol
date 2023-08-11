// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

interface ISingletonFactory {
    function deploy(bytes calldata initCode, bytes32 salt) external returns (address payable);
}
