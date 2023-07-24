// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {Errors} from "./Errors.sol";
import {IBondPositionManager} from "./interfaces/IBondPositionManager.sol";
import {ICouponManager} from "./interfaces/ICouponManager.sol";
import {IAssetPool} from "./interfaces/IAssetPool.sol";
import {IBondPositionCallbackReceiver} from "./interfaces/IBondPositionCallbackReceiver.sol";
import {ERC721Permit} from "./libraries/ERC721Permit.sol";
import {BondPosition, BondPositionLibrary} from "./libraries/BondPosition.sol";
import {Coupon, CouponLibrary} from "./libraries/Coupon.sol";
import {Epoch, EpochLibrary} from "./libraries/Epoch.sol";

contract BondPositionManager is IBondPositionManager, ERC721Permit, Ownable {
    using SafeERC20 for IERC20;
    using Strings for uint256;
    using EpochLibrary for Epoch;
    using BondPositionLibrary for BondPosition;

    address public immutable override couponManager;
    address public immutable override assetPool;

    string public override baseURI;
    uint256 public override nextId = 1;

    mapping(address asset => bool) public override isAssetRegistered;
    mapping(uint256 id => BondPosition) private _positionMap;

    constructor(
        address coupon_,
        address assetPool_,
        string memory baseURI_,
        address[] memory initialAssets
    ) ERC721Permit("Bond Position", "BP", "1") {
        couponManager = coupon_;
        assetPool = assetPool_;
        baseURI = baseURI_;
        for (uint256 i = 0; i < initialAssets.length; ++i) {
            _registerAsset(initialAssets[i]);
        }
    }

    function getPosition(uint256 tokenId) external view returns (BondPosition memory) {
        return _positionMap[tokenId];
    }

    function mint(
        address asset,
        uint256 amount,
        uint16 lockEpochs,
        address recipient,
        bytes calldata data
    ) external returns (uint256 tokenId) {
        require(isAssetRegistered[asset], Errors.UNREGISTERED_ASSET);
        require(lockEpochs > 0 && amount > 0, Errors.EMPTY_INPUT);
        Epoch currentEpoch = EpochLibrary.current();
        Coupon[] memory coupons = new Coupon[](lockEpochs);
        for (uint16 i = 0; i < lockEpochs; ++i) {
            coupons[i] = CouponLibrary.from(asset, currentEpoch.add(i), amount);
        }
        tokenId = nextId++;
        Epoch expiredWith = currentEpoch.add(lockEpochs - 1);
        BondPosition memory position = BondPositionLibrary.from(asset, expiredWith, amount);
        _positionMap[tokenId] = position;
        emit PositionUpdated(tokenId, amount, expiredWith);

        _mint(recipient, tokenId);
        ICouponManager(couponManager).mintBatch(recipient, coupons, data);

        if (data.length > 0) {
            IBondPositionCallbackReceiver(recipient).bondPositionAdjustCallback(msg.sender, tokenId, position, data);
        }

        IERC20(asset).safeTransferFrom(msg.sender, address(assetPool), amount);
        IAssetPool(assetPool).deposit(asset, amount);
    }

    function adjustPosition(uint256 tokenId, uint256 amount, Epoch expiredWith, bytes calldata data) external {
        require(_isApprovedOrOwner(msg.sender, tokenId), Errors.ACCESS);

        BondPosition memory oldPosition = _positionMap[tokenId];
        Epoch latestExpiredEpoch = EpochLibrary.current().sub(1);
        require(oldPosition.expiredWith.compare(latestExpiredEpoch) > 0, Errors.INVALID_EPOCH);

        address asset = oldPosition.asset;
        BondPosition memory newPosition = BondPosition({
            asset: asset,
            nonce: oldPosition.nonce,
            expiredWith: (amount == 0 || latestExpiredEpoch.compare(expiredWith) > 0)
                ? latestExpiredEpoch
                : expiredWith,
            amount: amount
        });

        (Coupon[] memory couponsToMint, Coupon[] memory couponsToBurn) = oldPosition.calculateCouponRequirement(
            newPosition
        );

        _positionMap[tokenId] = newPosition;
        emit PositionUpdated(tokenId, newPosition.amount, newPosition.expiredWith);

        if (couponsToMint.length > 0) {
            ICouponManager(couponManager).mintBatch(msg.sender, couponsToMint, data);
        }
        if (oldPosition.amount > newPosition.amount) {
            IAssetPool(assetPool).withdraw(asset, oldPosition.amount - newPosition.amount, msg.sender);
        }
        if (data.length > 0) {
            IBondPositionCallbackReceiver(msg.sender).bondPositionAdjustCallback(
                msg.sender,
                tokenId,
                newPosition,
                data
            );
        }
        if (newPosition.amount > oldPosition.amount) {
            uint256 assetToDeposit = newPosition.amount - oldPosition.amount;
            IERC20(asset).safeTransferFrom(msg.sender, address(assetPool), assetToDeposit);
            IAssetPool(assetPool).deposit(asset, assetToDeposit);
        }
        if (couponsToBurn.length > 0) {
            ICouponManager(couponManager).burnBatch(msg.sender, couponsToBurn);
        }
        if (newPosition.amount == 0) {
            _burn(tokenId);
        }
    }

    function burnExpiredPosition(uint256 tokenId) external {
        require(_isApprovedOrOwner(msg.sender, tokenId), Errors.ACCESS);
        BondPosition memory position = _positionMap[tokenId];
        require(position.expiredWith.compare(EpochLibrary.current()) < 0, Errors.INVALID_EPOCH);

        uint256 assetToWithdraw = position.amount;
        if (assetToWithdraw > 0) {
            IAssetPool(assetPool).withdraw(position.asset, assetToWithdraw, msg.sender);
            position.amount -= assetToWithdraw;
            _positionMap[tokenId] = position;
        }
        if (position.amount == 0) {
            _burn(tokenId);
        }
    }

    function registerAsset(address asset) external onlyOwner {
        _registerAsset(asset);
    }

    function _registerAsset(address asset) internal {
        IERC20(asset).approve(address(assetPool), type(uint256).max);
        isAssetRegistered[asset] = true;
        emit AssetRegistered(asset);
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function _getAndIncrementNonce(uint256 tokenId) internal override returns (uint256) {
        return _positionMap[tokenId].getAndIncrementNonce();
    }
}
