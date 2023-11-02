// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

/**
 * SuperLike interface
 */
interface ISuperLikeExtension {
    enum StorageProtocol { INVALID, NONE, ARWEAVE, IPFS }

    event SuperLikeInitialized(address indexed creatorContract, uint256 indexed instanceId, address editionAddress, address initializer);
    event SuperLikeUpdated(address indexed creatorContract, uint256 indexed instanceId);
    event SuperLike(address indexed creatorContract, uint256 indexed instanceId, address superLiker, uint96 count);
    event SuperLikeProxy(address indexed creatorContract, uint256 indexed instanceId, address superLiker, uint96 count, address caller);

    struct SuperLikeParameters {
        StorageProtocol storageProtocol;
        string location;
        address payable paymentReceiver;
    }

    struct SuperLikeInstance {
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
     * @param creatorContractAddress    the erc721 creator contract the SuperLike proof will mint on
     * @param editionAddress            the erc1155 creator contract where soulbound tokens will mint on
     * @param instanceId                the SuperLike instanceId for the creator contract
     * @param parameters                the parameters which will affect the behavior of the SuperLike
     */
    function initializeSuperLike(address creatorContractAddress, address editionAddress, uint256 instanceId, SuperLikeParameters calldata parameters) external;

    /**
     * @notice update a superlike
     * @param creatorContractAddress    the erc721 creator contract the SuperLike proof will mint on
     * @param instanceId                the SuperLike instanceId for the creator contract
     * @param parameters                the parameters which will affect the behavior of the SuperLike
     */
    function updateSuperLike(address creatorContractAddress, uint256 instanceId, SuperLikeParameters calldata parameters) external;

    /**
     * @notice Withdraw funds
     */
    function withdraw(address payable receiver, uint256 amount) external;

    /**
     * @notice Set the Manifold Membership address
     */
    function setMembershipAddress(address membershipAddress) external;

    /**
     * @notice Mint a SuperLike
     *
     * @param creatorContractAddress    the address of the creator contract for the claim
     * @param instanceId                the SuperLike instanceId for the creator contract
     * @param count                     the number of times to SuperLike
     */
    function mint(address creatorContractAddress, uint256 instanceId, uint96 count) external payable;

    /**
     * @notice Mint a SuperLike by Proxy
     *
     * @param creatorContractAddress    the address of the creator contract for the claim
     * @param instanceId                the SuperLike instanceId for the creator contract
     * @param count                     the number of times to SuperLike
     * @param mintFor                   the address to mint the SuperLike for
     */
    function mintProxy(address creatorContractAddress, uint256 instanceId, uint96 count, address mintFor) external payable;

    /**
     * @notice Get the superLike count for a claim
     *
     * @param creatorContractAddress    the address of the creator contract for the claim
     * @param instanceId                the claim instanceId for the creator contract
     * @return                          the SuperLike instance
     */
    function getSuperLike(address creatorContractAddress, uint256 instanceId) external view returns(SuperLikeInstance memory);

    /**
     * @notice extend tokenURI parameters for an existing SuperLike at instanceId.  Must have NONE StorageProtocol
     * @param creatorContractAddress    the creator contract corresponding to the claim
     * @param instanceId                the claim instanceId for the creator contract
     * @param locationChunk             the additional location chunk
     */
    function extendTokenURI(address creatorContractAddress, uint256 instanceId, string calldata locationChunk) external;

}