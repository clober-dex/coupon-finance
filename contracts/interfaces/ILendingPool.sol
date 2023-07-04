// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

interface ILendingPool {
    struct CouponKey {
        address asset;
        uint256 maturity;
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
        address collateral;
        uint256 collateralAmount;
        address asset;
        uint256 amount;
        uint256 maturity;
    }

    // View Functions //
    function yieldFarmer() external view returns (address);

    function getReserve(address asset) external view returns (Reserve memory);

    function getVault(address asset, address user) external view returns (Vault memory);

    function withdrawable(address asset) external view returns (uint256);

    // User Functions //
    function deposit(address asset, address recipient, uint256 amount) external;

    function withdraw(address asset, address recipient, uint256 amount) external;

    function mintCoupon(CouponKey calldata couponKey, address recipient, uint256 amount) external;

    function burnCoupon(CouponKey calldata couponKey, address recipient, uint256 amount) external;

    function addCollateral(address asset, address recipient, uint256 amount) external;

    function borrow(CouponKey calldata couponKey, address collateral, address recipient, uint256 amount) external;

    function repay(address recipient, uint256 amount) external;

    function liquidate(address user, address debt, address collateral) external;

    // Admin Functions //
    function setLiquidator(address newLiquidator) external;

    function createPool() external;
}
