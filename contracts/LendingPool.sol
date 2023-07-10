// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IERC1155MetadataURI} from "@openzeppelin/contracts/token/ERC1155/extensions/IERC1155MetadataURI.sol";
import {ERC1155Supply} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {Types} from "./Types.sol";
import {IWETH9} from "./external/weth/IWETH9.sol";
import {ICoupon} from "./interfaces/ICoupon.sol";
import {ILendingPool} from "./interfaces/ILendingPool.sol";
import {IYieldFarmer} from "./interfaces/IYieldFarmer.sol";
import {CouponKeyLibrary, LoanKeyLibrary, VaultKeyLibrary} from "./libraries/Keys.sol";
import {ReentrancyGuard} from "./libraries/ReentrancyGuard.sol";

contract LendingPool is ILendingPool, ERC1155Supply, ReentrancyGuard {
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

    function getLoanLimit(Types.LoanKey calldata loanKey, uint256 epoch) external view returns (uint256) {
        return _loanLimit[loanKey.toId()][epoch];
    }

    function withdrawable(address asset) external view returns (uint256) {
        return IYieldFarmer(yieldFarmer).withdrawable(asset);
    }

    // User Functions //
    function deposit(address asset, uint256 amount, address recipient) public payable nonReentrant {}

    function depositWithPermit(
        address asset,
        uint256 amount,
        address recipient,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        revert("not implemented");
    }

    function withdraw(address asset, uint256 amount, address recipient) external returns (uint256) {
        revert("not implemented");
    }

    function mintCoupons(Types.Coupon[] calldata coupons, address recipient) external {
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

    function liquidate(address collateral, address debt, address user, uint256 maxRepayAmount) external {
        revert("not implemented");
    }

    // Admin Functions //
    function registerAsset(address asset, Types.AssetConfiguration calldata config) external {
        revert("not implemented");
    }

    function setTreasury(address newTreasury) external {
        revert("not implemented");
    }

    function _checkValidAsset(address asset) internal view {
        require(_assetConfig[asset].liquidationThreshold > 0, "invalid asset");
    }
}
