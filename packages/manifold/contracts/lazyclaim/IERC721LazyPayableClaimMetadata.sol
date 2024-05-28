// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

/**
 * ERC721 Lazy Payable Claim External Metadata interface
 */
interface IERC721LazyPayableClaimMetadata {
    /**
     * @notice Get the token URI for a claim instance
     */
    function tokenURI(address creatorContract, uint256 tokenId, uint256 instanceId, uint24 mintOrder) external view returns (string memory);
}