// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {
    IBondPositionManager, IBondPositionManagerTypes
} from "../../../../contracts/interfaces/IBondPositionManager.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";
import {MockAssetPool} from "../../mocks/MockAssetPool.sol";
import {TestInitializer} from "./helpers/TestInitializer.sol";

contract BondPositionManagerAdminUnitTest is Test, IBondPositionManagerTypes {
    MockAssetPool public assetPool;
    IBondPositionManager public bondPositionManager;

    function setUp() public {
        TestInitializer.Params memory p = TestInitializer.init(vm);
        assetPool = p.assetPool;
        bondPositionManager = p.bondPositionManager;
    }

    function testRegisterAsset() public {
        MockERC20 newToken = new MockERC20("New", "NEW", 18);
        assertTrue(!bondPositionManager.isAssetRegistered(address(newToken)), "NEW_TOKEN_IS_REGISTERED");
        vm.expectEmit(true, true, true, true);
        emit AssetRegistered(address(newToken));
        bondPositionManager.registerAsset(address(newToken));
        assertTrue(bondPositionManager.isAssetRegistered(address(newToken)), "NEW_TOKEN_IS_NOT_REGISTERED");
        assertEq(newToken.allowance(address(bondPositionManager), address(assetPool)), type(uint256).max, "ALLOWANCE");
    }

    function testRegisterAssetOwnership() public {
        MockERC20 newToken = new MockERC20("New", "NEW", 18);
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(address(0x123));
        bondPositionManager.registerAsset(address(newToken));
    }
}
