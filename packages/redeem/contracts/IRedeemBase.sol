// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/libraries-solidity/contracts/access/IAdminControl.sol";

/**
 * @dev Base redemption interface
 */
interface IRedeemBase is IAdminControl {

    struct TokenRange{
        uint256 min;
        uint256 max;
    }

    event UpdateApprovedContracts(address[] contracts, bool[] approved);
    event UpdateApprovedTokens(address contract_, uint256[] tokenIds, bool[] approved);
    event UpdateApprovedTokenRanges(address contract_, uint256[] minTokenIds, uint256[] maxTokenIds);

    /**
     * @dev Update approved contracts that can be used to redeem. Can only be called by contract owner/admin.
     */
    function updateApprovedContracts(address[] calldata contracts, bool[] calldata approved) external;

    /**
     * @dev Get array of approved contracts that can be used to redeem.
     */
    function getApprovedContracts() external view returns(address[] memory);

    /**
     * @dev Update approved tokens that can be used to redeem. Can only be called by contract owner/admin.
     */
    function updateApprovedTokens(address contract_, uint256[] calldata tokenIds, bool[] calldata approved) external;

    /**
     * @dev Get all approved tokens for every contract that can be used to redeem.
     */
    function getApprovedTokens() external view returns(address[] memory, uint256[][] memory);

    /**
     * @dev Update approved token ranges that can be used to redeem. Can only be called by contract owner/admin.
     * Clears out old ranges
     */
    function updateApprovedTokenRanges(address contract_, uint256[] calldata minTokenIds, uint256[] calldata maxTokenIds) external;

    /**
     * @dev Get all approved token ranges for every contract that can be used to redeem.
     */
    function getApprovedTokenRanges() external view returns(address[] memory, TokenRange[][] memory);

    /**
     * @dev Check if an NFT is redeemable
     */
    function redeemable(address contract_, uint256 tokenId) external view returns(bool);

}