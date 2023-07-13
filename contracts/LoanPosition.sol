// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import {Types} from "./Types.sol";
import {ILoanPosition} from "./interfaces/ILoanPosition.sol";
import {ERC721Permit} from "./libraries/ERC721Permit.sol";

contract LoanPosition is ILoanPosition, ERC721Permit {
    address public immutable override coupon;
    address public immutable override assetPool;

    string public override baseURI;
    uint256 public override nextId;

    mapping(address asset => Types.AssetLoanConfiguration) private _assetConfig;
    mapping(uint256 id => Types.Loan) private _loanMap;

    constructor(address coupon_, address assetPool_, string memory baseURI_) ERC721Permit("Loan Position", "LP", "1") {
        coupon = coupon_;
        assetPool = assetPool_;
        baseURI = baseURI_;
    }

    function loans(uint256 tokenId) external view returns (Types.Loan memory) {
        return _loanMap[tokenId];
    }

    function isAssetRegistered(address asset) external view returns (bool) {
        return _assetConfig[asset].liquidationThreshold > 0;
    }

    function getLoanConfiguration(address asset) external view returns (Types.AssetLoanConfiguration memory) {
        return _assetConfig[asset];
    }

    function getLiquidationStatus(uint256 tokenId) external view returns (Types.LiquidationStatus memory) {
        revert("not implemented");
    }

    function mint(
        address collateralToken,
        address debtToken,
        uint256 loanEpochs,
        uint256 collateralAmount,
        uint256 debtAmount,
        address recipient,
        bytes calldata data
    ) external returns (uint256) {
        revert("not implemented");
    }

    function adjustPosition(
        uint256 tokenId,
        int256 debtAmount,
        int256 collateralAmount,
        int256 loanEpochs,
        address recipient,
        bytes calldata data
    ) external {
        revert("not implemented");
    }

    function liquidate(uint256 tokenId, uint256 maxRepayAmount) external {
        revert("not implemented");
    }

    function _getAndIncrementNonce(uint256 tokenId) internal override returns (uint256) {
        return _loanMap[tokenId].nonce++;
    }
}
