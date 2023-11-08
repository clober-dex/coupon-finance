// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

interface ICouponLiquidator {
    error CollateralSwapFailed(string reason);

    function liquidate(uint256 positionId, uint256 maxRepayAmount, bytes memory swapData)
        external
        returns (bytes memory result);

    function collectFee(address token, address recipient) external;
}
