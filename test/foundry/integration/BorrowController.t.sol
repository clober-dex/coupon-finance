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
import {IERC721Permit} from "../../../contracts/interfaces/IERC721Permit.sol";
import {ILoanPositionManager} from "../../../contracts/interfaces/ILoanPositionManager.sol";
import {PermitParams} from "../../../contracts/libraries/PermitParams.sol";
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
    ILoanPositionManager public loanPositionManager;
    IWrapped1155Factory public wrapped1155Factory;
    ICouponManager public couponManager;
    ICouponOracle public oracle;
    CloberMarketFactory public cloberMarketFactory;
    IERC20 public usdc;
    IERC20 public weth;
    address public user;
    PermitParams public emptyPermitParams;

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

        oracle = new CouponOracle(
            Utils.toArr(Constants.USDC, Constants.WETH, address(0)),
            Utils.toArr(Constants.USDC_CHAINLINK_FEED, Constants.ETH_CHAINLINK_FEED, Constants.ETH_CHAINLINK_FEED)
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
            "loan/position/uri/"
        );
        loanPositionManager.setLoanConfiguration(Constants.USDC, Constants.WETH, 800000, 25000, 5000, 700000);
        loanPositionManager.setLoanConfiguration(Constants.WETH, Constants.USDC, 800000, 25000, 5000, 700000);

        borrowController = new BorrowController(
            Constants.WRAPPED1155_FACTORY,
            Constants.CLOBER_FACTORY,
            address(couponManager),
            Constants.WETH,
            address(loanPositionManager)
        );
        borrowController.setCollateralAllowance(Constants.USDC);
        borrowController.setCollateralAllowance(Constants.WETH);

        usdc.transfer(address(assetPool), usdc.amount(1_000));
        weth.transfer(address(assetPool), 1_000 ether);

        // create wrapped1155
        for (uint8 i = 0; i < 5; i++) {
            couponKeys.push(CouponKey({asset: Constants.USDC, epoch: EpochLibrary.current().add(i)}));
        }
        if (!cloberMarketFactory.registeredQuoteTokens(Constants.USDC)) {
            vm.prank(cloberMarketFactory.owner());
            cloberMarketFactory.registerQuoteToken(Constants.USDC);
        }
        for (uint8 i = 5; i < 10; i++) {
            couponKeys.push(CouponKey({asset: Constants.WETH, epoch: EpochLibrary.current().add(i - 5)}));
        }
        if (!cloberMarketFactory.registeredQuoteTokens(Constants.WETH)) {
            vm.prank(cloberMarketFactory.owner());
            cloberMarketFactory.registerQuoteToken(Constants.WETH);
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
                MARKET_MAKER, bidIndex, market.quoteToRaw(IERC20(key.asset).amount(100), false), 0, 3, ""
            );
            uint256 amount = IERC20(wrappedCoupons[i]).amount(100);
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
        PermitParams memory permitParams =
            _buildERC20PermitParams(1, IERC20Permit(collateralToken), address(borrowController), collateralAmount);
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

        uint256 positionId = _initialBorrow(user, Constants.USDC, Constants.WETH, collateralAmount, borrowAmount, 2);
        LoanPosition memory loanPosition = loanPositionManager.getPosition(positionId);

        uint256 couponAmount = 0.08 ether;

        assertEq(loanPositionManager.ownerOf(positionId), user, "POSITION_OWNER");
        assertEq(usdc.balanceOf(user), beforeUSDCBalance - collateralAmount, "USDC_BALANCE");
        assertGe(user.balance, beforeETHBalance + borrowAmount - couponAmount, "NATIVE_BALANCE_GE");
        assertLe(user.balance, beforeETHBalance + borrowAmount - couponAmount + 0.001 ether, "NATIVE_BALANCE_LE");
        assertEq(loanPosition.expiredWith, EpochLibrary.current().add(1), "POSITION_EXPIRE_EPOCH");
        assertEq(loanPosition.collateralAmount, collateralAmount, "POSITION_COLLATERAL_AMOUNT");
        assertEq(loanPosition.debtAmount, borrowAmount, "POSITION_DEBT_AMOUNT");
        assertEq(loanPosition.collateralToken, Constants.USDC, "POSITION_COLLATERAL_TOKEN");
        assertEq(loanPosition.debtToken, Constants.WETH, "POSITION_DEBT_TOKEN");
    }

    function testBorrowMore() public {
        uint256 positionId = _initialBorrow(user, Constants.USDC, Constants.WETH, usdc.amount(10000), 1 ether, 2);

        uint256 beforeUSDCBalance = usdc.balanceOf(user);
        uint256 beforeETHBalance = user.balance;
        LoanPosition memory beforeLoanPosition = loanPositionManager.getPosition(positionId);
        PermitParams memory permitParams =
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
        uint256 positionId = _initialBorrow(user, Constants.USDC, Constants.WETH, usdc.amount(10000), 1 ether, 2);

        uint256 beforeUSDCBalance = usdc.balanceOf(user);
        uint256 beforeETHBalance = user.balance;
        LoanPosition memory beforeLoanPosition = loanPositionManager.getPosition(positionId);
        uint256 collateralAmount = usdc.amount(123);
        PermitParams memory permit721Params =
            _buildERC721PermitParams(1, IERC721Permit(loanPositionManager), address(borrowController), positionId);
        PermitParams memory permit20Params =
            _buildERC20PermitParams(1, IERC20Permit(Constants.USDC), address(borrowController), collateralAmount);
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

    function testRemoveCollateral() public {
        uint256 positionId = _initialBorrow(user, Constants.USDC, Constants.WETH, usdc.amount(10000), 1 ether, 2);

        uint256 beforeUSDCBalance = usdc.balanceOf(user);
        uint256 beforeETHBalance = user.balance;
        LoanPosition memory beforeLoanPosition = loanPositionManager.getPosition(positionId);
        uint256 collateralAmount = usdc.amount(123);
        PermitParams memory permit721Params =
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
        uint256 positionId = _initialBorrow(user, Constants.USDC, Constants.WETH, usdc.amount(10000), 1 ether, 2);

        uint256 beforeUSDCBalance = usdc.balanceOf(user);
        uint256 beforeETHBalance = user.balance;
        LoanPosition memory beforeLoanPosition = loanPositionManager.getPosition(positionId);
        uint8 epochs = 3;
        uint256 maxPayInterest = 0.04 ether * uint256(epochs);
        PermitParams memory permit721Params =
            _buildERC721PermitParams(1, IERC721Permit(loanPositionManager), address(borrowController), positionId);
        vm.startPrank(user);
        weth.approve(address(borrowController), maxPayInterest);
        borrowController.extendLoanDuration{value: maxPayInterest}(
            positionId, epochs, maxPayInterest, permit721Params, emptyPermitParams
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
        uint256 positionId = _initialBorrow(user, Constants.USDC, Constants.WETH, usdc.amount(10000), 1 ether, 5);

        uint256 beforeUSDCBalance = usdc.balanceOf(user);
        uint256 beforeETHBalance = user.balance;
        LoanPosition memory beforeLoanPosition = loanPositionManager.getPosition(positionId);
        uint8 epochs = 3;
        uint256 minEarnInterest = 0.02 ether * epochs - 0.01 ether;
        PermitParams memory permit721Params =
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
        uint256 positionId = _initialBorrow(user, Constants.USDC, Constants.WETH, usdc.amount(10000), 1 ether, 2);

        uint256 beforeUSDCBalance = usdc.balanceOf(user);
        uint256 beforeETHBalance = user.balance;
        LoanPosition memory beforeLoanPosition = loanPositionManager.getPosition(positionId);
        uint256 repayAmount = 0.3 ether;
        PermitParams memory permit721Params =
            _buildERC721PermitParams(1, IERC721Permit(loanPositionManager), address(borrowController), positionId);
        PermitParams memory permit20Params =
            _buildERC20PermitParams(1, IERC20Permit(Constants.WETH), address(borrowController), repayAmount);
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

    function testRepayWithCollateral() public {
        uint256 positionId = _initialBorrow(user, Constants.USDC, Constants.WETH, usdc.amount(10000), 1 ether, 2);

        uint256 beforeUSDCBalance = usdc.balanceOf(user);
        uint256 beforeETHBalance = user.balance;
        LoanPosition memory beforeLoanPosition = loanPositionManager.getPosition(positionId);
        uint256 collateralAmount = usdc.amount(500);
        uint256 maxDebtAmount = 0.75 ether;
        uint24 fee = 10000;
        bytes memory exactInputSingleParams = abi.encodeWithSignature(
            "exactInputSingle((address,address,uint24,address,uint256,uint256,uint256,uint160))",
            Constants.USDC,
            Constants.WETH,
            fee,
            address(borrowController),
            block.timestamp + 1,
            collateralAmount,
            1 ether - maxDebtAmount,
            0
        );
        IBorrowController.SwapData memory swapData = IBorrowController.SwapData({
            swap: Constants.UNISWAP_V3_SWAP_ROUTER,
            inAmount: collateralAmount,
            minOutAmount: 1 ether - maxDebtAmount,
            data: exactInputSingleParams
        });

        PermitParams memory permit721Params =
            _buildERC721PermitParams(1, IERC721Permit(loanPositionManager), address(borrowController), positionId);

        vm.prank(user);
        borrowController.repayWithCollateral(positionId, maxDebtAmount, swapData, permit721Params);

        LoanPosition memory afterLoanPosition = loanPositionManager.getPosition(positionId);

        assertEq(usdc.balanceOf(user), beforeUSDCBalance, "USDC_BALANCE");
        assertLe(user.balance, beforeETHBalance, "NATIVE_BALANCE");
        assertEq(beforeLoanPosition.expiredWith, afterLoanPosition.expiredWith, "POSITION_EXPIRE_EPOCH");
        assertEq(
            beforeLoanPosition.collateralAmount - collateralAmount,
            afterLoanPosition.collateralAmount,
            "POSITION_COLLATERAL_AMOUNT"
        );
        assertLe(afterLoanPosition.debtAmount, maxDebtAmount, "POSITION_DEBT_AMOUNT");
        assertGe(afterLoanPosition.debtAmount, 0.7 ether, "POSITION_DEBT_AMOUNT");
        assertEq(beforeLoanPosition.collateralToken, afterLoanPosition.collateralToken, "POSITION_COLLATERAL_TOKEN");
        assertEq(beforeLoanPosition.debtToken, afterLoanPosition.debtToken, "POSITION_DEBT_TOKEN");
    }

    function _buildERC20PermitParams(uint256 privateKey, IERC20Permit token, address spender, uint256 amount)
        internal
        view
        returns (PermitParams memory)
    {
        address owner = vm.addr(privateKey);
        bytes32 structHash = keccak256(
            abi.encode(_ERC20_PERMIT_TYPEHASH, owner, spender, amount, token.nonces(owner), block.timestamp + 1)
        );
        bytes32 hash = ECDSA.toTypedDataHash(token.DOMAIN_SEPARATOR(), structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);
        return PermitParams(block.timestamp + 1, v, r, s);
    }

    function _buildERC721PermitParams(uint256 privateKey, IERC721Permit token, address spender, uint256 tokenId)
        internal
        view
        returns (PermitParams memory)
    {
        bytes32 structHash =
            keccak256(abi.encode(token.PERMIT_TYPEHASH(), spender, tokenId, token.nonces(tokenId), block.timestamp + 1));
        bytes32 hash = ECDSA.toTypedDataHash(token.DOMAIN_SEPARATOR(), structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);
        return PermitParams(block.timestamp + 1, v, r, s);
    }

    function assertEq(Epoch e1, Epoch e2, string memory err) internal {
        assertEq(e1.unwrap(), e2.unwrap(), err);
    }
}
