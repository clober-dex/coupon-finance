// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {IPositionLocker} from "../../../../../contracts/interfaces/IPositionLocker.sol";
import {Epoch, EpochLibrary} from "../../../../../contracts/libraries/Epoch.sol";
import "../../../../../contracts/LoanPositionManager.sol";

contract LoanPositionMintHelper is IPositionLocker, ERC1155Holder {
    using EpochLibrary for Epoch;

    ILoanPositionManager public immutable loanPositionManager;

    constructor(address loanPositionManager_) {
        loanPositionManager = ILoanPositionManager(loanPositionManager_);
    }

    struct MintParams {
        address collateralToken;
        address debtToken;
        uint256 collateralAmount;
        uint256 debtAmount;
        Epoch expiredWith;
        address recipient;
    }

    function mint(
        address collateralToken,
        address debtToken,
        uint256 collateralAmount,
        uint256 debtAmount,
        Epoch expiredWith,
        address recipient
    ) external returns (uint256 positionId) {
        bytes memory result = loanPositionManager.lock(
            abi.encode(MintParams(collateralToken, debtToken, collateralAmount, debtAmount, expiredWith, recipient))
        );
        positionId = abi.decode(result, (uint256));
    }

    function positionLockAcquired(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(loanPositionManager), "not loan position manager");
        MintParams memory params = abi.decode(data, (MintParams));

        uint256 positionId = loanPositionManager.mint(params.collateralToken, params.debtToken);

        (, Coupon[] memory couponsToBurn,,) = loanPositionManager.adjustPosition(
            positionId,
            params.collateralAmount,
            params.debtAmount,
            params.debtAmount == 0 ? EpochLibrary.lastExpiredEpoch() : params.expiredWith
        );

        loanPositionManager.depositToken(params.collateralToken, params.collateralAmount);
        loanPositionManager.withdrawToken(params.debtToken, params.recipient, params.debtAmount);
        if (couponsToBurn.length > 0) {
            loanPositionManager.burnCoupons(couponsToBurn);
        }

        loanPositionManager.settlePosition(positionId);

        loanPositionManager.transferFrom(address(this), params.recipient, positionId);

        return abi.encode(positionId);
    }
}
