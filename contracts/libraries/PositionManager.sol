// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
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
    using CouponLibrary for Coupon;
    using LockDataLibrary for LockData;

    address internal immutable _couponManager;
    address public immutable override assetPool;

    string public override baseURI;
    uint256 public override nextId = 1;

    LockData private _lockData;

    // @dev Since the epoch is greater than 0, the coupon ID and address can never be the same.
    mapping(address locker => mapping(uint256 assetId => int256 delta)) public override assetDelta;

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

    modifier modifyPosition(uint256 positionId) {
        _;
        _unsettlePosition(positionId);
    }

    modifier onlyByLocker() {
        address locker = _lockData.getActiveLock();
        if (msg.sender != locker) revert LockedBy(locker);
        _;
    }

    function lock(bytes calldata data) external returns (bytes memory result) {
        _lockData.push(msg.sender);

        result = IPositionLocker(msg.sender).positionLockAcquired(data);

        if (_lockData.length == 1) {
            if (_lockData.nonzeroDeltaCount != 0) revert NotSettled();
            delete _lockData;
        } else {
            _lockData.pop();
        }
    }

    function _isSettled(uint256 positionId) internal view virtual returns (bool);

    function _setPositionSettlement(uint256 positionId, bool settled) internal virtual;

    function _unsettlePosition(uint256 positionId) internal {
        if (!_isSettled(positionId)) return;
        _setPositionSettlement(positionId, false);
        unchecked {
            _lockData.nonzeroDeltaCount++;
        }
    }

    function _accountDelta(uint256 assetId, uint256 amount0, uint256 amount1) internal returns (int256 delta) {
        if (amount0 == amount1) return 0;

        address locker = _lockData.getActiveLock();
        int256 current = assetDelta[locker][assetId];
        unchecked {
            // Todo should check overflow
            if (amount0 > amount1) {
                delta = int256(amount0 - amount1);
            } else {
                delta = -int256(amount1 - amount0);
            }
        }
        int256 next = current + delta;

        unchecked {
            if (next == 0) {
                _lockData.nonzeroDeltaCount--;
            } else if (current == 0) {
                _lockData.nonzeroDeltaCount++;
            }
        }

        assetDelta[locker][assetId] = next;
    }

    function withdrawToken(address token, address to, uint256 amount) external onlyByLocker {
        _accountDelta(uint256(uint160(token)), amount, 0);
        IAssetPool(assetPool).withdraw(token, amount, to);
    }

    function mintCoupons(Coupon[] calldata coupons, address to, bytes calldata data) external onlyByLocker {
        unchecked {
            for (uint256 i = 0; i < coupons.length; ++i) {
                _accountDelta(coupons[i].id(), coupons[i].amount, 0);
            }
            ICouponManager(_couponManager).mintBatch(to, coupons, data);
        }
    }

    function depositToken(address token, uint256 amount) external onlyByLocker {
        if (amount == 0) return;
        IERC20(token).safeTransferFrom(msg.sender, assetPool, amount);
        _accountDelta(uint256(uint160(token)), 0, amount);
    }

    function burnCoupons(Coupon[] calldata coupons) external onlyByLocker {
        unchecked {
            ICouponManager(_couponManager).burnBatch(msg.sender, coupons);
            for (uint256 i = 0; i < coupons.length; ++i) {
                _accountDelta(coupons[i].id(), 0, coupons[i].amount);
            }
        }
    }

    function settlePosition(uint256 positionId) public virtual {
        if (_isSettled(positionId)) return;
        _setPositionSettlement(positionId, true);
        unchecked {
            _lockData.nonzeroDeltaCount--;
        }
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function lockData() external view override returns (uint128, uint128) {
        return (_lockData.length, _lockData.nonzeroDeltaCount);
    }

    function _mint(address to, uint256 positionId) internal virtual override {
        super._mint(to, positionId);
        _setPositionSettlement(positionId, false);
        unchecked {
            _lockData.nonzeroDeltaCount++;
        }
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
