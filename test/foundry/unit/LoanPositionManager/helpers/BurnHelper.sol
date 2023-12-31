// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {IPositionLocker} from "../../../../../contracts/interfaces/IPositionLocker.sol";
import "../../../../../contracts/LoanPositionManager.sol";

contract LoanPositionBurnHelper is IPositionLocker, ERC1155Holder {
    ILoanPositionManager public immutable loanPositionManager;

    constructor(address loanPositionManager_) {
        loanPositionManager = ILoanPositionManager(loanPositionManager_);
    }

    function burn(uint256 positionId) external {
        loanPositionManager.lock(abi.encode(positionId));
    }

    function positionLockAcquired(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(loanPositionManager), "not loan position manager");
        uint256 positionId = abi.decode(data, (uint256));

        LoanPosition memory position = loanPositionManager.getPosition(positionId);
        loanPositionManager.adjustPosition(positionId, 0, 0, EpochLibrary.lastExpiredEpoch());

        loanPositionManager.withdrawToken(position.collateralToken, address(this), position.collateralAmount);

        loanPositionManager.settlePosition(positionId);

        return "";
    }
}
