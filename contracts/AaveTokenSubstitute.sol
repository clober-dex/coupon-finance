// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IAToken} from "./external/aave-v3/IAToken.sol";
import {IPool} from "./external/aave-v3/IPool.sol";
import {DataTypes} from "./external/aave-v3/DataTypes.sol";
import {ReserveConfiguration} from "./external/aave-v3/ReserveConfiguration.sol";
import {IAaveTokenSubstitute} from "./interfaces/IAaveTokenSubstitute.sol";

contract AaveTokenSubstitute is IAaveTokenSubstitute, ERC20Permit, Ownable {
    using SafeERC20 for IERC20;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    IPool private immutable _aaveV3Pool;
    uint8 private immutable _decimals;
    address public immutable aToken;
    address public immutable override underlyingToken;

    address public override treasury;

    constructor(address asset_, address aaveV3Pool_, address treasury_, address owner_)
        ERC20Permit(string.concat("Wrapped Aave ", IERC20Metadata(asset_).name()))
        ERC20(
            string.concat("Wrapped Aave ", IERC20Metadata(asset_).name()),
            string.concat("Wa", IERC20Metadata(asset_).symbol())
        )
    {
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
        IERC20(underlyingToken).approve(address(_aaveV3Pool), amount);
        _aaveV3Pool.supply(underlyingToken, amount, address(this), 0);
        _mint(to, amount);
    }

    function mintableAmount() external view returns (uint256) {
        DataTypes.ReserveConfigurationMap memory configuration =
            _aaveV3Pool.getReserveData(underlyingToken).configuration;
        return configuration.getSupplyCap() * 10 ** (configuration.getDecimals());
    }

    function burnToAToken(uint256 amount, address to) external {
        _burn(msg.sender, amount);
        IERC20(aToken).safeTransfer(address(to), amount);
    }

    function burn(uint256 amount, address to) external {
        _burn(msg.sender, amount);
        _aaveV3Pool.withdraw(underlyingToken, amount, to);
    }

    function burnableAmount() external view returns (uint256) {
        return IERC20(underlyingToken).balanceOf(address(aToken));
    }

    function setTreasury(address newTreasury) external onlyOwner {
        treasury = newTreasury;
    }

    function claim() external {
        uint256 adminYield = IERC20(aToken).balanceOf(address(this)) - totalSupply() - 1;
        if (adminYield > 0) {
            IERC20(aToken).transfer(treasury, adminYield);
        }
    }
}
