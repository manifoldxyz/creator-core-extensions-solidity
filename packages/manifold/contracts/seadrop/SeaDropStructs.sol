// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

/// @author: manifold.xyz

/**
 * @notice Storage protocol used to resolve the tokenURI.
 * @dev INVALID is the default zero-value and is used as an "unset" sentinel.
 */
enum StorageProtocol {
    INVALID,
    NONE,
    ARWEAVE,
    IPFS
}

/**
 * @notice PublicDrop as consumed by stock SeaDrop v1
 * @dev Field order and packed sizes mirror the deployed SeaDrop ABI so that
 *      forwarding setters on the shim can pass the struct by value without
 *      re-encoding. Keep in sync with ISeaDrop.updatePublicDrop.
 */
struct PublicDrop {
    uint80 mintPrice;
    uint48 startTime;
    uint48 endTime;
    uint16 maxTotalMintableByWallet;
    uint16 feeBps;
    bool restrictFeeRecipients;
}

/**
 * @notice Allowlist configuration SeaDrop stores for the calling nft contract.
 * @dev publicKeyURIs / allowListURI are encrypted-list pointers surfaced to
 *      collectors pre-reveal; the shim does not interpret them.
 */
struct AllowListData {
    bytes32 merkleRoot;
    string[] publicKeyURIs;
    string allowListURI;
}

/**
 * @notice Full drop configuration accepted by ManifoldERC1155SeaDropShim
 *         initialize() and multiConfigure().
 * @dev Groups every value the shim needs to apply local caps + metadata and to
 *      forward the stock SeaDrop setters in a single admin transaction.
 *      seaDropImpl is the SeaDrop deployment to configure (must also be in the
 *      shim's allowed-SeaDrop set for mintSeaDrop to accept its calls).
 *      The Manifold drop instanceId is bound at deploy time as a constructor
 *      immutable on the shim — it is NOT part of this struct.
 *
 *      multiConfigure ignores zero-value / empty-array fields — callers use
 *      the individual external setters to unset or reset a property to zero.
 *      Paired `allowed*` / `disallowed*` arrays let a single reconfigure
 *      transaction drain an old recipient/payer set and install a new one,
 *      mirroring the stock SeaDrop MultiConfigureStruct semantics.
 */
struct MultiConfigureStruct {
    uint256 maxSupply;
    string tokenUriLocation;
    StorageProtocol storageProtocol;
    string contractURI;
    address seaDropImpl;
    PublicDrop publicDrop;
    string dropURI;
    AllowListData allowListData;
    address creatorPayoutAddress;
    address[] allowedFeeRecipients;
    address[] disallowedFeeRecipients;
    address[] allowedPayers;
    address[] disallowedPayers;

    // Token-gated drops: tokenGatedAllowedNftTokens[i] is configured with
    // tokenGatedDropStages[i] (arrays must have the same length). Entries in
    // disallowedTokenGatedAllowedNftTokens are drained by forwarding a zero
    // TokenGatedDropStage — matching stock SeaDrop's remove-via-zero semantics.
    address[] tokenGatedAllowedNftTokens;
    TokenGatedDropStage[] tokenGatedDropStages;
    address[] disallowedTokenGatedAllowedNftTokens;

    // Signed mints: signers[i] is configured with signedMintValidationParams[i]
    // (arrays must have the same length). Entries in disallowedSigners are
    // drained by forwarding a zero SignedMintValidationParams.
    address[] signers;
    SignedMintValidationParams[] signedMintValidationParams;
    address[] disallowedSigners;
}

/**
 * @notice TokenGatedDropStage as declared by stock SeaDrop v1.
 * @dev Used by the shim's `updateTokenGatedDrop` pass-through (and the paired
 *      MultiConfigureStruct arrays) and by INonFungibleSeaDropToken when
 *      Solidity computes its interfaceId. Field order and packing must mirror
 *      the canonical ProjectOpenSea/seadrop layout or the computed interfaceId
 *      will drift from the value SeaDrop callers and OpenSea expect.
 */
struct TokenGatedDropStage {
    uint80 mintPrice;
    uint16 maxTotalMintableByWallet;
    uint48 startTime;
    uint48 endTime;
    uint8 dropStageIndex;
    uint32 maxTokenSupplyForStage;
    uint16 feeBps;
    bool restrictFeeRecipients;
}

/**
 * @notice SignedMintValidationParams as declared by stock SeaDrop v1.
 * @dev Used by the shim's `updateSignedMintValidationParams` pass-through (and
 *      the paired MultiConfigureStruct arrays) and by INonFungibleSeaDropToken
 *      when Solidity computes its interfaceId. Field order and packing must
 *      mirror the canonical ProjectOpenSea/seadrop layout to keep the derived
 *      interfaceId in sync with the value SeaDrop and OpenSea expect.
 */
struct SignedMintValidationParams {
    uint80 minMintPrice;
    uint24 maxMaxTotalMintableByWallet;
    uint40 minStartTime;
    uint40 maxEndTime;
    uint40 maxMaxTokenSupplyForStage;
    uint16 minFeeBps;
    uint16 maxFeeBps;
}
