// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "../../../../../contracts/LoanPositionManager.sol";

contract LoanPositionLiquidateHelper is ILoanPositionLocker, ERC1155Holder {
    ILoanPositionManager public immutable loanPositionManager;

    constructor(address loanPositionManager_) {
        loanPositionManager = ILoanPositionManager(loanPositionManager_);
    }

    function liquidate(uint256 positionId, uint256 maxRepayAmount) external {
        loanPositionManager.lock(abi.encode(positionId, maxRepayAmount));
    }

    function lockAcquired(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(loanPositionManager), "not loan position manager");
        (uint256 positionId, uint256 maxRepayAmount) = abi.decode(data, (uint256, uint256));

        LoanPosition memory position = loanPositionManager.getPosition(positionId);
        (uint256 liquidationAmount, uint256 repayAmount, uint256 protocolFeeAmount) =
            loanPositionManager.liquidate(positionId, maxRepayAmount);

        loanPositionManager.withdrawToken(
            position.collateralToken, address(this), liquidationAmount - protocolFeeAmount
        );
        loanPositionManager.depositToken(position.debtToken, repayAmount);

        return "";
    }
}
