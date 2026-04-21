// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

/// @author: manifold.xyz

import {AllowListData, MultiConfigureStruct, PublicDrop, StorageProtocol} from "./SeaDropStructs.sol";

/**
 * @notice External ABI for ManifoldERC1155SeaDropShim — the SeaDrop-facing
 *         shim that fronts a single Manifold Creator Core ERC1155 drop.
 * @dev Consumers (scripts, tests, off-chain indexers) depend on this stable
 *      surface rather than the concrete contract so admin, mint, and view
 *      entrypoints stay in one place. Types are re-exported via SeaDropStructs
 *      so this file never duplicates struct definitions.
 *
 *      Auth boundaries, re-stated here for readers:
 *        - admin setters are gated by AdminControl.creatorAdminRequired on
 *          the immutable creator contract address the shim binds to;
 *        - mintSeaDrop is gated by the shim-local allowed-SeaDrop set;
 *        - owner() / getAllowedSeaDrop() / metadata views are unauthenticated.
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

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------

    /// @notice Emitted exactly once, from initialize(), after the Creator
    ///         Core tokenId is seeded and before config is applied.
    event Initialized(uint256 indexed instanceId, uint256 indexed tokenId);

    /// @notice Emitted after _applyConfig finishes — from both initialize()
    ///         and multiConfigure().
    event Configured(uint256 indexed instanceId, uint256 indexed tokenId);

    /// @notice OpenSea collection metadata changed.
    event ContractURIUpdated();

    /// @notice tokenURI storage protocol or location changed.
    event TokenURIUpdated();

    /// @notice _maxSupply updated (possibly clamped to _totalMinted).
    event MaxSupplyUpdated(uint256 newMaxSupply);

    /// @notice _maxMintsPerWallet updated.
    event MaxMintsPerWalletUpdated(uint256 newMax);

    /// @notice _allowedSeaDrop set replaced with the given addresses.
    event AllowedSeaDropUpdated(address[] allowed);

    /// @notice Emitted after every successful mintSeaDrop call.
    event SeaDropMint(address indexed minter, uint256 quantity);

    // -----------------------------------------------------------------------
    // Lifecycle
    // -----------------------------------------------------------------------

    /**
     * @notice One-shot initializer. Seeds the Creator Core tokenId via
     *         mintExtensionNew(amount=0) and applies the full drop config
     *         in a single admin transaction.
     * @dev Gated by creatorAdminRequired. Reverts with AlreadyInitialized if
     *      called a second time. Requires the shim to already be registered
     *      as an extension on the creator contract.
     */
    function initialize(MultiConfigureStruct calldata cfg) external;

    /**
     * @notice Post-init reconfigure path. Re-applies the same internal
     *         _applyConfig initialize uses, so runs are idempotent.
     * @dev Gated by creatorAdminRequired. Reverts with NotInitialized before
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

    function setMaxMintsPerWallet(uint256 newMax) external;

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

    function owner() external view returns (address);
}
