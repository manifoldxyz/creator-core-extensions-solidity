// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

/// @author: manifold.xyz

import {
    AllowListData,
    MultiConfigureStruct,
    PublicDrop,
    SignedMintValidationParams,
    StorageProtocol,
    TokenGatedDropStage
} from "./SeaDropStructs.sol";

/**
 * @notice External ABI for ManifoldERC1155SeaDropShim — the SeaDrop-facing
 *         shim that fronts a single Manifold Creator Core ERC1155 drop.
 * @dev Consumers (scripts, tests, off-chain indexers) depend on this stable
 *      surface rather than the concrete contract so admin, mint, and view
 *      entrypoints stay in one place. Types are re-exported via SeaDropStructs
 *      so this file never duplicates struct definitions.
 *
 *      Auth boundaries, re-stated here for readers:
 *        - admin setters are gated by `creatorAdminRequired` against the
 *          bound Creator Core's AdminControl — only wallets flagged as
 *          admins on the creator contract can reconfigure the drop;
 *        - multiConfigure / initialize share an internal `_applyConfig`
 *          helper that calls internal `_setX` / `_updateX` helpers directly
 *          (no `this.` self-calls), so the admin surface is NOT widened to
 *          `address(this)`;
 *        - mintSeaDrop is gated by the shim-local allowed-SeaDrop set;
 *        - getAllowedSeaDrop() / metadata views are unauthenticated.
 *
 *      The ICreatorExtensionTokenURI `tokenURI(address,uint256)` overload and
 *      IERC165 `supportsInterface` come from their respective standard
 *      interfaces and are intentionally not redeclared here.
 */
interface IManifoldERC1155SeaDropShim {
    // -----------------------------------------------------------------------
    // Errors
    // -----------------------------------------------------------------------

    /// @dev Reverts from initialize() when the drop has already been seeded.
    error AlreadyInitialized();

    /// @dev Reverts from mintSeaDrop / multiConfigure when _tokenId == 0.
    error NotInitialized();

    /// @dev Reverts from mintSeaDrop when msg.sender is not in the shim's
    ///      allowed-SeaDrop set.
    error OnlyAllowedSeaDrop();

    /// @dev Reserved for supply-cap violations surfaced by the shim itself.
    ///      Day-to-day cap enforcement happens inside SeaDrop via getMintStats.
    error ExceedsMaxSupply();

    /// @dev tokenURI lookups fail when the queried tokenId (or creator, for
    ///      the Creator Core overload) does not match the shim's single drop.
    error TokenDNE();

    /// @dev Rejects StorageProtocol.INVALID, or extendTokenURI on a protocol
    ///      that is not NONE.
    error InvalidStorageProtocol();

    /// @dev Reverts from _applyConfig when a paired `{values, disallowed}` set
    ///      of arrays (tokenGated, signedMint) has mismatched lengths between
    ///      the two halves of the configure pair.
    error MismatchedArrayLengths();

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------

    /// @notice Emitted at the end of the shim constructor — mirrors the stock
    ///         ERC721SeaDrop `SeaDropTokenDeployed` signal so indexers can
    ///         detect a new Manifold x SeaDrop shim deployment without
    ///         scanning Creator Core's registerExtension events.
    event ManifoldSeaDropTokenDeployed();

    /// @notice Emitted exactly once, from initialize(), after _applyConfig has
    ///         pushed the full drop config. Carries the correlation pair that
    ///         indexers key off to associate the shim with a Studio drop.
    event Initialized(uint256 indexed instanceId, uint256 indexed tokenId);

    /// @notice OpenSea collection metadata changed. Signature mirrors
    ///         ISeaDropTokenContractMetadata.ContractURIUpdated so SeaDrop /
    ///         OpenSea indexers can match on the canonical topic0 hash.
    event ContractURIUpdated(string newContractURI);

    /// @notice tokenURI storage protocol or location changed. Shim-specific
    ///         — retained for on-chain diagnostics; OpenSea refreshes via
    ///         the EIP-4906 BatchMetadataUpdate event emitted alongside.
    event TokenURIUpdated();

