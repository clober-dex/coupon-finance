// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {Types} from "../../../contracts/Types.sol";
import {ILoanPosition, ILoanPositionEvents} from "../../../contracts/interfaces/ILoanPosition.sol";
import {INewCoupon} from "../../../contracts/interfaces/INewCoupon.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockYieldFarmer} from "../mocks/MockYieldFarmer.sol";
import {MockOracle} from "../mocks/MockOracle.sol";
import {Constants} from "./Constants.sol";

contract LoanPositionUnitTest is Test, ILoanPositionEvents {
    MockERC20 public collateral;
    MockERC20 public usdc;

    MockOracle public oracle;
    MockYieldFarmer public yieldFarmer;
    INewCoupon public coupon;
    ILoanPosition public loanPosition;

    uint256 private _snapshotId;
    Types.PermitParams private _permitParams;

    function setUp() public {
        collateral = new MockERC20("Collateral Token", "COL", 18);
        usdc = new MockERC20("USD coin", "USDC", 6);

        collateral.mint(address(this), collateral.amount(1_000_000_000));
        usdc.mint(address(this), usdc.amount(1_000_000_000));

        yieldFarmer = new MockYieldFarmer();
        oracle = new MockOracle();
        // loanPosition = new LoanPosition();

        collateral.approve(address(loanPosition), type(uint256).max);
        usdc.approve(address(loanPosition), type(uint256).max);

        oracle.setAssetPrice(address(collateral), 1800 * 10 ** 8);
        oracle.setAssetPrice(address(usdc), 10 ** 8);
    }

    function testMint() public {
        uint256 collateralAmount = collateral.amount(1);
        uint256 debtAmount = usdc.amount(100);

        loanPosition.mint(
            address(collateral),
            address(usdc),
            collateralAmount,
            debtAmount,
            2,
            address(this),
            new bytes(0)
        );
    }
}
