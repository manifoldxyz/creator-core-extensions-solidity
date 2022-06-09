// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

/**
 * Lazy Claim interface
 */
interface IERC721LazyClaim {
    enum StorageProtocol { NONE, ARWEAVE, IPFS }

    struct ClaimParameters {
        uint32 totalMax;
        uint32 walletMax;
        uint48 startDate;
        uint48 endDate;
        StorageProtocol storageProtocol;
        bool identical;
        bytes32 merkleRoot;
        string location;
    }

    struct Claim {
        uint32 total;
        uint32 totalMax;
        uint32 walletMax;
        uint48 startDate;
        uint48 endDate;
        StorageProtocol storageProtocol;
        bool identical;
        bytes32 merkleRoot;
        string location;
    }
    function initializeClaim(address creatorContractAddress, ClaimParameters calldata claimParameters) external returns(uint);
    function overwriteClaim(address creatorContractAddress, uint index, ClaimParameters calldata claimParameters) external;

    function getClaimCount(address creatorContractAddress) external view returns(uint);
    function getClaim(address creatorContractAddress, uint index) external view returns(Claim memory);
    function getWalletMinted(address creatorContractAddress, uint index) external view returns(uint32);
    function getTokenClaim(address creatorContractAddress, uint tokenId) external view returns(uint);

    function mint(address creatorContractAddress, uint index, bytes32[] calldata merkleProof, uint32 minterValue) external returns(uint256);
}
