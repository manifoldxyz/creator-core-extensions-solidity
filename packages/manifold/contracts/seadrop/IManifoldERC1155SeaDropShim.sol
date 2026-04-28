// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

/// @author: manifold.xyz

import {MultiConfigureStruct, StorageProtocol} from "./SeaDropStructs.sol";

/**
 * @notice Shim-specific external surface for ManifoldERC1155SeaDropShim.
 * @dev The shim contract additionally inherits INonFungibleSeaDropToken
 *      (and its parent ISeaDropTokenContractMetadata) — every selector
 *      declared on those upstream interfaces is therefore implemented and
 *      enforced at compile time. This file declares ONLY the entries that
 *      are unique to the shim: lifecycle (initialize / multiConfigure),
 *      Manifold StorageProtocol-flavored URI setters, and the local-only
 *      views (totalSupply, getAllowedSeaDrop, tokenURI(uint256)).
 *
 *      Auth: every admin entry is gated by `creatorAdminRequired` against
 *      the bound Creator Core's AdminControl. mintSeaDrop is gated by the
 *      shim-local allowed-SeaDrop set.
 */
interface IManifoldERC1155SeaDropShim {
    // -----------------------------------------------------------------------
    // Errors
    // -----------------------------------------------------------------------

    /// @dev Reverts from initialize() when the drop has already been seeded.
    error AlreadyInitialized();

    /// @dev Reverts from mintSeaDrop / multiConfigure when _tokenId == 0.
    error NotInitialized();

    /// @dev Reserved for supply-cap violations surfaced by the shim itself.
    ///      Day-to-day cap enforcement happens inside SeaDrop via getMintStats.
    error ExceedsMaxSupply();

    /// @dev tokenURI lookups fail when the queried tokenId (or creator, for
    ///      the Creator Core overload) does not match the shim's single drop.
    error TokenDNE();

    /// @dev Rejects StorageProtocol.INVALID, or extendTokenURI on a protocol
    ///      that is not NONE.
    error InvalidStorageProtocol();

    /// @dev Reverts from _applyConfig when cfg.tokenGatedDropStages.length
    ///      != cfg.tokenGatedAllowedNftTokens.length.
    error TokenGatedMismatch();

    /// @dev Reverts from _applyConfig when cfg.signedMintValidationParams.length
    ///      != cfg.signers.length.
    error SignersMismatch();

    /// @dev Reverts from setMaxSupply when newMaxSupply > 2**64 - 1.
    error CannotExceedMaxSupplyOfUint64(uint256 newMaxSupply);

    /// @dev Reverts from setMaxSupply when newMaxSupply < _totalMinted.
    error NewMaxSupplyCannotBeLessThenTotalMinted(uint256 got, uint256 totalMinted);

    /// @dev Reverts from setProvenanceHash. The shim implements the canonical
    ///      INonFungibleSeaDropToken / ISeaDropTokenContractMetadata signature
    ///      for compile-time interface compliance, but provenance reveals are a
    ///      v1 non-goal — calls always revert with this error rather than
    ///      silently no-op'ing (so admin tooling fails loudly).
    error ProvenanceHashNotSupported();

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------

    /// @notice Emitted at the end of the shim constructor — mirrors stock
    ///         ERC721SeaDrop's SeaDropTokenDeployed signal so off-chain
    ///         indexers can detect a new shim deployment without scanning
    ///         Creator Core's registerExtension event stream.
    event ManifoldSeaDropTokenDeployed();

    /// @notice Emitted exactly once, from initialize(), after _applyConfig has
    ///         pushed the full drop config. Carries the correlation pair that
    ///         indexers key off to associate the shim with a Studio drop.
    event Initialized(uint256 indexed instanceId, uint256 indexed tokenId);

    // -----------------------------------------------------------------------
    // Lifecycle
    // -----------------------------------------------------------------------

    /**
     * @notice One-shot initializer. Seeds the Creator Core tokenId via
     *         mintExtensionNew(amount=0) then applies the full drop config
     *         through the shared `_applyConfig` helper.
     */
    function initialize(MultiConfigureStruct calldata cfg) external;

    /**
     * @notice Configure multiple properties at a time. Zero-value /
     *         empty-array fields are ignored.
     */
    function multiConfigure(MultiConfigureStruct calldata cfg) external;

    // -----------------------------------------------------------------------
    // Shim-local URI setters (Manifold StorageProtocol-flavored)
    // -----------------------------------------------------------------------

    /// @notice Replace the storage protocol + URI location atomically.
    function updateTokenURI(StorageProtocol storageProtocol, string calldata location) external;

    /// @notice Append a chunk to the URI location (only valid when
    ///         storageProtocol == NONE; ARWEAVE/IPFS locations are opaque).
    function extendTokenURI(string calldata chunk) external;

    // -----------------------------------------------------------------------
    // Shim-local views
    // -----------------------------------------------------------------------

    /// @notice Drop-wide cumulative mints. Mirrors getMintStats.currentTotalSupply.
    function totalSupply() external view returns (uint256);

    /// @notice Bare-tokenId tokenURI overload. Returns the same assembled URI
    ///         as the ICreatorExtensionTokenURI overload routed via Creator Core.
    function tokenURI(uint256 tokenId) external view returns (string memory);

    /// @notice The set of SeaDrop deployments authorized to call mintSeaDrop.
    function getAllowedSeaDrop() external view returns (address[] memory);
}
