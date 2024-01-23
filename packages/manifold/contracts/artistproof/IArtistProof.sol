// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

/**
 * ArtistProof interface
 */
interface IArtistProofExtension {
    enum StorageProtocol { INVALID, NONE, ARWEAVE, IPFS }

    event ArtistProofInitialized(address indexed creatorContract, uint256 indexed instanceId, address editionAddress, address initializer);
    event ArtistProofUpdated(address indexed creatorContract, uint256 indexed instanceId);
    event ArtistProof(address indexed creatorContract, uint256 indexed instanceId, address artistProofr, uint96 count);
    event ArtistProofProxy(address indexed creatorContract, uint256 indexed instanceId, address artistProofr, uint96 count, address caller);

    struct ArtistProofParameters {
        StorageProtocol storageProtocol;
        string location;
        address payable paymentReceiver;
    }

    struct ArtistProofInstance {
        uint256 proofTokenId;
        uint256 editionTokenId;
        address editionAddress;
        StorageProtocol storageProtocol;
        string location;
        address payable paymentReceiver;
        uint96 editionCount;
    }


    /**
     * @notice initialize a new superlike, emit initialize event
     * @param creatorContractAddress    the erc721 creator contract the ArtistProof proof will mint on
     * @param editionAddress            the erc1155 creator contract where soulbound tokens will mint on
     * @param instanceId                the ArtistProof instanceId for the creator contract
     * @param parameters                the parameters which will affect the behavior of the ArtistProof
     */
    function initializeArtistProof(address creatorContractAddress, address editionAddress, uint256 instanceId, ArtistProofParameters calldata parameters) external;

    /**
     * @notice update a superlike
     * @param creatorContractAddress    the erc721 creator contract the ArtistProof proof will mint on
     * @param instanceId                the ArtistProof instanceId for the creator contract
     * @param parameters                the parameters which will affect the behavior of the ArtistProof
     */
    function updateArtistProof(address creatorContractAddress, uint256 instanceId, ArtistProofParameters calldata parameters) external;

    /**
     * @notice Withdraw funds
     */
    function withdraw(address payable receiver, uint256 amount) external;

    /**
     * @notice Set the Manifold Membership address
     */
    function setMembershipAddress(address membershipAddress) external;

    /**
     * @notice Mint a ArtistProof
     *
     * @param creatorContractAddress    the address of the creator contract for the claim
     * @param instanceId                the ArtistProof instanceId for the creator contract
     * @param count                     the number of times to ArtistProof
     */
    function mint(address creatorContractAddress, uint256 instanceId, uint96 count) external payable;

    /**
     * @notice Mint a ArtistProof by Proxy
     *
     * @param creatorContractAddress    the address of the creator contract for the claim
     * @param instanceId                the ArtistProof instanceId for the creator contract
     * @param count                     the number of times to ArtistProof
     * @param mintFor                   the address to mint the ArtistProof for
     */
    function mintProxy(address creatorContractAddress, uint256 instanceId, uint96 count, address mintFor) external payable;

    /**
     * @notice Get the artistProof count for a claim
     *
     * @param creatorContractAddress    the address of the creator contract for the claim
     * @param instanceId                the claim instanceId for the creator contract
     * @return                          the ArtistProof instance
     */
    function getArtistProof(address creatorContractAddress, uint256 instanceId) external view returns(ArtistProofInstance memory);

    /**
     * @notice extend tokenURI parameters for an existing ArtistProof at instanceId.  Must have NONE StorageProtocol
     * @param creatorContractAddress    the creator contract corresponding to the claim
     * @param instanceId                the claim instanceId for the creator contract
     * @param locationChunk             the additional location chunk
     */
    function extendTokenURI(address creatorContractAddress, uint256 instanceId, string calldata locationChunk) external;

}