    /// @notice EIP-4906 metadata refresh signal for the drop's tokenId.
    ///         Emitted whenever the stored tokenURI changes so OpenSea and
    ///         other marketplaces invalidate their metadata cache.
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);

    /// @notice _maxSupply updated.
    event MaxSupplyUpdated(uint256 newMaxSupply);

    /// @notice _allowedSeaDrop set replaced with the given addresses.
    event AllowedSeaDropUpdated(address[] allowed);

    /// @notice Emitted after every successful mintSeaDrop call.
    event SeaDropMint(address indexed minter, uint256 quantity);

    // -----------------------------------------------------------------------
    // Lifecycle
    // -----------------------------------------------------------------------

    /**
     * @notice One-shot initializer. Seeds the Creator Core tokenId via
     *         mintExtensionNew(amount=0) then applies the full drop config
     *         through the shared `_applyConfig` helper.
     * @dev Gated by creatorAdminRequired. Reverts with AlreadyInitialized if
     *      called a second time. Requires the shim to already be registered
     *      as an extension on the creator contract. Because `_applyConfig`
     *      skips zero-value fields, admins must pass a complete cfg on the
     *      first call — matching stock SeaDrop semantics.
     */
    function initialize(MultiConfigureStruct calldata cfg) external;

    /**
     * @notice Configure multiple properties at a time.
     * @dev Zero-value / empty-array fields are ignored — admins use the
     *      individual external setters to unset or reset a property to zero.
     *      Each populated field dispatches to an internal `_setX` / `_updateX`
     *      helper so bounds checks + per-field events run consistently across
     *      direct admin calls and batch reconfigures. Gated by
     *      creatorAdminRequired. Reverts with NotInitialized before
     *      initialize() has been called.
     */
    function multiConfigure(MultiConfigureStruct calldata cfg) external;

    // -----------------------------------------------------------------------
    // SeaDrop surface
    // -----------------------------------------------------------------------

    /**
     * @notice Mint entry invoked by an allowed SeaDrop on behalf of a
     *         collector. Increments local counters before delegating to
     *         Creator Core's mintExtensionExisting for actual ERC1155 mint.
     */
    function mintSeaDrop(address minter, uint256 quantity) external;

    /**
     * @notice Tuple SeaDrop reads to enforce per-wallet + drop-wide caps.
     * @return minterNumMinted   cumulative mints by `minter` across phases
     * @return currentTotalSupply cumulative mints on this drop
     * @return maxSupply          admin-configured cap
     */
    function getMintStats(address minter)
        external
        view
        returns (uint256 minterNumMinted, uint256 currentTotalSupply, uint256 maxSupply);

    // -----------------------------------------------------------------------
    // Local admin setters (caps + metadata)
    // -----------------------------------------------------------------------

    function setMaxSupply(uint256 newMaxSupply) external;

    function setContractURI(string calldata newContractURI) external;

    function updateTokenURI(StorageProtocol storageProtocol, string calldata location) external;

    function extendTokenURI(string calldata chunk) external;

    function updateAllowedSeaDrop(address[] calldata newAllowed) external;

    // -----------------------------------------------------------------------
    // SeaDrop pass-through setters
    // -----------------------------------------------------------------------

    function updatePublicDrop(address seaDropImpl, PublicDrop calldata publicDrop) external;

    function updateAllowList(address seaDropImpl, AllowListData calldata allowListData) external;

    function updateCreatorPayoutAddress(address seaDropImpl, address payoutAddress) external;

    function updateAllowedFeeRecipient(address seaDropImpl, address feeRecipient, bool allowed) external;

    function updateDropURI(address seaDropImpl, string calldata dropURI) external;

    function updatePayer(address seaDropImpl, address payer, bool allowed) external;

    function updateTokenGatedDrop(
        address seaDropImpl,
        address allowedNftToken,
        TokenGatedDropStage calldata dropStage
    ) external;

    function updateSignedMintValidationParams(
        address seaDropImpl,
        address signer,
        SignedMintValidationParams calldata signedMintValidationParams
    ) external;

    // -----------------------------------------------------------------------
    // Views
    // -----------------------------------------------------------------------

    function maxSupply() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function contractURI() external view returns (string memory);

    function tokenURI(uint256 tokenId) external view returns (string memory);

    function baseURI() external view returns (string memory);

    function provenanceHash() external view returns (bytes32);

    function getAllowedSeaDrop() external view returns (address[] memory);
}
