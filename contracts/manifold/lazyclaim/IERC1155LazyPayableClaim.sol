// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "./IERC721LazyPayableClaim.sol";

/**
 * Lazy Claim interface
 */
interface IERC1155LazyPayableClaim is ILazyPayableClaim {

    struct ClaimParameters {
        uint32 totalMax;
        uint32 walletMax;
        uint48 startDate;
        uint48 endDate;
        StorageProtocol storageProtocol;
        bytes32 merkleRoot;
        string location;
        uint256 cost;
        address payable paymentReceiver;
    }

    struct Claim {
        uint32 total;
        uint32 totalMax;
        uint32 walletMax;
        uint48 startDate;
        uint48 endDate;
        StorageProtocol storageProtocol;
        bytes32 merkleRoot;
        string location;
        uint256 tokenId;
        uint256 cost;
        address payable paymentReceiver;
    }

    /**
     * @notice initialize a new claim, emit initialize event, and return the newly created index
     * @param creatorContractAddress    the creator contract the claim will mint tokens for
     * @param claimIndex                the index of the claim in the list of creatorContractAddress' _claims
     * @param claimParameters           the parameters which will affect the minting behavior of the claim
     */
    function initializeClaim(address creatorContractAddress, uint256 claimIndex, ClaimParameters calldata claimParameters) external;

    /**
     * @notice update an existing claim at claimIndex
     * @param creatorContractAddress    the creator contract corresponding to the claim
     * @param claimIndex                the index of the claim in the list of creatorContractAddress' _claims
     * @param claimParameters           the parameters which will affect the minting behavior of the claim
     */
    function updateClaim(address creatorContractAddress, uint256 claimIndex, ClaimParameters calldata claimParameters) external;

    /**
     * @notice update tokenURI parameters for an existing claim at claimIndex
     * @param creatorContractAddress    the creator contract corresponding to the claim
     * @param claimIndex                the index of the claim in the list of creatorContractAddress' _claims
     * @param storageProtocol           the new storage protocol
     * @param location                  the new location
     */
    function updateTokenURIParams(address creatorContractAddress, uint256 claimIndex, StorageProtocol storageProtocol, string calldata location) external;

    /**
     * @notice get a claim corresponding to a creator contract and index
     * @param creatorContractAddress    the address of the creator contract
     * @param claimIndex                the index of the claim
     * @return                          the claim object
     */
    function getClaim(address creatorContractAddress, uint256 claimIndex) external view returns(Claim memory);

    /**
     * @notice allow admin to airdrop arbitrary tokens 
     * @param creatorContractAddress    the creator contract the claim will mint tokens for
     * @param claimIndex                the index of the claim in the list of creatorContractAddress' _claims
     * @param recipients                addresses to airdrop to
     * @param amounts                   number of tokens to airdrop to each address in addresses
     */
    function airdrop(address creatorContractAddress, uint256 claimIndex, address[] calldata recipients, uint256[] calldata amounts) external;
}
