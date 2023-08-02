// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IAToken} from "./external/aave-v3/IAToken.sol";
import {IPool} from "./external/aave-v3/IPool.sol";
import {IAssetPool} from "./interfaces/IAssetPool.sol";

contract AssetPoolAaveV3 is IAssetPool, Ownable {
    using SafeERC20 for IERC20;

    IPool private immutable _aaveV3Pool;

    address public override treasury;
    mapping(address => uint256) public override totalReservedAmount;

    mapping(address => address) public aTokenMap;
    mapping(address => bool) public override isOperator;

    constructor(address aaveV3Pool_, address treasury_, address[] memory operators) {
        _aaveV3Pool = IPool(aaveV3Pool_);
        treasury = treasury_;
        for (uint256 i = 0; i < operators.length; ++i) {
            isOperator[operators[i]] = true;
        }
    }

    function isAssetRegistered(address asset) public view returns (bool) {
        return !_isAssetUnregistered(asset);
    }

    function claimableAmount(address asset) public view returns (uint256) {
        if (_isAssetUnregistered(asset)) {
            return 0;
        }
        return IERC20(aTokenMap[asset]).balanceOf(address(this)) - totalReservedAmount[asset];
    }

    function claim(address asset) external {
        if (_isAssetUnregistered(asset)) {
            revert InvalidAsset();
        }
        uint256 amount = claimableAmount(asset);
        _aaveV3Pool.withdraw(asset, amount, treasury);
    }

    function deposit(address asset, uint256 amount) external {
        if (_isAssetUnregistered(asset)) {
            revert InvalidAsset();
        }
        if (!isOperator[msg.sender]) {
            revert InvalidAccess();
        }
        totalReservedAmount[asset] += amount;
        _aaveV3Pool.supply(asset, amount, address(this), 0);
    }

    function withdraw(address asset, uint256 amount, address recipient) external {
        if (_isAssetUnregistered(asset)) {
            revert InvalidAsset();
        }
        if (!isOperator[msg.sender]) {
            revert InvalidAccess();
        }
        uint256 balance = totalReservedAmount[asset];
        if (amount > balance) {
            revert ExceedsBalance(balance);
        }
        totalReservedAmount[asset] = balance - amount;
        address aToken = aTokenMap[asset];
        uint256 maxUnderlyingAmount = IERC20(asset).balanceOf(aToken);
        if (amount > maxUnderlyingAmount) {
            IERC20(aToken).safeTransfer(recipient, amount - maxUnderlyingAmount);
            amount = maxUnderlyingAmount;
        }
        _aaveV3Pool.withdraw(asset, amount, recipient);
    }

    function setTreasury(address newTreasury) external onlyOwner {
        treasury = newTreasury;
    }

    function registerAsset(address asset) external onlyOwner {
        address aToken = _aaveV3Pool.getReserveData(asset).aTokenAddress;
        if (aToken == address(0)) {
            revert InvalidAsset();
        }
        aTokenMap[asset] = aToken;
        IERC20(asset).approve(address(_aaveV3Pool), type(uint256).max);
    }

    function withdrawLostToken(address asset, address recipient) external onlyOwner {
        if (isAssetRegistered(asset)) {
            revert InvalidAsset();
        }
        // check if the asset is a registered aToken
        try IAToken(asset).UNDERLYING_ASSET_ADDRESS() returns (address underlyingAsset) {
            if (!_isAssetUnregistered(underlyingAsset)) {
                revert InvalidAsset();
            }
        } catch {}

        IERC20(asset).safeTransfer(recipient, IERC20(asset).balanceOf(address(this)));
    }

    function _isAssetUnregistered(address asset) internal view returns (bool) {
        return aTokenMap[asset] == address(0);
    }
}
