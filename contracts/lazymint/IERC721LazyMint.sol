// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

/**
 * Lazy Mint interface
 */
interface IERC721LazyMint {
    struct Listing {
        bytes32 merkleRoot;
        string uri;
        bool initialized;
    }
    function initializeListing(address creatorContractAddress, bytes32 merkleRoot, string calldata uri) external;
    function getListing(address creatorContractAddress) external returns(Listing memory);
    function mint(address creatorContractAddress, bytes32[] calldata merkleProof) external;
}
