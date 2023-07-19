// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

interface IBondPositionCallbackReceiver {
    function bondPositionAdjustCallback(
        address operator,
        uint256 tokenId,
        int256 amount,
        int16 lockEpochs,
        bytes calldata data
    ) external;
}
