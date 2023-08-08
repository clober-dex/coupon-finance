// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {IPositionLocker} from "../../../../../contracts/interfaces/IPositionLocker.sol";
import "../../../../../contracts/BondPositionManager.sol";

contract BondPositionMintHelper is IPositionLocker {
    IBondPositionManager public immutable bondPositionManager;

    constructor(address bondPositionManager_) {
        bondPositionManager = IBondPositionManager(bondPositionManager_);
    }

    struct MintParams {
        address asset;
        uint256 amount;
        Epoch expiredWith;
        address recipient;
        address user;
    }

    function mint(address asset, uint256 amount, Epoch expiredWith, address recipient)
        external
        returns (uint256 positionId)
    {
        bytes memory result =
            bondPositionManager.lock(abi.encode(MintParams(asset, amount, expiredWith, recipient, msg.sender)));
        positionId = abi.decode(result, (uint256));
    }

    function positionLockAcquired(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(bondPositionManager), "not bond position manager");
        MintParams memory params = abi.decode(data, (MintParams));

        uint256 positionId = bondPositionManager.mint(params.asset);

        (Coupon[] memory couponsToMint,,) =
            bondPositionManager.adjustPosition(positionId, params.amount, params.expiredWith);

        IERC20(params.asset).approve(address(bondPositionManager), type(uint256).max);
        IERC20(params.asset).transferFrom(params.user, address(this), params.amount);
        bondPositionManager.depositToken(params.asset, params.amount);
        if (couponsToMint.length > 0) {
            bondPositionManager.withdrawCoupons(couponsToMint, params.recipient, "");
        }

        bondPositionManager.settlePosition(positionId);

        if (params.amount > 0) {
            bondPositionManager.transferFrom(address(this), params.recipient, positionId);
        }

        return abi.encode(positionId);
    }
}
