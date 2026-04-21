// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

/// @author: manifold.xyz

/**
 * @notice Storage protocol used to resolve the tokenURI.
 * @dev Matches the ERC1155LazyPayableClaimCore storage-protocol pattern.
 *      INVALID is the default zero-value and is used as an "unset" sentinel.
 */
enum StorageProtocol {
    INVALID,
    NONE,
    ARWEAVE,
    IPFS
}

/**
 * @notice PublicDrop as consumed by stock SeaDrop v1
 *         (0x00005EA00Ac477B1030CE78506496e8C2dE24bf5).
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
 */
struct MultiConfigureStruct {
    uint256 maxSupply;
    uint256 maxMintsPerWallet;
    string tokenUriLocation;
    StorageProtocol storageProtocol;
    string contractURI;
    address seaDropImpl;
    PublicDrop publicDrop;
    AllowListData allowListData;
    address creatorPayoutAddress;
    address[] allowedFeeRecipients;
}
