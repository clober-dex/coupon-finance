// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

import {Types} from "../Types.sol";
import {IERC721Permit} from "./IERC721Permit.sol";

interface ILoanPositionEvents {
    event AssetRegistered(address indexed asset);
    event PositionUpdated(uint256 indexed tokenId, uint256 collateralAmount, uint256 debtAmount, uint256 unlockedAt);
}

interface ILoanPosition is IERC721Metadata, IERC721Permit, ILoanPositionEvents {
    function baseURI() external view returns (string memory);

    function treasury() external view returns (address);

    function oracle() external view returns (address);

    function nextId() external view returns (uint256);

    function coupon() external view returns (address);

    function assetPool() external view returns (address);

    function minDebtValueInEth() external view returns (uint256);

    function couponOwed(address user, uint256 couponId) external view returns (uint256);

    function loans(uint256 tokenId) external view returns (Types.Loan memory);

    function isAssetRegistered(address asset) external view returns (bool);

    function getLoanConfiguration(address asset) external view returns (Types.AssetLoanConfiguration memory);

    function setLoanConfiguration(address asset, Types.AssetLoanConfiguration memory config) external;

    function getLiquidationStatus(
        uint256 tokenId,
        uint256 maxRepayAmount
    ) external view returns (Types.LiquidationStatus memory);

    function mint(
        address collateralToken,
        address debtToken,
        uint256 collateralAmount,
        uint256 debtAmount,
        uint256 loanEpochs,
        address recipient,
        bytes calldata data
    ) external returns (uint256);

    function adjustPosition(
        uint256 tokenId,
        int256 collateralAmount,
        int256 debtAmount,
        int256 loanEpochs,
        bytes calldata data
    ) external;

    function liquidate(uint256 tokenId, uint256 maxRepayAmount, bytes calldata data) external;

    function burn(uint256 tokenId) external;
}
