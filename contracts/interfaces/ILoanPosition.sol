// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

import {Types} from "../Types.sol";
import {IERC721Permit} from "./IERC721Permit.sol";

interface ILoanPosition is IERC721Permit, IERC721Metadata {
    function baseURI() external view returns (string memory);

    function coupon() external view returns (address);

    function nextId() external view returns (uint256);

    function loans(uint256 tokenId) external view returns (Types.Loan memory);

    function getLiquidationStatus(uint256 tokenId) external view returns (Types.LiquidationStatus memory);

    function mint(
        address collateralToken,
        address debtToken,
        uint256 loanEpochs,
        uint256 collateralAmount,
        uint256 debtAmount,
        address recipient,
        bytes calldata data
    ) external payable returns (uint256);

    function adjustPosition(
        uint256 tokenId,
        int256 debtAmount,
        int256 collateralAmount,
        int256 loanEpochs,
        address recipient,
        bytes calldata data
    ) external;

    function liquidate(uint256 tokenId, uint256 maxRepayAmount) external;
}
