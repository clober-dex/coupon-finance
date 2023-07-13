// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IERC1155MetadataURI} from "@openzeppelin/contracts/token/ERC1155/extensions/IERC1155MetadataURI.sol";
import {ERC1155Supply} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {Types} from "./Types.sol";
import {IWETH9} from "./external/weth/IWETH9.sol";
import {ICoupon} from "./interfaces/ICoupon.sol";
import {ILendingPool} from "./interfaces/ILendingPool.sol";
import {IAaveOracle} from "./external/aave-v3/IAaveOracle.sol";
import {IYieldFarmer} from "./interfaces/IYieldFarmer.sol";
import {CouponKeyLibrary, LoanKeyLibrary, VaultKeyLibrary} from "./libraries/Keys.sol";
import {ReentrancyGuard} from "./libraries/ReentrancyGuard.sol";

contract LendingPool is ILendingPool, ERC1155Supply, ReentrancyGuard, Ownable {
    using Strings for uint256;
    using SafeERC20 for IERC20;
    using CouponKeyLibrary for Types.CouponKey;
    using LoanKeyLibrary for Types.LoanKey;
    using VaultKeyLibrary for Types.VaultKey;

    struct Reserve {
        uint256 spendableAmount;
        uint256 collateralAmount;
    }
    struct Vault {
        uint256 spendableAmount;
        uint256 collateralAmount;
    }
    struct Loan {
        uint256 amount;
        uint256 collateralAmount;
    }

    uint256 private constant _RATE_PRECISION = 10 ** 6;

    IWETH9 private immutable _weth;
    uint256 private immutable _maxEpochDiff;
    uint256 public immutable override startedAt;
    uint256 public immutable override epochDuration;

    string public override baseURI;
    address public override oracle;
    address public override treasury;
    address public override yieldFarmer;

    mapping(address asset => Types.AssetConfiguration) private _assetConfig;
    mapping(address asset => Reserve) private _reserveMap;
    mapping(address asset => mapping(uint256 epoch => uint256)) private _reserveLockedAmountMap;
    mapping(Types.VaultId => Vault) private _vaultMap;
    mapping(Types.VaultId => mapping(uint256 epoch => uint256)) private _vaultLockedAmountMap;

    mapping(Types.LoanId => Loan) private _loanMap;
    mapping(Types.LoanId => mapping(uint256 epoch => uint256)) private _loanLimit;

    constructor(
        uint256 maxEpochDiff_,
        uint256 startedAt_,
        uint256 epochDuration_,
        address oracle_,
        address treasury_,
        address yieldFarmer_,
        address weth_,
        string memory baseURI_
    ) ERC1155(baseURI_) {
        _maxEpochDiff = maxEpochDiff_;
        startedAt = startedAt_;
        epochDuration = epochDuration_;
        oracle = oracle_;
        treasury = treasury_;
        yieldFarmer = yieldFarmer_;
        _weth = IWETH9(weth_);
        baseURI = baseURI_;
    }

    // View Functions //
    function totalSupply(uint256 id) public view override(ERC1155Supply, ICoupon) returns (uint256) {
        return super.totalSupply(id);
    }

    function exists(uint256 id) public view override(ERC1155Supply, ICoupon) returns (bool) {
        return super.exists(id);
    }

    function uri(uint256 id) public view override(ERC1155, IERC1155MetadataURI) returns (string memory) {
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, id.toString())) : "";
    }

    function maxEpoch() public view returns (uint256) {
        unchecked {
            return currentEpoch() + _maxEpochDiff;
        }
    }

    function currentEpoch() public view returns (uint256) {
        unchecked {
            return block.timestamp < startedAt ? 0 : (block.timestamp - startedAt) / epochDuration + 1;
        }
    }

    function isAssetRegistered(address asset) public view returns (bool) {
        return _assetConfig[asset].liquidationThreshold > 0;
    }

    function getAssetConfiguration(address asset) external view returns (Types.AssetConfiguration memory) {
        return _assetConfig[asset];
    }

    function getReserveStatus(address asset) external view returns (Types.ReserveStatus memory) {
        return
            Types.ReserveStatus({
                spendableAmount: _reserveMap[asset].spendableAmount,
                lockedAmount: _reserveLockedAmountMap[asset][currentEpoch()],
                collateralAmount: _reserveMap[asset].collateralAmount
            });
    }

    function getReserveLockedAmount(address asset, uint256 epoch) external view returns (uint256) {
        return _reserveLockedAmountMap[asset][epoch];
    }

    function getVaultStatus(Types.VaultKey calldata vaultKey) external view returns (Types.VaultStatus memory) {
        Types.VaultId id = vaultKey.toId();
        return
            Types.VaultStatus({
                spendableAmount: _vaultMap[id].spendableAmount,
                lockedAmount: _vaultLockedAmountMap[id][currentEpoch()],
                collateralAmount: _vaultMap[id].collateralAmount
            });
    }

    function getVaultLockedAmount(Types.VaultKey calldata vaultKey, uint256 epoch) external view returns (uint256) {
        return _vaultLockedAmountMap[vaultKey.toId()][epoch];
    }

    function getLoanStatus(Types.LoanKey calldata loanKey) external view returns (Types.LoanStatus memory) {
        Types.LoanId id = loanKey.toId();
        return
            Types.LoanStatus({
                amount: _loanMap[id].amount,
                collateralAmount: _loanMap[id].collateralAmount,
                limit: _loanLimit[id][currentEpoch()]
            });
    }

    function _getAssetConfig(address asset, address collateral) private view returns (Types.AssetConfiguration memory) {
        Types.AssetConfiguration memory debtAssetConfig = _assetConfig[asset];
        Types.AssetConfiguration memory collateralAssetConfig = _assetConfig[collateral];

        if (collateralAssetConfig.liquidationThreshold == 0) return debtAssetConfig;
        if (debtAssetConfig.liquidationThreshold == 0) return collateralAssetConfig;

        if (debtAssetConfig.liquidationFee > collateralAssetConfig.liquidationFee) {
            collateralAssetConfig.liquidationFee = debtAssetConfig.liquidationFee;
        }
        if (debtAssetConfig.liquidationProtocolFee > collateralAssetConfig.liquidationProtocolFee) {
            collateralAssetConfig.liquidationProtocolFee = debtAssetConfig.liquidationProtocolFee;
        }
        if (debtAssetConfig.liquidationThreshold < collateralAssetConfig.liquidationThreshold) {
            collateralAssetConfig.liquidationThreshold = debtAssetConfig.liquidationThreshold;
        }
        if (debtAssetConfig.liquidationTargetLtv < collateralAssetConfig.liquidationTargetLtv) {
            collateralAssetConfig.liquidationTargetLtv = debtAssetConfig.liquidationTargetLtv;
        }
        return collateralAssetConfig;
    }

    function _getPriceWithPrecision(address asset, address collateral) private view returns (uint256, uint256) {
        address[] memory assets = new address[](2);
        assets[0] = asset;
        assets[1] = collateral;

        uint256 assetDecimal = _assetConfig[asset].decimal;
        uint256 collateralDecimal = _assetConfig[collateral].decimal;

        uint256[] memory prices = IAaveOracle(oracle).getAssetsPrices(assets);
        if (assetDecimal > collateralDecimal) {
            return (prices[0], prices[1] * 10 ** (assetDecimal - collateralDecimal));
        }
        return (prices[0] * 10 ** (collateralDecimal - assetDecimal), prices[1]);
    }

    function _getLiquidationAmount(
        Types.LoanKey calldata loanKey,
        uint256 maxRepayAmount
    ) private view returns (uint256 liquidationAmount, uint256 repayAmount, uint256 protocolFeeAmount) {
        Types.LoanId id = loanKey.toId();

        Loan memory loan = _loanMap[id];
        uint256 currentLoanLimit = _loanLimit[id][currentEpoch()];

        Types.AssetConfiguration memory assetConfig = _getAssetConfig(loanKey.asset, loanKey.collateral);
        (uint256 assetPrice, uint256 collateralPrice) = _getPriceWithPrecision(loanKey.asset, loanKey.collateral);

        if (currentLoanLimit < loan.amount) {
            repayAmount = loan.amount - currentLoanLimit;
            if (repayAmount > maxRepayAmount) {
                repayAmount = maxRepayAmount;
            }

            // Todo: round up liquidation amount
            liquidationAmount =
                (repayAmount * assetPrice * _RATE_PRECISION) /
                collateralPrice /
                (_RATE_PRECISION - assetConfig.liquidationFee);
            protocolFeeAmount = (liquidationAmount * assetConfig.liquidationProtocolFee) / _RATE_PRECISION;
            return (liquidationAmount, repayAmount, protocolFeeAmount);
        }

        uint256 assetAmountInBaseCurrency = loan.amount * assetPrice * _RATE_PRECISION;
        uint256 collateralAmountInBaseCurrency = loan.collateralAmount * collateralPrice * _RATE_PRECISION;

        unchecked {
            if (
                (collateralAmountInBaseCurrency / _RATE_PRECISION) * assetConfig.liquidationThreshold >
                assetAmountInBaseCurrency
            ) {
                return (0, 0, 0);
            }

            // Todo: round up liquidation amount
            liquidationAmount =
                (assetAmountInBaseCurrency -
                    (collateralAmountInBaseCurrency / _RATE_PRECISION) *
                    assetConfig.liquidationTargetLtv) /
                collateralPrice /
                (_RATE_PRECISION - assetConfig.liquidationFee - assetConfig.liquidationTargetLtv);
        }

        repayAmount =
            (liquidationAmount * collateralPrice * (_RATE_PRECISION - assetConfig.liquidationFee)) /
            _RATE_PRECISION;

        if (repayAmount > maxRepayAmount) {
            repayAmount = maxRepayAmount;

            // Todo: round up liquidation amount
            liquidationAmount =
                (repayAmount * assetPrice * _RATE_PRECISION) /
                collateralPrice /
                (_RATE_PRECISION - assetConfig.liquidationFee);
        }

        protocolFeeAmount = (liquidationAmount * assetConfig.liquidationProtocolFee) / _RATE_PRECISION;

        return (liquidationAmount, repayAmount, protocolFeeAmount);
    }

    function getLiquidationStatus(
        Types.LoanKey calldata loanKey,
        uint256 maxRepayAmount
    ) external view returns (Types.LiquidationStatus memory) {
        (uint256 liquidationAmount, uint256 repayAmount, ) = _getLiquidationAmount(
            loanKey,
            maxRepayAmount > 0 ? maxRepayAmount : type(uint256).max
        );
        return
            Types.LiquidationStatus({
                available: liquidationAmount > 0,
                liquidationAmount: liquidationAmount,
                repayAmount: repayAmount
            });
    }

    function getLoanLimit(Types.LoanKey calldata loanKey, uint256 epoch) external view returns (uint256) {
        return _loanLimit[loanKey.toId()][epoch];
    }

    function withdrawable(address asset) external view returns (uint256) {
        return IYieldFarmer(yieldFarmer).withdrawable(asset);
    }

    // User Functions //
    function deposit(address asset, uint256 amount, address recipient) public payable nonReentrant {
        _checkValidAsset(asset);
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        if (asset == address(_weth)) {
            if (msg.value > 0) {
                amount += msg.value;
                _weth.deposit{value: msg.value}();
            }
        }
        _reserveMap[asset].spendableAmount += amount;
        _vaultMap[Types.VaultKey({asset: asset, user: recipient}).toId()].spendableAmount += amount;
        emit Deposit(asset, msg.sender, recipient, amount);
        IYieldFarmer(yieldFarmer).deposit(asset, amount);
    }

    function depositWithPermit(
        address asset,
        uint256 amount,
        address recipient,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        IERC20Permit(asset).permit(msg.sender, address(this), amount, deadline, v, r, s);
        deposit(asset, amount, recipient);
    }

    function withdraw(address asset, uint256 amount, address recipient) external nonReentrant {
        bool isNative = asset == address(0);
        if (isNative) {
            asset = address(_weth);
        }
        _checkValidAsset(asset);
        _reserveMap[asset].spendableAmount -= amount;
        _vaultMap[Types.VaultKey({asset: asset, user: msg.sender}).toId()].spendableAmount -= amount;
        emit Withdraw(asset, msg.sender, recipient, amount);
        IYieldFarmer(yieldFarmer).withdraw(isNative ? address(0) : asset, amount, recipient);
    }

    function mintCoupons(
        address asset,
        uint256[] calldata epochs,
        uint256[] calldata amounts,
        address recipient
    ) external payable {
        revert("not implemented");
    }

    function burnCoupons(Types.Coupon[] calldata coupons, address recipient) external {
        revert("not implemented");
    }

    function convertToCollateral(Types.LoanKey calldata loanKey, uint256 amount) external payable {
        revert("not implemented");
    }

    function convertToCollateralWithPermit(
        Types.LoanKey calldata loanKey,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        revert("not implemented");
    }

    function borrow(Types.Coupon[] calldata coupons, address collateral, address recipient) external {
        revert("not implemented");
    }

    function repay(Types.LoanKey calldata loanKey, uint256 amount) external payable {
        revert("not implemented");
    }

    function repayWithPermit(
        Types.LoanKey calldata loanKey,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        revert("not implemented");
    }

    function liquidate(
        address collateral,
        address debt,
        address user,
        uint256 maxRepayAmount,
        bytes calldata data
    ) external {
        revert("not implemented");
    }

    // Admin Functions //
    function registerAsset(address asset, Types.AssetConfiguration calldata config) external onlyOwner {
        require(!isAssetRegistered(asset), "Already registered");
        require(config.liquidationThreshold > 0, "Invalid liquidation threshold");
        require(config.decimal == IERC20Metadata(asset).decimals(), "Wrong decimal");
        _assetConfig[asset] = config;
        emit RegisterAsset(asset, config);

        IERC20(asset).approve(yieldFarmer, type(uint256).max);
    }

    function setTreasury(address newTreasury) external onlyOwner {
        revert("not implemented");
    }

    function _checkValidAsset(address asset) internal view {
        require(isAssetRegistered(asset), "Unregistered asset");
    }
}
