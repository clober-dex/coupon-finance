// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {IPositionLocker} from "../../../../../contracts/interfaces/IPositionLocker.sol";
import {ICouponManager} from "../../../../../contracts/interfaces/ICouponManager.sol";
import "../../../../../contracts/BondPositionManager.sol";

contract BondPositionAdjustPositionHelper is IPositionLocker, ERC1155Holder {
    IBondPositionManager public immutable bondPositionManager;
    ICouponManager public immutable couponManager;

    constructor(address bondPositionManager_, address couponManager_) {
        bondPositionManager = IBondPositionManager(bondPositionManager_);
        couponManager = ICouponManager(couponManager_);
    }

    struct AdjustPositionParams {
        uint256 positionId;
        uint256 amount;
        Epoch expiredWith;
        address user;
    }

    function adjustPosition(uint256 positionId, uint256 amount, Epoch expiredWith) external {
        bondPositionManager.lock(abi.encode(AdjustPositionParams(positionId, amount, expiredWith, msg.sender)));
    }

    function positionLockAcquired(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(bondPositionManager), "not bond position manager");
        AdjustPositionParams memory params = abi.decode(data, (AdjustPositionParams));

        (Coupon[] memory couponsToMint, Coupon[] memory couponsToBurn, int256 amountDelta) =
            bondPositionManager.adjustPosition(params.positionId, params.amount, params.expiredWith);
        BondPosition memory bondPosition = bondPositionManager.getPosition(params.positionId);

        IERC20(bondPosition.asset).approve(address(bondPositionManager), type(uint256).max);
        if (amountDelta > 0) {
            IERC20(bondPosition.asset).transferFrom(params.user, address(this), uint256(amountDelta));
            bondPositionManager.depositToken(bondPosition.asset, uint256(amountDelta));
        }
        if (amountDelta < 0) {
            bondPositionManager.withdrawToken(bondPosition.asset, params.user, uint256(-amountDelta));
        }
        if (couponsToMint.length > 0) {
            bondPositionManager.mintCoupons(couponsToMint, params.user, "");
        }
        if (couponsToBurn.length > 0) {
            couponManager.safeBatchTransferFrom(params.user, address(this), couponsToBurn, "");
            bondPositionManager.burnCoupons(couponsToBurn);
        }

        bondPositionManager.settlePosition(params.positionId);

        return "";
    }
}
