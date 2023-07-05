// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "./ICoupon.sol";

interface ILendingPoolEvents {
    event Deposit(address indexed asset, address indexed sender, address indexed user, uint256 amount);
    event Withdraw(address indexed asset, address indexed user, address indexed to, uint256 amount);
}

interface ILendingPoolTypes {
    struct CouponKey {
        address asset;
        uint256 epoch;
    }

    struct Reserve {
        uint256 amount;
        uint256 locked;
    }

    struct Vault {
        uint256 amount;
        uint256 locked;
    }

    struct LoanKey {
        address user;
        address collateral;
        address asset;
    }

    struct Loan {
        uint256 amount;
        uint256 collateralAmount;
    }
}

interface ILendingPool is ILendingPoolEvents, ILendingPoolTypes, ICouponPool {
    // View Functions //
    function epochDuration() external view returns (uint256);

    function currentEpoch() external view returns (uint256);

    function yieldFarmer() external view returns (address);

    function getReserve(address asset) external view returns (Reserve memory);

    function getVault(address asset, address user) external view returns (Vault memory);

    function getLoan(bytes32 loanId) external view returns (Loan memory);

    function getLoanLimit(bytes32 loanId, uint256 epoch) external view returns (uint256);

    function withdrawable(address asset) external view returns (uint256);

    // User Functions //
    function deposit(address asset, uint256 amount, address recipient) external payable;

    // @dev If the amount exceeds the withdrawable balance, it will withdraw the maximum amount.
    function withdraw(address asset, uint256 amount, address recipient) external returns (uint256);

    function mintCoupon(CouponKey calldata couponKey, uint256 amount, address recipient) external;

    function burnCoupon(CouponKey calldata couponKey, uint256 amount, address recipient) external;

    function addCollateral(address asset, uint256 amount, address recipient) external;

    function borrow(CouponKey calldata couponKey, address collateral, uint256 amount, address recipient) external;

    function repay(address asset, uint256 amount, address recipient) external;

    function liquidate(address collateral, address debt, address user) external;

    // Admin Functions //
    function setLiquidator(address newLiquidator) external;

    function createPool() external;
}
