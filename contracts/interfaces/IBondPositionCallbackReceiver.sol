// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {Types} from "../Types.sol";

interface IBondPositionCallbackReceiver {
    function bondPositionAdjustCallback(
        address operator,
        uint256 tokenId,
        Types.BondPosition memory position,
        bytes calldata data
    ) external;
}
