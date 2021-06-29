// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/libraries-solidity/contracts/access/IAdminControl.sol";

/**
 * @dev Base redemption interface
 */
interface IRedeemBase is IAdminControl {

    event UpdateApprovedContracts(address[] contracts, bool[] approved);
    event UpdateApprovedTokens(address contract_, uint256[] tokenIds, bool[] approved);
    event UpdateApprovedTokenRanges(address contract_, uint256[] minTokenIds, uint256[] maxTokenIds);

    /**
     * @dev Update approved contracts that can be used to redeem. Can only be called by contract owner/admin.
     */
    function updateApprovedContracts(address[] calldata contracts, bool[] calldata approved) external;

    /**
     * @dev Update approved tokens that can be used to redeem. Can only be called by contract owner/admin.
     */
    function updateApprovedTokens(address contract_, uint256[] calldata tokenIds, bool[] calldata approved) external;

    /**
     * @dev Update approved token ranges that can be used to redeem. Can only be called by contract owner/admin.
     * Clears out old ranges
     */
    function updateApprovedTokenRanges(address contract_, uint256[] calldata minTokenIds, uint256[] calldata maxTokenIds) external;

    /**
     * @dev Check if an NFT is redeemable
     */
    function redeemable(address contract_, uint256 tokenId) external view returns(bool);

}