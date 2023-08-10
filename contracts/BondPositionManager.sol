// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {IBondPositionManager} from "./interfaces/IBondPositionManager.sol";
import {ICouponManager} from "./interfaces/ICouponManager.sol";
import {IPositionManager} from "./interfaces/IPositionManager.sol";
import {IAssetPool} from "./interfaces/IAssetPool.sol";
import {IBondPositionCallbackReceiver} from "./interfaces/IBondPositionCallbackReceiver.sol";
import {ERC721Permit} from "./libraries/ERC721Permit.sol";
import {BondPosition, BondPositionLibrary} from "./libraries/BondPosition.sol";
import {Coupon, CouponLibrary} from "./libraries/Coupon.sol";
import {Epoch, EpochLibrary} from "./libraries/Epoch.sol";
import {PositionManager} from "./libraries/PositionManager.sol";

contract BondPositionManager is IBondPositionManager, PositionManager, Ownable {
    using SafeCast for uint256;
    using SafeERC20 for IERC20;
    using Strings for uint256;
    using EpochLibrary for Epoch;
    using BondPositionLibrary for BondPosition;
    using CouponLibrary for Coupon;

    Epoch private constant _MAX_EPOCH = Epoch.wrap(157); // Ends at 31 Dec 2048 23:59:59 GMT

    mapping(address asset => bool) public override isAssetRegistered;
    mapping(uint256 id => BondPosition) private _positionMap;

    constructor(address coupon_, address assetPool_, string memory baseURI_)
        PositionManager(coupon_, assetPool_, baseURI_, "Bond Position", "BP")
    {}

    function getMaxEpoch() external pure returns (Epoch maxEpoch) {
        return _MAX_EPOCH;
    }

    function getPosition(uint256 positionId) external view returns (BondPosition memory) {
        return _positionMap[positionId];
    }

    function mint(address asset) external onlyByLocker returns (uint256 positionId) {
        if (!isAssetRegistered[asset]) {
            revert UnregisteredAsset();
        }

        unchecked {
            positionId = nextId++;
        }
        _positionMap[positionId].asset = asset;
        _mint(msg.sender, positionId);
    }

    function adjustPosition(uint256 positionId, uint256 amount, Epoch expiredWith)
        external
        onlyByLocker
        modifyPosition(positionId)
        returns (Coupon[] memory couponsToMint, Coupon[] memory couponsToBurn, int256 amountDelta)
    {
        if (!_isApprovedOrOwner(msg.sender, positionId)) {
            revert InvalidAccess();
        }
        Epoch lastExpiredEpoch = EpochLibrary.lastExpiredEpoch();
        if (amount == 0 || expiredWith == Epoch.wrap(0)) {
            amount = 0;
            expiredWith = lastExpiredEpoch;
        }

        if (expiredWith < lastExpiredEpoch || _MAX_EPOCH < expiredWith) {
            revert InvalidEpoch();
        }

        BondPosition memory position = _positionMap[positionId];

        _positionMap[positionId].amount = amount;
        if (Epoch.wrap(0) < position.expiredWith && position.expiredWith <= lastExpiredEpoch) {
            if (amount > 0) revert AlreadyExpired();
        } else {
            _positionMap[positionId].expiredWith = expiredWith;
            if (position.expiredWith == Epoch.wrap(0)) {
                position.expiredWith = lastExpiredEpoch;
            }

            (couponsToMint, couponsToBurn) = position.calculateCouponRequirement(_positionMap[positionId]);
        }

        if (couponsToMint.length > 0) {
            for (uint256 i = 0; i < couponsToMint.length; ++i) {
                _accountDelta(couponsToMint[i].id(), -couponsToMint[i].amount.toInt256());
            }
        }
        if (position.amount > amount) {
            amountDelta = -(position.amount - amount).toInt256();
            _accountDelta(uint256(uint160(position.asset)), amountDelta);
        }
        if (amount > position.amount) {
            amountDelta = (amount - position.amount).toInt256();
            _accountDelta(uint256(uint160(position.asset)), amountDelta);
        }
        if (couponsToBurn.length > 0) {
            for (uint256 i = 0; i < couponsToBurn.length; ++i) {
                _accountDelta(couponsToBurn[i].id(), couponsToBurn[i].amount.toInt256());
            }
        }
    }

    function settlePosition(uint256 positionId) public override(IPositionManager, PositionManager) onlyByLocker {
        super.settlePosition(positionId);
        BondPosition memory position = _positionMap[positionId];
        if (_MAX_EPOCH < position.expiredWith) {
            revert InvalidEpoch();
        }
        if (position.amount == 0) {
            _burn(positionId);
        } else {
            if (position.expiredWith < EpochLibrary.current()) {
                revert InvalidEpoch();
            }
        }
        emit PositionUpdated(positionId, position.amount, position.expiredWith);
    }

    function registerAsset(address asset) external onlyOwner {
        _registerAsset(asset);
    }

    function nonces(uint256 positionId) external view returns (uint256) {
        return _positionMap[positionId].nonce;
    }

    function _registerAsset(address asset) internal {
        isAssetRegistered[asset] = true;
        emit AssetRegistered(asset);
    }

    function _getAndIncrementNonce(uint256 positionId) internal override returns (uint256) {
        return _positionMap[positionId].getAndIncrementNonce();
    }

    function _isSettled(uint256 positionId) internal view override returns (bool) {
        return _positionMap[positionId].isSettled;
    }

    function _setPositionSettlement(uint256 positionId, bool settled) internal override {
        _positionMap[positionId].isSettled = settled;
    }
}
