// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IController} from "./IController.sol";

interface IBorrowAdapter is IController {
    error CollateralSwapFailed(string reason);

    function borrow(
        address collateralToken,
        address debtToken,
        uint256 collateralAmount,
        uint256 borrowAmount,
        uint256 maxPayInterest,
        uint8 loanEpochs,
        bytes memory swapData,
        ERC20PermitParams calldata collateralPermitParams
    ) external payable;
}
