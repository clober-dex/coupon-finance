// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAToken} from "./external/aave-v3/IAToken.sol";
import {IAaveTokenSubstitute} from "./interfaces/IAaveTokenSubstitute.sol";
import {IPool} from "./external/aave-v3/IPool.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {DataTypes} from "./external/aave-v3/DataTypes.sol";
import {ReserveConfiguration} from "./external/aave-v3/ReserveConfiguration.sol";

contract AaveTokenSubstitute is IAaveTokenSubstitute, ERC20Permit, Ownable {
    using SafeERC20 for IERC20;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    address public override treasury;
    address public immutable aToken;

    address private immutable _underlyingToken;
    IPool private immutable _aaveV3Pool;

    constructor(address asset_, address aaveV3Pool_)
        ERC20Permit(string.concat("Wrapped Aave ", IERC20Metadata(asset_).name()))
        ERC20(
            string.concat("Wrapped Aave ", IERC20Metadata(asset_).name()),
            string.concat("Wa", IERC20Metadata(asset_).symbol())
        )
    {
        _aaveV3Pool = IPool(aaveV3Pool_);
        aToken = _aaveV3Pool.getReserveData(asset_).aTokenAddress;
        _underlyingToken = asset_;
    }

    function mintByAToken(uint256 amount, address to) external {
        IERC20(aToken).safeTransferFrom(msg.sender, address(this), amount);
        _mint(to, amount);
    }

    function mint(uint256 amount, address to) external {
        IERC20(_underlyingToken).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(_underlyingToken).approve(address(_aaveV3Pool), amount);
        _aaveV3Pool.supply(_underlyingToken, amount, address(this), 0);
        _mint(to, amount);
    }

    function mintableAmount() external view returns (uint256) {
        DataTypes.ReserveConfigurationMap memory configuration =
            _aaveV3Pool.getReserveData(_underlyingToken).configuration;
        return configuration.getSupplyCap() * 10 ** (configuration.getDecimals());
    }

    function burnToAToken(uint256 amount, address to) external {
        _burn(msg.sender, amount);
        IERC20(aToken).safeTransfer(address(to), amount);
    }

    function burn(uint256 amount, address to) external {
        _burn(msg.sender, amount);
        _aaveV3Pool.withdraw(_underlyingToken, amount, to);
    }

    function burnableAmount() external view returns (uint256) {
        return IERC20(_underlyingToken).balanceOf(address(aToken));
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
