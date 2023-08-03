// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ERC1155Holder, ERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {IAssetPool} from "../interfaces/IAssetPool.sol";
import {ICouponManager} from "../interfaces/ICouponManager.sol";
import {IPositionLocker} from "../interfaces/IPositionLocker.sol";
import {ERC721Permit, IERC165} from "./ERC721Permit.sol";
import {LockData, LockDataLibrary} from "./LockData.sol";
import {Coupon, CouponLibrary} from "./Coupon.sol";
import {IPositionManager} from "../interfaces/IPositionManager.sol";

abstract contract PositionManager is ERC721Permit, ERC1155Holder, IPositionManager {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using CouponLibrary for Coupon;
    using LockDataLibrary for LockData;

    address internal immutable _couponManager;
    address public immutable override assetPool;

    string public override baseURI;
    uint256 private _nextId = 1;

    LockData public override lockData;

    mapping(address locker => mapping(uint256 assetId => int256 delta)) public override assetDelta;
    // todo: merge this storage into _positionMap
    mapping(uint256 positionId => bool) public override unsettledPosition;

    constructor(
        address couponManager_,
        address assetPool_,
        string memory baseURI_,
        string memory name_,
        string memory symbol_
    ) ERC721Permit(name_, symbol_, "1") {
        _couponManager = couponManager_;
        assetPool = assetPool_;
        baseURI = baseURI_;
    }

    modifier onlyByLocker() {
        address locker = lockData.getActiveLock();
        if (msg.sender != locker) revert LockedBy(locker);
        _;
    }

    function lock(bytes calldata data) external returns (bytes memory result) {
        lockData.push(msg.sender);

        result = IPositionLocker(msg.sender).positionLockAcquired(data);

        if (lockData.length == 1) {
            if (lockData.nonzeroDeltaCount != 0) revert NotSettled();
            delete lockData;
        } else {
            lockData.pop();
        }
    }

    function _markUnsettled(uint256 positionId) internal {
        if (unsettledPosition[positionId]) return;
        unsettledPosition[positionId] = true;
        unchecked {
            lockData.nonzeroDeltaCount++;
        }
    }

    function _markSettled(uint256 positionId) internal {
        if (!unsettledPosition[positionId]) return;
        delete unsettledPosition[positionId];
        unchecked {
            lockData.nonzeroDeltaCount--;
        }
    }

    function _accountDelta(uint256 assetId, int256 delta) internal {
        if (delta == 0) return;

        address locker = lockData.getActiveLock();
        int256 current = assetDelta[locker][assetId];
        int256 next = current + delta;

        unchecked {
            if (next == 0) {
                lockData.nonzeroDeltaCount--;
            } else if (current == 0) {
                lockData.nonzeroDeltaCount++;
            }
        }

        assetDelta[locker][assetId] = next;
    }

    function withdrawToken(address token, address to, uint256 amount) external onlyByLocker {
        _accountDelta(uint256(uint160(token)), amount.toInt256());
        IAssetPool(assetPool).withdraw(token, amount, to);
    }

    function withdrawCoupons(Coupon[] calldata coupons, address to, bytes calldata data) external onlyByLocker {
        unchecked {
            for (uint256 i = 0; i < coupons.length; ++i) {
                _accountDelta(coupons[i].id(), coupons[i].amount.toInt256());
            }
            ICouponManager(_couponManager).safeBatchTransferFrom(address(this), to, coupons, data);
        }
    }

    function depositToken(address token, uint256 amount) external onlyByLocker {
        if (amount == 0) return;
        IERC20(token).safeTransferFrom(msg.sender, assetPool, amount);
        IAssetPool(assetPool).deposit(token, amount);
        _accountDelta(uint256(uint160(token)), -amount.toInt256());
    }

    function depositCoupons(Coupon[] calldata coupons) external onlyByLocker {
        unchecked {
            ICouponManager(_couponManager).safeBatchTransferFrom(msg.sender, address(this), coupons, "");
            for (uint256 i = 0; i < coupons.length; ++i) {
                _accountDelta(coupons[i].id(), -coupons[i].amount.toInt256());
            }
        }
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function nextId() external view override returns (uint256) {
        return _nextId;
    }

    function _getAndIncreaseId() internal returns (uint256 id) {
        id = _nextId;
        _nextId++;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721Permit, ERC1155Receiver, IERC165)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}