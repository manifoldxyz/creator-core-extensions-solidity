// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

/**
 * Lazy Claim interface
 */
interface IERC721LazyClaim {
    struct Claim {
        bytes32 merkleRoot;
        string uri;
        uint totalMax;
        uint walletMax;
        uint startDate;
        uint endDate;
    }
    function initializeClaim(address creatorContractAddress, bytes32 merkleRoot, string calldata uri, uint totalMax, uint walletMax, uint startDate, uint endDate) external;

    function overwriteClaim(address creatorContractAddress, uint index, bytes32 merkleRoot, string calldata uri, uint totalMax, uint walletMax, uint startDate, uint endDate) external;
    function setMerkleRoot(address creatorContractAddress, uint index, bytes32 merkleRoot) external;
    function setURI(address creatorContractAddress, uint index, string calldata uri) external;
    function setTotalMax(address creatorContractAddress, uint index, uint totalMax) external;
    function setWalletMax(address creatorContractAddress, uint index, uint walletMax) external;
    function setStartDate(address creatorContractAddress, uint index, uint startDate) external;
    function setEndDate(address creatorContractAddress, uint index, uint endDate) external;

    function getClaimCount(address creatorContractAddress) external view returns(uint);
    function getClaim(address creatorContractAddress, uint index) external view returns(Claim memory);

    function mint(address creatorContractAddress, uint index, bytes32[] calldata merkleProof) external;
}
