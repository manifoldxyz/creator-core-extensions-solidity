// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

/**
 * Gacha Lazy Claim interface
 */
interface IGachaLazyClaim {
    enum StorageProtocol { INVALID, NONE, ARWEAVE, IPFS }

    error InvalidSignature();
    error FailedToTransfer();
    error InsufficientPayment();
    error PaymentNotAllowed();

    event GachaClaimInitialized(address indexed creatorContract, uint256 indexed instanceId, address initializer);
    // mvp: Gacha claims cannot be updated except for price
    event GachaClaimUpdated(address indexed creatorContract, uint256 indexed instanceId);
    event GachaClaimMintReserved(address indexed creatorContract, uint256 indexed instanceId, address indexed collector, uint256 amount);
    event GachaClaimMintDelivered(address indexed creatorContract, uint256 indexed instanceId, address indexed collector, uint32 itemIndex, uint256 amount);
    // nice to have:
    // event GachaMintBatch(address indexed creatorContract, uint256 indexed instanceId, uint16 mintCount);

    struct Recipient {
        address receiver;
        uint256 amount;
        uint256 payment;
        uint32 itemIndex;
    }

    struct Mint {
        address creatorContractAddress;
        uint256 instanceId;
        Recipient[] recipients;
    }
        
    struct ItemProbability {
        uint32 itemIndex; // this is also the same as arweave index
        uint16 rate; // given in basis pts
        string tier;
    }

    struct ClaimParameters {
        uint32 totalMax;
        uint48 startDate;
        uint48 endDate;
        StorageProtocol storageProtocol;
        string location;
        address payable paymentReceiver;
        address erc20;
        uint256 cost;
        uint256 startingTokenId;
        ItemProbability[] itemProbabilities;
    }

    /**
     * @notice Set the signing address
     * @param signer    the signer address
     */
    function setSigner(address signer) external;

    /**
     * @notice Withdraw funds
     */
    function withdraw(address payable receiver, uint256 amount) external;

    /**
     * @notice minting request
     * @param creatorContractAddress    the creator contract address
     * @param instanceId                the claim instanceId for the creator contract
     */
    function mintReserve(address creatorContractAddress, uint256 instanceId) external payable;

    /**
     * @notice minting request
     * @param creatorContractAddress    the creator contract address
     * @param instanceId                the claim instanceId for the creator contract
     * @param mintCount                 the number of claims to mint
     */
    function mintReserveBatch(address creatorContractAddress, uint256 instanceId, uint16 mintCount) external payable;

    /**
     * @notice Deliver NFTs
     */
    function deliverMints(Mint[] calldata mints) external;

    /**
     * @notice get mints made for a wallet
     *
     * @param minter                    the address of the minting address
     * @param creatorContractAddress    the address of the creator contract for the claim
     * @param instanceId                the claim instance for the creator contract
     * @return                          how many mints the minter has made
     */
    function getTotalMints(address minter, address creatorContractAddress, uint256 instanceId) external view returns(uint32);

}