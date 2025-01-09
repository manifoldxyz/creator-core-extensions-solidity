// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

/**
 * ERC1155 Lazy Payable Claim External Metadata interface
 */
interface IERC1155LazyPayableClaimMetadataV2 {
    /**
     * @notice Get the token URI for a claim instance
     */
    function tokenURI(address creatorContract, uint256 tokenId, uint256 instanceId) external view returns (string memory);
}