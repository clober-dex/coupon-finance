// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

import {Types} from "../Types.sol";
import {IERC721Permit} from "./IERC721Permit.sol";

interface ILoanPosition is IERC721Permit, IERC721Metadata {
    function baseURI() external view returns (string memory);

    function coupon() external view returns (address);

    function assetPool() external view returns (address);

    function nextId() external view returns (uint256);

    function mint(
        address collateralToken,
        address loanToken,
        uint256 loanEpochs,
        uint256 collateralAmount,
        uint256 loanAmount,
        address recipient
    ) external payable returns (uint256);

    function mintWithPermit(
        address collateralToken,
        address loanToken,
        uint256 loanEpochs,
        uint256 collateralAmount,
        uint256 loanAmount,
        address recipient,
        Types.PermitParams calldata permitParams
    ) external returns (uint256);

    function increaseLoan(uint256 tokenId, uint256 loanAmount, address recipient) external;

    function decreaseLoan(uint256 tokenId, uint256 loanAmount, address recipient) external payable;

    function decreaseLoanWithPermit(
        uint256 tokenId,
        uint256 loanAmount,
        address recipient,
        Types.PermitParams calldata permitParams
    ) external;

    function increaseCollateral(uint256 tokenId, uint256 collateralAmount, address recipient) external payable;

    function increaseCollateralWithPermit(
        uint256 tokenId,
        uint256 collateralAmount,
        address recipient,
        Types.PermitParams calldata permitParams
    ) external;

    function decreaseCollateral(uint256 tokenId, uint256 collateralAmount, address recipient) external;

    function increaseEpochs(uint256 tokenId, uint256 epochs, address recipient) external;

    function decreaseEpochs(uint256 tokenId, uint256 epochs, address recipient) external;

    function liquidate(uint256 tokenId, uint256 maxRepayAmount) external;

    function burn(uint256 tokenId, address recipient) external;
}
