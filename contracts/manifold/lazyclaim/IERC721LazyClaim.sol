// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

/**
 * Lazy Claim interface
 */
interface IERC721LazyClaim {
    enum StorageProtocol { INVALID, NONE, ARWEAVE, IPFS }

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

    event ClaimInitialized(address indexed creatorContract, uint256 indexed claimIndex, address initializer);
    event Mint(address indexed creatorContract, uint256 indexed claimIndex, uint256 tokenId, address claimer);

    function initializeClaim(address creatorContractAddress, ClaimParameters calldata claimParameters) external returns(uint256);
    function updateClaim(address creatorContractAddress, uint256 claimIndex, ClaimParameters calldata claimParameters) external;

    function getClaimCount(address creatorContractAddress) external view returns(uint256);
    function getClaim(address creatorContractAddress, uint256 claimIndex) external view returns(Claim memory);
    function canMint(address creatorContractAddress, uint256 claimIndex, uint32 mintIndex) external view returns(bool);

    function mint(address creatorContractAddress, uint256 claimIndex, uint32 mintIndex, bytes32[] calldata merkleProof) external returns(uint256);
}
