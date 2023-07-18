// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {Types} from "./Types.sol";
import {Errors} from "./Errors.sol";
import {IBondPosition} from "./interfaces/IBondPosition.sol";
import {ICouponManager} from "./interfaces/ICouponManager.sol";
import {IAssetPool} from "./interfaces/IAssetPool.sol";
import {ERC721Permit} from "./libraries/ERC721Permit.sol";
import {Bond} from "./libraries/Bond.sol";
import {Coupon} from "./libraries/Coupon.sol";
import {Epoch} from "./libraries/Epoch.sol";

contract BondPosition is IBondPosition, ERC721Permit, Ownable {
    using SafeERC20 for IERC20;
    using Epoch for Types.Epoch;
    using Bond for Types.Bond;

    address public immutable override coupon;
    address public immutable override assetPool;

    string public override baseURI;
    uint256 public override nextId = 1;

    mapping(address asset => bool) public override isAssetRegistered;
    mapping(uint256 id => Types.Bond) private _bondMap;

    constructor(
        address coupon_,
        address assetPool_,
        string memory baseURI_,
        address[] memory initialAssets
    ) ERC721Permit("Bond Position", "BP", "1") {
        coupon = coupon_;
        assetPool = assetPool_;
        baseURI = baseURI_;
        for (uint256 i = 0; i < initialAssets.length; ++i) {
            _registerAsset(initialAssets[i]);
        }
    }

    function bonds(uint256 tokenId) external view returns (Types.Bond memory) {
        return _bondMap[tokenId];
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
        Types.Epoch currentEpoch = Epoch.current();
        Types.Coupon[] memory coupons = new Types.Coupon[](lockEpochs);
        for (uint16 i = 0; i < lockEpochs; ++i) {
            coupons[i] = Coupon.from(asset, currentEpoch.add(i), amount);
        }
        tokenId = nextId++;
        Types.Epoch expiredWith = currentEpoch.add(lockEpochs - 1);
        _bondMap[tokenId] = Bond.from(asset, expiredWith, amount);
        emit PositionUpdated(tokenId, amount, expiredWith);

        _safeMint(recipient, tokenId, data);
        ICouponManager(coupon).mintBatch(recipient, coupons, data);

        IERC20(asset).safeTransferFrom(msg.sender, address(assetPool), amount);
        IAssetPool(assetPool).deposit(asset, amount);
    }

    function adjustPosition(uint256 tokenId, int256 amount, int16 lockEpochs, bytes calldata data) external {
        require(_isApprovedOrOwner(msg.sender, tokenId), Errors.ACCESS);
        Types.Bond memory oldBond = _bondMap[tokenId];
        Types.Epoch latestExpiredEpoch = Epoch.current().sub(1);
        require(oldBond.expiredWith.compare(latestExpiredEpoch) > 0, Errors.INVALID_EPOCH);
        address asset = oldBond.asset;
        {
            uint256 withdrawableAmount = IAssetPool(assetPool).withdrawable(asset);
            if (amount < 0 && int256(withdrawableAmount) < -amount) {
                amount = -int256(withdrawableAmount);
            }
        }
        Types.Bond memory newBond = oldBond.adjustPosition(amount, lockEpochs, latestExpiredEpoch);

        Types.Coupon[] memory couponsToMint;
        Types.Coupon[] memory couponsToBurn;
        uint256 assetToDeposit;
        uint256 assetToWithdraw;
        if (newBond.amount == oldBond.amount) {
            int256 comparisonResult = newBond.compareEpoch(oldBond);
            if (comparisonResult > 0) {
                couponsToMint = new Types.Coupon[](newBond.expiredWith.sub(oldBond.expiredWith));
                for (uint16 i = 0; i < couponsToBurn.length; ++i) {
                    couponsToMint[i] = Coupon.from(asset, oldBond.expiredWith.add(i + 1), newBond.amount);
                }
            } else {
                couponsToBurn = new Types.Coupon[](oldBond.expiredWith.sub(newBond.expiredWith));
                for (uint16 i = 0; i < couponsToBurn.length; ++i) {
                    couponsToBurn[i] = Coupon.from(asset, newBond.expiredWith.add(i + 1), oldBond.amount);
                }
            }
        } else {
            if (newBond.amount > oldBond.amount) {
                (couponsToMint, couponsToBurn) = _diffInCoupons(newBond, oldBond, latestExpiredEpoch, asset);
                assetToDeposit = newBond.amount - oldBond.amount;
            } else {
                (couponsToBurn, couponsToMint) = _diffInCoupons(oldBond, newBond, latestExpiredEpoch, asset);
                assetToWithdraw = oldBond.amount - newBond.amount;
            }
        }

        _bondMap[tokenId] = newBond;
        emit PositionUpdated(tokenId, newBond.amount, newBond.expiredWith);

        if (couponsToMint.length > 0) {
            ICouponManager(coupon).mintBatch(msg.sender, couponsToMint, data);
        }
        if (assetToWithdraw > 0) {
            IAssetPool(assetPool).withdraw(asset, assetToWithdraw, msg.sender);
        }
        // todo callback
        if (assetToDeposit > 0) {
            IERC20(asset).safeTransferFrom(msg.sender, address(assetPool), assetToDeposit);
            IAssetPool(assetPool).deposit(asset, assetToDeposit);
        }
        if (couponsToBurn.length > 0) {
            ICouponManager(coupon).burnBatch(msg.sender, couponsToBurn);
        }
        if (newBond.amount == 0) {
            _burn(tokenId);
        }
    }

    function burnExpiredPosition(uint256 tokenId) external {
        require(_isApprovedOrOwner(msg.sender, tokenId), Errors.ACCESS);
        Types.Bond memory bond = _bondMap[tokenId];
        require(bond.expiredWith.compare(Epoch.current()) < 0, Errors.INVALID_EPOCH);

        uint256 withdrawableAmount = IAssetPool(assetPool).withdrawable(bond.asset);
        uint256 assetToWithdraw = bond.amount > withdrawableAmount ? withdrawableAmount : bond.amount;
        if (assetToWithdraw > 0) {
            IAssetPool(assetPool).withdraw(bond.asset, assetToWithdraw, msg.sender);
            bond.amount -= assetToWithdraw;
            _bondMap[tokenId] = bond;
        }
        if (bond.amount == 0) {
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

    function _getAndIncrementNonce(uint256 tokenId) internal override returns (uint256) {
        return _bondMap[tokenId].getAndIncrementNonce();
    }

    function _diffInCoupons(
        Types.Bond memory largeAmountBond,
        Types.Bond memory smallAmountBond,
        Types.Epoch latestExpiredEpoch,
        address asset
    ) internal pure returns (Types.Coupon[] memory couponsToMint, Types.Coupon[] memory couponsToBurn) {
        // @dev always satisfy below condition
        // require(largeAmountBond.amount >= smallAmountBond.amount);

        couponsToMint = new Types.Coupon[](largeAmountBond.expiredWith.sub(latestExpiredEpoch));
        uint256 amountDiff = largeAmountBond.amount - smallAmountBond.amount;
        for (uint16 i = 0; i < couponsToMint.length; ++i) {
            Types.Epoch epoch = latestExpiredEpoch.add(i + 1);
            if (epoch.compare(smallAmountBond.expiredWith) > 0) {
                couponsToMint[i] = Coupon.from(asset, epoch, largeAmountBond.amount);
            } else {
                couponsToMint[i] = Coupon.from(asset, epoch, amountDiff);
            }
        }
        if (smallAmountBond.compareEpoch(largeAmountBond) > 0) {
            couponsToBurn = new Types.Coupon[](smallAmountBond.expiredWith.sub(largeAmountBond.expiredWith));
            for (uint16 i = 0; i < couponsToBurn.length; ++i) {
                couponsToBurn[i] = Coupon.from(asset, largeAmountBond.expiredWith.add(i + 1), smallAmountBond.amount);
            }
        }
    }
}
