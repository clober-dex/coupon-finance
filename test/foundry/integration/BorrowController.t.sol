// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Create1} from "@clober/library/contracts/Create1.sol";

import {Constants} from "../Constants.sol";
import {ForkUtils, ERC20Utils, Utils} from "../Utils.sol";
import {IAssetPool} from "../../../contracts/interfaces/IAssetPool.sol";
import {ICouponOracle} from "../../../contracts/interfaces/ICouponOracle.sol";
import {ICouponManager} from "../../../contracts/interfaces/ICouponManager.sol";
import {IController} from "../../../contracts/interfaces/IController.sol";
import {IERC721Permit} from "../../../contracts/interfaces/IERC721Permit.sol";
import {ILoanPositionManager, ILoanPositionManagerTypes} from "../../../contracts/interfaces/ILoanPositionManager.sol";
import {Coupon, CouponLibrary} from "../../../contracts/libraries/Coupon.sol";
import {CouponKey, CouponKeyLibrary} from "../../../contracts/libraries/CouponKey.sol";
import {Epoch, EpochLibrary} from "../../../contracts/libraries/Epoch.sol";
import {LoanPosition} from "../../../contracts/libraries/LoanPosition.sol";
import {Wrapped1155MetadataBuilder} from "../../../contracts/libraries/Wrapped1155MetadataBuilder.sol";
import {IWrapped1155Factory} from "../../../contracts/external/wrapped1155/IWrapped1155Factory.sol";
import {CloberMarketFactory} from "../../../contracts/external/clober/CloberMarketFactory.sol";
import {CloberMarketSwapCallbackReceiver} from "../../../contracts/external/clober/CloberMarketSwapCallbackReceiver.sol";
import {CloberOrderBook} from "../../../contracts/external/clober/CloberOrderBook.sol";
import {BorrowController} from "../../../contracts/BorrowController.sol";
import {IBorrowController} from "../../../contracts/interfaces/IBorrowController.sol";
import {CouponManager} from "../../../contracts/CouponManager.sol";
import {LoanPositionManager} from "../../../contracts/LoanPositionManager.sol";
import {MockOracle} from "../mocks/MockOracle.sol";
import {AssetPool} from "../../../contracts/AssetPool.sol";
import {CouponOracle} from "../../../contracts/CouponOracle.sol";
import {AaveTokenSubstitute} from "../../../contracts/AaveTokenSubstitute.sol";
import "../../../contracts/BorrowAdapter.sol";

