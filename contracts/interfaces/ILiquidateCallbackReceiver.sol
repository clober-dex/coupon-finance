// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface ILiquidateCallbackReceiver {
    function couponFinanceLiquidateCallback(
        uint256 tokenId,
        address collateralToken,
        address debtToken,
        uint256 liquidationAmount,
        uint256 repayAmount,
        bytes calldata data
    ) external;
}
