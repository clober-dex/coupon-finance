// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "../../../../../contracts/LoanPositionManager.sol";

contract LoanPositionAdjustPositionHelper is ILoanPositionLocker, ERC1155Holder {
    ILoanPositionManager public immutable loanPositionManager;

    constructor(address loanPositionManager_) {
        loanPositionManager = ILoanPositionManager(loanPositionManager_);
    }

    struct AdjustPositionParams {
        uint256 positionId;
        uint256 collateralAmount;
        uint256 debtAmount;
        Epoch expiredWith;
    }

    function adjustPosition(uint256 positionId, uint256 collateralAmount, uint256 debtAmount, Epoch expiredWith)
        external
    {
        loanPositionManager.lock(
            abi.encode(AdjustPositionParams(positionId, collateralAmount, debtAmount, expiredWith))
        );
    }

    function loanPositionLockAcquired(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(loanPositionManager), "not loan position manager");
        AdjustPositionParams memory params = abi.decode(data, (AdjustPositionParams));

        (Coupon[] memory couponsToPay, Coupon[] memory couponsToRefund, int256 collateralDelta, int256 debtDelta) =
        loanPositionManager.adjustPosition(
            params.positionId, params.collateralAmount, params.debtAmount, params.expiredWith
        );
        LoanPosition memory position = loanPositionManager.getPosition(params.positionId);
        if (collateralDelta > 0) {
            loanPositionManager.depositToken(position.collateralToken, uint256(collateralDelta));
        } else if (collateralDelta < 0) {
            loanPositionManager.withdrawToken(position.collateralToken, address(this), uint256(-collateralDelta));
        }

        if (debtDelta > 0) {
            loanPositionManager.withdrawToken(position.debtToken, address(this), uint256(debtDelta));
        } else if (debtDelta < 0) {
            loanPositionManager.depositToken(position.debtToken, uint256(-debtDelta));
        }

        if (couponsToPay.length > 0) {
            loanPositionManager.depositCoupons(couponsToPay);
        }
        if (couponsToRefund.length > 0) {
            loanPositionManager.withdrawCoupons(couponsToRefund, address(this), new bytes(0));
        }

        loanPositionManager.settlePosition(params.positionId);

        return new bytes(0);
    }
}
