// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

/**
 * Lazy Claim interface
 */
interface IERC721LazyClaim {
    enum StorageProtocol { ARWEAVE, IPFS }

    struct Claim {
        uint32 total;
        uint32 totalMax;
        uint32 walletMax;
        uint48 startDate;
        uint48 endDate;
        StorageProtocol storageProtocol;
        bool identical;
        bytes32 merkleRoot;
        string uri;
    }
    function initializeClaim(address creatorContractAddress, bytes32 merkleRoot, string calldata uri, uint32 totalMax, uint32 walletMax, uint48 startDate, uint48 endDate, StorageProtocol storageProtocol, bool identical) external;
    function overwriteClaim(address creatorContractAddress, uint index, bytes32 merkleRoot, string calldata uri, uint32 totalMax, uint32 walletMax, uint48 startDate, uint48 endDate, StorageProtocol storageProtocol, bool identical) external;

    function getClaimCount(address creatorContractAddress) external view returns(uint);
    function getClaim(address creatorContractAddress, uint index) external view returns(Claim memory);
    function getWalletMinted(address creatorContractAddress, uint index) external view returns(uint32);

    function mint(address creatorContractAddress, uint index, bytes32[] calldata merkleProof, uint32 minterValue) external;
}