contract BorrowControllerIntegrationTest is Test, CloberMarketSwapCallbackReceiver, ERC1155Holder {
    using Strings for *;
    using ERC20Utils for IERC20;
    using CouponKeyLibrary for CouponKey;
    using EpochLibrary for Epoch;

    address public constant MARKET_MAKER = address(999123);
    bytes32 private constant _ERC20_PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    IAssetPool public assetPool;
    BorrowController public borrowController;
    BorrowAdapter public borrowAdapter;
    ILoanPositionManager public loanPositionManager;
    IWrapped1155Factory public wrapped1155Factory;
    ICouponManager public couponManager;
    ICouponOracle public oracle;
    CloberMarketFactory public cloberMarketFactory;
    IERC20 public usdc;
    IERC20 public weth;
    AaveTokenSubstitute public wausdc;
    AaveTokenSubstitute public waweth;
    address public user;
    IController.ERC20PermitParams public emptyERC20PermitParams;
    IController.PermitSignature public emptyERC721PermitParams;

    CouponKey[] public couponKeys;
    address[] public wrappedCoupons;

    function setUp() public {
        ForkUtils.fork(vm, Constants.FORK_BLOCK_NUMBER);
        user = vm.addr(1);

        usdc = IERC20(Constants.USDC);
        weth = IERC20(Constants.WETH);
        vm.startPrank(Constants.USDC_WHALE);
        usdc.transfer(user, usdc.amount(1_000_000));
        usdc.transfer(address(this), usdc.amount(1_000_000));
        vm.stopPrank();
        vm.deal(user, 1_000_000 ether);

        bool success;
        vm.startPrank(user);
        (success,) = payable(address(weth)).call{value: 500_000 ether}("");
        require(success, "transfer failed");
        vm.stopPrank();

        vm.deal(address(this), 1_000_000 ether);
        (success,) = payable(address(weth)).call{value: 500_000 ether}("");
        require(success, "transfer failed");

        wrapped1155Factory = IWrapped1155Factory(Constants.WRAPPED1155_FACTORY);
        cloberMarketFactory = CloberMarketFactory(Constants.CLOBER_FACTORY);

        wausdc = new AaveTokenSubstitute(
            Constants.WETH, Constants.USDC, Constants.AAVE_V3_POOL, address (this), address (this)
        );
        waweth = new AaveTokenSubstitute(
            Constants.WETH, Constants.WETH, Constants.AAVE_V3_POOL, address (this), address (this)
        );

        usdc.approve(address(wausdc), usdc.amount(3_000));
        wausdc.mint(usdc.amount(3_000), address(this));
        IERC20(Constants.WETH).approve(address(waweth), 3_000 ether);
        waweth.mint(3_000 ether, address(this));

        oracle = new CouponOracle(Constants.CHAINLINK_SEQUENCER_ORACLE, 1 days, 1 days);
        oracle.setFeeds(
            Utils.toArr(address(wausdc), address(waweth), address(0)),
            Utils.toArr(
                Utils.toArr(Constants.USDC_CHAINLINK_FEED),
                Utils.toArr(Constants.ETH_CHAINLINK_FEED),
                Utils.toArr(Constants.ETH_CHAINLINK_FEED)
            )
        );
        uint64 thisNonce = vm.getNonce(address(this));
        assetPool = new AssetPool(
            Utils.toArr(Create1.computeAddress(address(this), thisNonce + 2))
        );

        couponManager =
            new CouponManager(Utils.toArr(Create1.computeAddress(address(this), thisNonce + 2), address(this)), "URI/");
        loanPositionManager = new LoanPositionManager(
            address(couponManager),
            address(assetPool),
            address(oracle),
            Constants.TREASURY,
            10 ** 16,
            "loan/position/uri/",
            "URI"
        );
        loanPositionManager.setLoanConfiguration(address(wausdc), address(waweth), 800000, 25000, 5000, 700000);
        loanPositionManager.setLoanConfiguration(address(waweth), address(wausdc), 800000, 25000, 5000, 700000);

        borrowController = new BorrowController(
            Constants.WRAPPED1155_FACTORY,
            Constants.CLOBER_FACTORY,
            address(couponManager),
            Constants.WETH,
            address(loanPositionManager)
        );
        borrowAdapter = new BorrowAdapter(
            Constants.WRAPPED1155_FACTORY,
            Constants.CLOBER_FACTORY,
            address(couponManager),
            Constants.WETH,
            address(loanPositionManager),
            Constants.ODOS_V2_SWAP_ROUTER
        );

        borrowController.giveManagerAllowance(address(wausdc));
        borrowController.giveManagerAllowance(address(waweth));

        borrowAdapter.giveManagerAllowance(address(wausdc));
        borrowAdapter.giveManagerAllowance(address(waweth));

        wausdc.transfer(address(assetPool), usdc.amount(1_500));
        waweth.transfer(address(assetPool), 1_500 ether);

        // create wrapped1155
        for (uint8 i = 0; i < 5; i++) {
            couponKeys.push(CouponKey({asset: address(wausdc), epoch: EpochLibrary.current().add(i)}));
        }
        if (!cloberMarketFactory.registeredQuoteTokens(address(wausdc))) {
            vm.prank(cloberMarketFactory.owner());
            cloberMarketFactory.registerQuoteToken(address(wausdc));
        }
        for (uint8 i = 5; i < 10; i++) {
            couponKeys.push(CouponKey({asset: address(waweth), epoch: EpochLibrary.current().add(i - 5)}));
        }
        if (!cloberMarketFactory.registeredQuoteTokens(address(waweth))) {
            vm.prank(cloberMarketFactory.owner());
            cloberMarketFactory.registerQuoteToken(address(waweth));
        }
        for (uint256 i = 0; i < 10; i++) {
            address wrappedToken = wrapped1155Factory.requireWrapped1155(
                address(couponManager),
                couponKeys[i].toId(),
                Wrapped1155MetadataBuilder.buildWrapped1155Metadata(couponKeys[i])
            );
            wrappedCoupons.push(wrappedToken);
            address market = cloberMarketFactory.createVolatileMarket(
                address(Constants.TREASURY),
                couponKeys[i].asset,
                wrappedToken,
                i < 5 ? 1 : 1e9,
                0,
                400,
                1e10,
                1001 * 1e15
            );
            borrowController.setCouponMarket(couponKeys[i], market);
            borrowAdapter.setCouponMarket(couponKeys[i], market);
        }
        _marketMake();

        vm.prank(Constants.USDC_WHALE);
        usdc.transfer(user, usdc.amount(10_000));
        vm.deal(address(user), 100 ether);
    }

    function _marketMake() internal {
        for (uint256 i = 0; i < wrappedCoupons.length; ++i) {
            CouponKey memory key = couponKeys[i];
            CloberOrderBook market = CloberOrderBook(borrowController.getCouponMarket(key));
            (uint16 bidIndex,) = market.priceToIndex(1e18 / 100 * 2, false); // 2%
            (uint16 askIndex,) = market.priceToIndex(1e18 / 100 * 4, false); // 4%
            CloberOrderBook(market).limitOrder(
                MARKET_MAKER, bidIndex, market.quoteToRaw(IERC20(key.asset).amount(1), false), 0, 3, ""
            );
            uint256 amount = IERC20(wrappedCoupons[i]).amount(5000);
            Coupon[] memory coupons = Utils.toArr(Coupon(key, amount));
            couponManager.mintBatch(address(this), coupons, "");
            couponManager.safeBatchTransferFrom(
                address(this),
                address(wrapped1155Factory),
                coupons,
                Wrapped1155MetadataBuilder.buildWrapped1155Metadata(couponKeys[i])
            );
            CloberOrderBook(market).limitOrder(MARKET_MAKER, askIndex, 0, amount, 2, "");
        }
    }

    function cloberMarketSwapCallback(address inputToken, address, uint256 inputAmount, uint256, bytes calldata)
        external
        payable
    {
        if (inputAmount > 0) {
            IERC20(inputToken).transfer(msg.sender, inputAmount);
        }
    }

    function _initialBorrow(
        address borrower,
        address collateralToken,
        address borrowToken,
        uint256 collateralAmount,
        uint256 borrowAmount,
        uint8 loanEpochs
    ) internal returns (uint256 positionId) {
        positionId = loanPositionManager.nextId();
        IController.ERC20PermitParams memory permitParams = _buildERC20PermitParams(
            1, AaveTokenSubstitute(payable(collateralToken)), address(borrowController), collateralAmount
        );
        vm.prank(borrower);
        borrowController.borrow(
            collateralToken, borrowToken, collateralAmount, borrowAmount, type(uint256).max, loanEpochs, permitParams
        );
    }

    function testBorrow() public {
        uint256 collateralAmount = usdc.amount(10000);
        uint256 borrowAmount = 1 ether;

        uint256 beforeUSDCBalance = usdc.balanceOf(user);
        uint256 beforeETHBalance = user.balance;

        uint256 positionId = _initialBorrow(user, address(wausdc), address(waweth), collateralAmount, borrowAmount, 2);
        LoanPosition memory loanPosition = loanPositionManager.getPosition(positionId);

        uint256 couponAmount = 0.08 ether;

        assertEq(loanPositionManager.ownerOf(positionId), user, "POSITION_OWNER");
        assertEq(usdc.balanceOf(user), beforeUSDCBalance - collateralAmount, "USDC_BALANCE");
        assertGe(user.balance, beforeETHBalance + borrowAmount - couponAmount, "NATIVE_BALANCE_GE");
        assertLe(user.balance, beforeETHBalance + borrowAmount - couponAmount + 0.001 ether, "NATIVE_BALANCE_LE");
        assertEq(loanPosition.expiredWith, EpochLibrary.current().add(1), "POSITION_EXPIRE_EPOCH");
        assertEq(loanPosition.collateralAmount, collateralAmount, "POSITION_COLLATERAL_AMOUNT");
        assertEq(loanPosition.debtAmount, borrowAmount, "POSITION_DEBT_AMOUNT");
        assertEq(loanPosition.collateralToken, address(wausdc), "POSITION_COLLATERAL_TOKEN");
        assertEq(loanPosition.debtToken, address(waweth), "POSITION_DEBT_TOKEN");
    }

    function testBorrowMore() public {
        uint256 positionId = _initialBorrow(user, address(wausdc), address(waweth), usdc.amount(10000), 1 ether, 2);

        uint256 beforeUSDCBalance = usdc.balanceOf(user);
        uint256 beforeETHBalance = user.balance;
        LoanPosition memory beforeLoanPosition = loanPositionManager.getPosition(positionId);
        IController.PermitSignature memory permitParams =
            _buildERC721PermitParams(1, IERC721Permit(loanPositionManager), address(borrowController), positionId);
        vm.prank(user);
        borrowController.borrowMore(positionId, 0.5 ether, type(uint256).max, permitParams);
        LoanPosition memory afterLoanPosition = loanPositionManager.getPosition(positionId);

        uint256 borrowMoreAmount = 0.5 ether;
        uint256 couponAmount = 0.04 ether;

        assertEq(usdc.balanceOf(user), beforeUSDCBalance, "USDC_BALANCE");
        assertGe(user.balance, beforeETHBalance + borrowMoreAmount - couponAmount, "NATIVE_BALANCE_GE");
        assertLe(user.balance, beforeETHBalance + borrowMoreAmount - couponAmount + 0.001 ether, "NATIVE_BALANCE_LE");
        assertEq(beforeLoanPosition.expiredWith, afterLoanPosition.expiredWith, "POSITION_EXPIRE_EPOCH");
        assertEq(beforeLoanPosition.collateralAmount, afterLoanPosition.collateralAmount, "POSITION_COLLATERAL_AMOUNT");
        assertEq(beforeLoanPosition.debtAmount + borrowMoreAmount, afterLoanPosition.debtAmount, "POSITION_DEBT_AMOUNT");
        assertEq(beforeLoanPosition.collateralToken, afterLoanPosition.collateralToken, "POSITION_COLLATERAL_TOKEN");
        assertEq(beforeLoanPosition.debtToken, afterLoanPosition.debtToken, "POSITION_DEBT_TOKEN");
    }

    function testAddCollateral() public {
        uint256 positionId = _initialBorrow(user, address(wausdc), address(waweth), usdc.amount(10000), 1 ether, 2);

        uint256 beforeUSDCBalance = usdc.balanceOf(user);
        uint256 beforeETHBalance = user.balance;
        LoanPosition memory beforeLoanPosition = loanPositionManager.getPosition(positionId);
        uint256 collateralAmount = usdc.amount(123);
        IController.PermitSignature memory permit721Params =
            _buildERC721PermitParams(1, IERC721Permit(loanPositionManager), address(borrowController), positionId);
        IController.ERC20PermitParams memory permit20Params =
            _buildERC20PermitParams(1, wausdc, address(borrowController), collateralAmount);
        vm.prank(user);
        borrowController.addCollateral(positionId, collateralAmount, permit721Params, permit20Params);
        LoanPosition memory afterLoanPosition = loanPositionManager.getPosition(positionId);

        assertEq(usdc.balanceOf(user), beforeUSDCBalance - collateralAmount, "USDC_BALANCE");
        assertEq(user.balance, beforeETHBalance, "NATIVE_BALANCE");
        assertEq(beforeLoanPosition.expiredWith, afterLoanPosition.expiredWith, "POSITION_EXPIRE_EPOCH");
        assertEq(
            beforeLoanPosition.collateralAmount + collateralAmount,
            afterLoanPosition.collateralAmount,
            "POSITION_COLLATERAL_AMOUNT"
        );
        assertEq(beforeLoanPosition.debtAmount, afterLoanPosition.debtAmount, "POSITION_DEBT_AMOUNT");
        assertEq(beforeLoanPosition.collateralToken, afterLoanPosition.collateralToken, "POSITION_COLLATERAL_TOKEN");
        assertEq(beforeLoanPosition.debtToken, afterLoanPosition.debtToken, "POSITION_DEBT_TOKEN");
    }

    function testLeverage() public {
        uint256 collateralAmount = 0.4 ether;
        uint256 borrowAmount = usdc.amount(550);

        uint256 beforeUSDCBalance = usdc.balanceOf(user);
        uint256 beforeWETHBalance = weth.balanceOf(user);
        uint256 beforeETHBalance = user.balance;

        uint256 positionId = loanPositionManager.nextId();
        IController.ERC20PermitParams memory permitParams = _buildERC20PermitParams(
            1, AaveTokenSubstitute(payable(address(wausdc))), address(borrowAdapter), collateralAmount
        );

        bytes memory data = fromHex(
            string.concat(
                "83bd37f90001af88d065e77c8cc2239327c5edb3a432268e5831000182af49447d8a07e3bd95bd0d56f35241523fbab1041dcd65000803c174ee39d2c08007ae1400017e3e803E966291EE9aA69e6FADa116cD07462E5D00000001",
                this.remove0x(Strings.toHexString(address(borrowAdapter))),
                "0000000103010204014386e4ac0b01000102000022010203020203ff0000000000000000006f38e884725a116c9c7fbf208e79fe8828a2595faf88d065e77c8cc2239327c5edb3a432268e583182af49447d8a07e3bd95bd0d56f35241523fbab100000000"
            )
        );

        vm.prank(user);
        borrowAdapter.leverage{value: 0.13 ether}(
            address(waweth), address(wausdc), collateralAmount, borrowAmount, type(uint256).max, 2, data, permitParams
        );

        LoanPosition memory loanPosition = loanPositionManager.getPosition(positionId);

        assertEq(loanPositionManager.ownerOf(positionId), user, "POSITION_OWNER");
        assertGt(usdc.balanceOf(user) - beforeUSDCBalance, 0, "USDC_BALANCE");
        assertLt(beforeETHBalance - user.balance, 0.13 ether, "NATIVE_BALANCE");
        assertEq(beforeWETHBalance, weth.balanceOf(user), "WETH_BALANCE");
        assertEq(loanPosition.expiredWith, EpochLibrary.current().add(1), "POSITION_EXPIRE_EPOCH");
        assertEq(loanPosition.collateralAmount, collateralAmount, "POSITION_COLLATERAL_AMOUNT");
        assertEq(loanPosition.debtAmount, borrowAmount, "POSITION_DEBT_AMOUNT");
        assertEq(loanPosition.collateralToken, address(waweth), "POSITION_COLLATERAL_TOKEN");
        assertEq(loanPosition.debtToken, address(wausdc), "POSITION_DEBT_TOKEN");
    }

    function testLeverageMore() public {
        uint256 positionId = _initialBorrow(user, address(waweth), address(wausdc), 1 ether, usdc.amount(500), 2);

        uint256 beforeUSDCBalance = usdc.balanceOf(user);
        uint256 beforeWETHBalance = weth.balanceOf(user);
        uint256 beforeETHBalance = user.balance;

        LoanPosition memory loanPosition = loanPositionManager.getPosition(positionId);

        uint256 beforePositionCollateralAmount = loanPosition.collateralAmount;
        uint256 beforePositionDebtAmount = loanPosition.debtAmount;

        uint256 collateralAmount = 0.4 ether;
        uint256 borrowAmount = usdc.amount(550);

        IController.ERC20PermitParams memory permitParams = _buildERC20PermitParams(
            1, AaveTokenSubstitute(payable(address(wausdc))), address(borrowAdapter), collateralAmount
        );

        IController.PermitSignature memory permit721Params =
            _buildERC721PermitParams(1, IERC721Permit(loanPositionManager), address(borrowAdapter), positionId);

        bytes memory data = fromHex(
            string.concat(
                "83bd37f90001af88d065e77c8cc2239327c5edb3a432268e5831000182af49447d8a07e3bd95bd0d56f35241523fbab1041dcd65000803c174ee39d2c08007ae1400017e3e803E966291EE9aA69e6FADa116cD07462E5D00000001",
                this.remove0x(Strings.toHexString(address(borrowAdapter))),
                "0000000103010204014386e4ac0b01000102000022010203020203ff0000000000000000006f38e884725a116c9c7fbf208e79fe8828a2595faf88d065e77c8cc2239327c5edb3a432268e583182af49447d8a07e3bd95bd0d56f35241523fbab100000000"
            )
        );

        vm.prank(user);
        borrowAdapter.leverageMore{value: 0.13 ether}(
            positionId, collateralAmount, borrowAmount, type(uint256).max, data, permit721Params, permitParams
        );

        loanPosition = loanPositionManager.getPosition(positionId);

        assertEq(loanPositionManager.ownerOf(positionId), user, "POSITION_OWNER");
        assertGt(usdc.balanceOf(user) - beforeUSDCBalance, 0, "USDC_BALANCE");
        assertLt(beforeETHBalance - user.balance, 0.13 ether, "NATIVE_BALANCE");
        assertEq(beforeWETHBalance, weth.balanceOf(user), "WETH_BALANCE");
        assertEq(loanPosition.expiredWith, EpochLibrary.current().add(1), "POSITION_EXPIRE_EPOCH");
        assertEq(
            loanPosition.collateralAmount,
            collateralAmount + beforePositionCollateralAmount,
            "POSITION_COLLATERAL_AMOUNT"
        );
        assertEq(loanPosition.debtAmount, borrowAmount + beforePositionDebtAmount, "POSITION_DEBT_AMOUNT");
        assertEq(loanPosition.collateralToken, address(waweth), "POSITION_COLLATERAL_TOKEN");
        assertEq(loanPosition.debtToken, address(wausdc), "POSITION_DEBT_TOKEN");
    }

    function testRemoveCollateral() public {
        uint256 positionId = _initialBorrow(user, address(wausdc), address(waweth), usdc.amount(10000), 1 ether, 2);

        uint256 beforeUSDCBalance = usdc.balanceOf(user);
        uint256 beforeETHBalance = user.balance;
        LoanPosition memory beforeLoanPosition = loanPositionManager.getPosition(positionId);
        uint256 collateralAmount = usdc.amount(123);
        IController.PermitSignature memory permit721Params =
            _buildERC721PermitParams(1, IERC721Permit(loanPositionManager), address(borrowController), positionId);
        vm.prank(user);
        borrowController.removeCollateral(positionId, collateralAmount, permit721Params);
        LoanPosition memory afterLoanPosition = loanPositionManager.getPosition(positionId);

        assertEq(usdc.balanceOf(user), beforeUSDCBalance + collateralAmount, "USDC_BALANCE");
        assertEq(user.balance, beforeETHBalance, "NATIVE_BALANCE");
        assertEq(beforeLoanPosition.expiredWith, afterLoanPosition.expiredWith, "POSITION_EXPIRE_EPOCH");
        assertEq(
            beforeLoanPosition.collateralAmount - collateralAmount,
            afterLoanPosition.collateralAmount,
            "POSITION_COLLATERAL_AMOUNT"
        );
        assertEq(beforeLoanPosition.debtAmount, afterLoanPosition.debtAmount, "POSITION_DEBT_AMOUNT");
        assertEq(beforeLoanPosition.collateralToken, afterLoanPosition.collateralToken, "POSITION_COLLATERAL_TOKEN");
        assertEq(beforeLoanPosition.debtToken, afterLoanPosition.debtToken, "POSITION_DEBT_TOKEN");
    }

    function testExtendLoanDuration() public {
        uint256 positionId = _initialBorrow(user, address(wausdc), address(waweth), usdc.amount(10000), 1 ether, 2);

        uint256 beforeUSDCBalance = usdc.balanceOf(user);
        uint256 beforeETHBalance = user.balance;
        LoanPosition memory beforeLoanPosition = loanPositionManager.getPosition(positionId);
        uint8 epochs = 3;
        uint256 maxPayInterest = 0.04 ether * uint256(epochs);
        IController.PermitSignature memory permit721Params =
            _buildERC721PermitParams(1, IERC721Permit(loanPositionManager), address(borrowController), positionId);
        vm.startPrank(user);
        weth.approve(address(borrowController), maxPayInterest);
        borrowController.extendLoanDuration{value: maxPayInterest}(
            positionId, epochs, maxPayInterest, permit721Params, emptyERC20PermitParams
        );
        vm.stopPrank();
        LoanPosition memory afterLoanPosition = loanPositionManager.getPosition(positionId);

        assertEq(usdc.balanceOf(user), beforeUSDCBalance, "USDC_BALANCE");
        assertGe(user.balance, beforeETHBalance - maxPayInterest, "NATIVE_BALANCE_GE");
        assertLe(user.balance, beforeETHBalance + 0.01 ether - maxPayInterest, "NATIVE_BALANCE_LE");
        assertEq(beforeLoanPosition.expiredWith.add(epochs), afterLoanPosition.expiredWith, "POSITION_EXPIRE_EPOCH");
        assertEq(beforeLoanPosition.collateralAmount, afterLoanPosition.collateralAmount, "POSITION_COLLATERAL_AMOUNT");
        assertEq(beforeLoanPosition.debtAmount, afterLoanPosition.debtAmount, "POSITION_DEBT_AMOUNT");
        assertEq(beforeLoanPosition.collateralToken, afterLoanPosition.collateralToken, "POSITION_COLLATERAL_TOKEN");
        assertEq(beforeLoanPosition.debtToken, afterLoanPosition.debtToken, "POSITION_DEBT_TOKEN");
    }

    function testShortenLoanDuration() public {
        uint256 positionId = _initialBorrow(user, address(wausdc), address(waweth), usdc.amount(10000), 1 ether, 5);

        uint256 beforeUSDCBalance = usdc.balanceOf(user);
        uint256 beforeETHBalance = user.balance;
        LoanPosition memory beforeLoanPosition = loanPositionManager.getPosition(positionId);
        uint8 epochs = 3;
        uint256 minEarnInterest = 0.02 ether * epochs - 0.01 ether;
        IController.PermitSignature memory permit721Params =
            _buildERC721PermitParams(1, IERC721Permit(loanPositionManager), address(borrowController), positionId);
        vm.prank(user);
        borrowController.shortenLoanDuration(positionId, epochs, minEarnInterest, permit721Params);
        LoanPosition memory afterLoanPosition = loanPositionManager.getPosition(positionId);

        assertEq(usdc.balanceOf(user), beforeUSDCBalance, "USDC_BALANCE");
        assertGe(user.balance, beforeETHBalance + minEarnInterest, "NATIVE_BALANCE_GE");
        assertLe(user.balance, beforeETHBalance + minEarnInterest + 0.01 ether, "NATIVE_BALANCE_LE");
        assertEq(beforeLoanPosition.expiredWith, afterLoanPosition.expiredWith.add(epochs), "POSITION_EXPIRE_EPOCH");
        assertEq(beforeLoanPosition.collateralAmount, afterLoanPosition.collateralAmount, "POSITION_COLLATERAL_AMOUNT");
        assertEq(beforeLoanPosition.debtAmount, afterLoanPosition.debtAmount, "POSITION_DEBT_AMOUNT");
        assertEq(beforeLoanPosition.collateralToken, afterLoanPosition.collateralToken, "POSITION_COLLATERAL_TOKEN");
        assertEq(beforeLoanPosition.debtToken, afterLoanPosition.debtToken, "POSITION_DEBT_TOKEN");
    }

    function testRepay() public {
        uint256 positionId = _initialBorrow(user, address(wausdc), address(waweth), usdc.amount(10000), 1 ether, 2);

        uint256 beforeUSDCBalance = usdc.balanceOf(user);
        uint256 beforeETHBalance = user.balance;
        LoanPosition memory beforeLoanPosition = loanPositionManager.getPosition(positionId);
        uint256 repayAmount = 0.3 ether;
        IController.PermitSignature memory permit721Params =
            _buildERC721PermitParams(1, IERC721Permit(loanPositionManager), address(borrowController), positionId);
        IController.ERC20PermitParams memory permit20Params =
            _buildERC20PermitParams(1, waweth, address(borrowController), repayAmount);
        vm.prank(user);
        borrowController.repay{value: repayAmount}(positionId, repayAmount, 0, permit721Params, permit20Params);
        LoanPosition memory afterLoanPosition = loanPositionManager.getPosition(positionId);

        uint256 couponAmount = 0.012 ether;

        assertEq(usdc.balanceOf(user), beforeUSDCBalance, "USDC_BALANCE");
        assertLe(user.balance, beforeETHBalance - repayAmount + couponAmount, "NATIVE_BALANCE_GE");
        assertGe(user.balance, beforeETHBalance - repayAmount + couponAmount - 0.0001 ether, "NATIVE_BALANCE_LE");
        assertEq(beforeLoanPosition.expiredWith, afterLoanPosition.expiredWith, "POSITION_EXPIRE_EPOCH");
        assertEq(beforeLoanPosition.collateralAmount, afterLoanPosition.collateralAmount, "POSITION_COLLATERAL_AMOUNT");
        assertEq(beforeLoanPosition.debtAmount, afterLoanPosition.debtAmount + repayAmount, "POSITION_DEBT_AMOUNT");
        assertEq(beforeLoanPosition.collateralToken, afterLoanPosition.collateralToken, "POSITION_COLLATERAL_TOKEN");
        assertEq(beforeLoanPosition.debtToken, afterLoanPosition.debtToken, "POSITION_DEBT_TOKEN");
    }

    function testRepayOverCloberMarket() public {
        uint256 positionId = _initialBorrow(user, address(wausdc), address(waweth), usdc.amount(200_000), 70 ether, 2);

        uint256 repayAmount = 60 ether;
        IController.PermitSignature memory permit721Params =
            _buildERC721PermitParams(1, IERC721Permit(loanPositionManager), address(borrowController), positionId);
        IController.ERC20PermitParams memory permit20Params =
            _buildERC20PermitParams(1, waweth, address(borrowController), repayAmount);
        vm.prank(user);
        borrowController.repay{value: repayAmount}(positionId, repayAmount, 0, permit721Params, permit20Params);

        assertGt(couponManager.balanceOf(user, couponKeys[5].toId()), 9.9 ether, "COUPON0_BALANCE");
        assertLt(couponManager.balanceOf(user, couponKeys[6].toId()), 10 ether, "COUPON0_BALANCE");
    }

    function testExpiredBorrowMore() public {
        uint256 positionId = _initialBorrow(user, address(wausdc), address(waweth), usdc.amount(10000), 1 ether, 2);
        // loan duration is 2 epochs
        vm.warp(EpochLibrary.current().add(2).startTime());
        IController.PermitSignature memory permitParams =
            _buildERC721PermitParams(1, IERC721Permit(loanPositionManager), address(borrowController), positionId);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(ILoanPositionManagerTypes.FullRepaymentRequired.selector));
        borrowController.borrowMore(positionId, 0.5 ether, type(uint256).max, permitParams);
    }

    function testExpiredReduceCollateral() public {
        uint256 positionId = _initialBorrow(user, address(wausdc), address(waweth), usdc.amount(10000), 1 ether, 2);
        uint256 collateralAmount = usdc.amount(123);
        // loan duration is 2 epochs
        vm.warp(EpochLibrary.current().add(2).startTime());
        IController.PermitSignature memory permit721Params =
            _buildERC721PermitParams(1, IERC721Permit(loanPositionManager), address(borrowController), positionId);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(ILoanPositionManagerTypes.FullRepaymentRequired.selector));
        borrowController.removeCollateral(positionId, collateralAmount, permit721Params);
    }

    // Convert an hexadecimal character to their value
    function fromHexChar(uint8 c) public pure returns (uint8) {
        if (bytes1(c) >= bytes1("0") && bytes1(c) <= bytes1("9")) {
            return c - uint8(bytes1("0"));
        }
        if (bytes1(c) >= bytes1("a") && bytes1(c) <= bytes1("f")) {
            return 10 + c - uint8(bytes1("a"));
        }
        if (bytes1(c) >= bytes1("A") && bytes1(c) <= bytes1("F")) {
            return 10 + c - uint8(bytes1("A"));
        }
        revert("fail");
    }

    // Convert an hexadecimal string to raw bytes
    function fromHex(string memory s) public pure returns (bytes memory) {
        bytes memory ss = bytes(s);
        require(ss.length % 2 == 0); // length must be even
        bytes memory r = new bytes(ss.length/2);
        for (uint256 i = 0; i < ss.length / 2; ++i) {
            r[i] = bytes1(fromHexChar(uint8(ss[2 * i])) * 16 + fromHexChar(uint8(ss[2 * i + 1])));
        }
        return r;
    }

    function remove0x(string calldata s) external pure returns (string memory) {
        return s[2:];
    }

    function _buildERC20PermitParams(
        uint256 privateKey,
        AaveTokenSubstitute substitute,
        address spender,
        uint256 amount
    ) internal view returns (IController.ERC20PermitParams memory) {
        IERC20Permit token = IERC20Permit(substitute.underlyingToken());
        address owner = vm.addr(privateKey);
        bytes32 structHash = keccak256(
            abi.encode(_ERC20_PERMIT_TYPEHASH, owner, spender, amount, token.nonces(owner), block.timestamp + 1)
        );
        bytes32 hash = ECDSA.toTypedDataHash(token.DOMAIN_SEPARATOR(), structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);
        return IController.ERC20PermitParams(amount, IController.PermitSignature(block.timestamp + 1, v, r, s));
    }

    function _buildERC721PermitParams(uint256 privateKey, IERC721Permit token, address spender, uint256 tokenId)
        internal
        view
        returns (IController.PermitSignature memory)
    {
        bytes32 structHash =
            keccak256(abi.encode(token.PERMIT_TYPEHASH(), spender, tokenId, token.nonces(tokenId), block.timestamp + 1));
        bytes32 hash = ECDSA.toTypedDataHash(token.DOMAIN_SEPARATOR(), structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);
        return IController.PermitSignature(block.timestamp + 1, v, r, s);
    }

    function assertEq(Epoch e1, Epoch e2, string memory err) internal {
        assertEq(Epoch.unwrap(e1), Epoch.unwrap(e2), err);
    }
}
