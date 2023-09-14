// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IWETH9} from "./external/weth/IWETH9.sol";
import {IPool} from "./external/aave-v3/IPool.sol";
import {DataTypes} from "./external/aave-v3/DataTypes.sol";
import {ReserveConfiguration} from "./external/aave-v3/ReserveConfiguration.sol";
import {IAaveTokenSubstitute} from "./interfaces/IAaveTokenSubstitute.sol";

contract AaveTokenSubstitute is IAaveTokenSubstitute, ERC20Permit, Ownable {
    using SafeERC20 for IERC20;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    IWETH9 private immutable _weth;
    IPool private immutable _aaveV3Pool;
    uint8 private immutable _decimals;
    address public immutable override aToken;
    address public immutable override underlyingToken;

    address public override treasury;

    constructor(address weth_, address asset_, address aaveV3Pool_, address treasury_, address owner_)
        ERC20Permit(string.concat("Wrapped Aave ", IERC20Metadata(asset_).name()))
        ERC20(
            string.concat("Wrapped Aave ", IERC20Metadata(asset_).name()),
            string.concat("Wa", IERC20Metadata(asset_).symbol())
        )
    {
        _weth = IWETH9(weth_);
        _aaveV3Pool = IPool(aaveV3Pool_);
        aToken = _aaveV3Pool.getReserveData(asset_).aTokenAddress;
        _decimals = IERC20Metadata(asset_).decimals();
        underlyingToken = asset_;
        treasury = treasury_;
        _transferOwnership(owner_);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mintByAToken(uint256 amount, address to) external {
        IERC20(aToken).safeTransferFrom(msg.sender, address(this), amount);
        _mint(to, amount);
    }

    function mint(uint256 amount, address to) external {
        IERC20(underlyingToken).safeTransferFrom(msg.sender, address(this), amount);
        uint256 supplyAmount = IERC20(underlyingToken).balanceOf(address(this));
        IERC20(underlyingToken).approve(address(_aaveV3Pool), supplyAmount);
        try _aaveV3Pool.supply(underlyingToken, supplyAmount, address(this), 0) {} catch {}
        _mint(to, amount);
    }

    function mintableAmount() external view returns (uint256) {
        DataTypes.ReserveConfigurationMap memory configuration =
            _aaveV3Pool.getReserveData(underlyingToken).configuration;
        if (configuration.getFrozen()) return 0;
        return configuration.getSupplyCap() * 10 ** (configuration.getDecimals());
    }

    function burnToAToken(uint256 amount, address to) external {
        _burn(msg.sender, amount);
        IERC20(aToken).safeTransfer(address(to), amount);
    }

    function burn(uint256 amount, address to) external {
        _burn(msg.sender, amount);

        uint256 underlyingAmount = IERC20(underlyingToken).balanceOf(address(this));
        if (amount <= underlyingAmount) {
            underlyingAmount = amount;
            amount = 0;
        } else {
            amount -= underlyingAmount;
            uint256 withdrawableAmount = IERC20(underlyingToken).balanceOf(address(aToken));
            if (withdrawableAmount < amount) {
                IERC20(aToken).safeTransfer(to, amount - withdrawableAmount);
                amount = withdrawableAmount;
            }
        }

        if (underlyingToken == address(_weth)) {
            if (amount > 0) {
                _aaveV3Pool.withdraw(underlyingToken, amount, address(this));
            }
            amount += underlyingAmount;
            _weth.withdraw(amount);
            (bool success,) = payable(to).call{value: amount}("");
            if (!success) revert ValueTransferFailed();
        } else {
            if (amount > 0) {
                _aaveV3Pool.withdraw(underlyingToken, amount, to);
            }
            if (underlyingAmount > 0) {
                IERC20(underlyingToken).safeTransfer(address(to), underlyingAmount);
            }
        }
    }

    function burnableAmount() external view returns (uint256) {
        DataTypes.ReserveConfigurationMap memory configuration =
            _aaveV3Pool.getReserveData(underlyingToken).configuration;
        if (configuration.getFrozen()) return 0;
        return IERC20(underlyingToken).balanceOf(address(aToken)) + IERC20(underlyingToken).balanceOf(address(this));
    }

    function setTreasury(address newTreasury) external onlyOwner {
        treasury = newTreasury;
    }

    function claim() external {
        uint256 adminYield = IERC20(aToken).balanceOf(address(this)) - totalSupply() - 1;
        if (adminYield > 0) IERC20(aToken).safeTransfer(treasury, adminYield);
    }

    receive() external payable {}
}
