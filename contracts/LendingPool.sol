// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Types} from "./Types.sol";
import {ILendingPool} from "./interfaces/ILendingPool.sol";
import {CouponKeyLibrary, LoanKeyLibrary, VaultKeyLibrary} from "./libraries/Keys.sol";
import {IYieldFarmer} from "./interfaces/IYieldFarmer.sol";

abstract contract LendingPool is ILendingPool {
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

    uint256 private immutable _maxEpochDiff;
    uint256 public immutable override startedAt;
    uint256 public immutable override epochDuration;

    address public override treasury;
    address public override yieldFarmer;

    mapping(address asset => Reserve) private _reserveMap;
    mapping(address asset => mapping(uint256 epoch => uint256)) private _reserveLockedAmountMap;
    mapping(Types.VaultId => Vault) private _vaultMap;
    mapping(Types.VaultId => mapping(uint256 epoch => uint256)) private _vaultLockedAmountMap;

    mapping(Types.LoanId => Loan) private _loanMap;
    mapping(Types.LoanId => mapping(uint256 epoch => uint256)) private _loanLimit;

    constructor(uint256 maxEpochDiff_, uint256 startedAt_, uint256 epochDuration_) {
        _maxEpochDiff = maxEpochDiff_;
        startedAt = startedAt_;
        epochDuration = epochDuration_;
    }

    // View Functions //
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
}
