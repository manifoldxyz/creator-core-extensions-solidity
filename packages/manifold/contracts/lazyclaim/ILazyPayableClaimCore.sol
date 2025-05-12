// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

/**
 * Lazy Payable Claim interface
 */
interface ILazyPayableClaimCore {
    error InvalidStorageProtocol();
    error ClaimNotInitialized();
    error InvalidStartDate();
    error InvalidAirdrop();
    error TokenDNE();
    error InvalidInstance();
    error InvalidInput();
    error ClaimInactive();
    error TooManyRequested();
    error MustUseSignatureMinting();
    error FailedToTransfer();
    error InvalidSignature();
    error ExpiredSignature();
    error CannotChangePaymentToken();

    enum StorageProtocol {
        INVALID,
        NONE,
        ARWEAVE,
        IPFS,
        ADDRESS
    }

    event ClaimInitialized(address indexed creatorContract, uint256 indexed instanceId, address initializer);
    event ClaimUpdated(address indexed creatorContract, uint256 indexed instanceId);
    event ClaimMint(address indexed creatorContract, uint256 indexed instanceId);
    event ClaimMintBatch(address indexed creatorContract, uint256 indexed instanceId, uint16 mintCount);
    event ClaimMintProxy(
        address indexed creatorContract, uint256 indexed instanceId, uint16 mintCount, address proxy, address mintFor
    );
    event ClaimMintSignature(
        address indexed creatorContract,
        uint256 indexed instanceId,
        uint16 mintCount,
        address proxy,
        address mintFor,
        bytes32 nonce
    );

    /**
     * @notice Withdraw funds
     */
    function withdraw(address payable receiver, uint256 amount) external;

    /**
     * @notice Set the Manifold Membership address
     */
    function setMembershipAddress(address membershipAddress) external;

    /**
     * @notice check if a mint index has been consumed or not (only for merkle claims)
     *
     * @param creatorContractAddress    the address of the creator contract for the claim
     * @param instanceId                the claim instanceId for the creator contract
     * @param mintIndex                 the mint claim instance
     * @return                          whether or not the mint index was consumed
     */
    function checkMintIndex(address creatorContractAddress, uint256 instanceId, uint32 mintIndex)
        external
        view
        returns (bool);

    /**
     * @notice check if multiple mint indices has been consumed or not (only for merkle claims)
     *
     * @param creatorContractAddress    the address of the creator contract for the claim
     * @param instanceId                the claim instanceId for the creator contract
     * @param mintIndices               the mint claim instance
     * @return                          whether or not the mint index was consumed
     */
    function checkMintIndices(address creatorContractAddress, uint256 instanceId, uint32[] calldata mintIndices)
        external
        view
        returns (bool[] memory);

    /**
     * @notice get mints made for a wallet (only for non-merkle claims with walletMax)
     *
     * @param minter                    the address of the minting address
     * @param creatorContractAddress    the address of the creator contract for the claim
     * @param instanceId                the claim instance for the creator contract
     * @return                          how many mints the minter has made
     */
    function getTotalMints(address minter, address creatorContractAddress, uint256 instanceId)
        external
        view
        returns (uint32);
}
