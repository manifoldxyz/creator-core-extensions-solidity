// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

/// @author: manifold.xyz

import {AdminControl} from "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";
import {IAdminControl} from "@manifoldxyz/libraries-solidity/contracts/access/IAdminControl.sol";
import {ICreatorExtensionTokenURI} from "@manifoldxyz/creator-core-solidity/contracts/extensions/ICreatorExtensionTokenURI.sol";
import {IERC1155CreatorCore} from "@manifoldxyz/creator-core-solidity/contracts/core/IERC1155CreatorCore.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IManifoldERC1155SeaDropShim} from "./IManifoldERC1155SeaDropShim.sol";
import {ISeaDrop} from "./ISeaDrop.sol";
import {AllowListData, MultiConfigureStruct, PublicDrop, StorageProtocol} from "./SeaDropStructs.sol";

/**
 * @notice ManifoldERC1155SeaDropShim — SeaDrop-facing extension that fronts a
 *         single ERC1155 drop living on a Manifold Creator Core contract.
 * @dev One shim per drop. The (creatorContractAddress, instanceId) pair is
 *      immutable, and _tokenId becomes effectively immutable after the first
 *      initialize(). See specs/manifold-seadrop-shim-erc1155.md for the full
 *      architecture; this file is the scaffold for US-004 — storage +
 *      constructor are live, every external function reverts with
 *      NotImplemented until its own user story fills it in.
 */
contract ManifoldERC1155SeaDropShim is
    AdminControl,
    IManifoldERC1155SeaDropShim,
    ICreatorExtensionTokenURI,
    ReentrancyGuard
{
    using EnumerableSet for EnumerableSet.AddressSet;

    // -----------------------------------------------------------------------
    // Immutable binding (constructor)
    // -----------------------------------------------------------------------

    /// @notice The Manifold Creator Core contract this shim drops onto.
    address public immutable creatorContractAddress;

    /// @notice Manifold drop instanceId — emitted in lifecycle events so
    ///         indexers can correlate shims with Studio-side drop records.
    uint256 public immutable instanceId;

    // -----------------------------------------------------------------------
    // Mutable state (populated by subsequent stories)
    // -----------------------------------------------------------------------

    /// @dev Creator Core tokenId seeded by initialize() via mintExtensionNew.
    ///      Zero until initialize() runs; never re-assigned afterwards.
    uint256 internal _tokenId;

    /// @dev Cumulative drop-wide mints. Never decrements (burns don't re-open
    ///      supply per spec); sole source of getMintStats.currentTotalSupply.
    uint256 internal _totalMinted;

    /// @dev Admin-configured hard cap. SeaDrop enforces via getMintStats.
    uint256 internal _maxSupply;

    /// @dev Admin-configured per-wallet cap. SeaDrop enforces via getMintStats.
    uint256 internal _maxMintsPerWallet;

    /// @dev Per-wallet cumulative mints across allowlist + public phases.
    mapping(address => uint256) internal _minterNumMinted;

    /// @dev SeaDrop deployments authorized to call mintSeaDrop on this shim.
    EnumerableSet.AddressSet internal _allowedSeaDrop;

    /// @dev Resolves the tokenURI prefix ("", "https://arweave.net/", "ipfs://").
    StorageProtocol internal _storageProtocol;

    /// @dev Suffix appended to the storage-protocol prefix to form tokenURI.
    string internal _tokenUriLocation;

    /// @dev OpenSea collection-level metadata pointer.
    string internal _contractURI;

    /// @dev Display-only admin surfaced via owner(). No auth flows through it.
    address internal _projectAdmin;

    // -----------------------------------------------------------------------
    // Scaffold sentinel
    // -----------------------------------------------------------------------

    /// @dev Reverts every stub below until the owning story replaces it with
    ///      real logic. Intentionally not part of the external interface.
    error NotImplemented();

    // -----------------------------------------------------------------------
    // Auth
    // -----------------------------------------------------------------------

    /**
     * @dev Gate that resolves against the bound Creator Core's admin list.
     *      Matches the creatorAdminRequired pattern used by every other
     *      Manifold extension (Soulbound, Edition, LazyPayableClaim, ...).
     */
    modifier creatorAdminRequired(address creator) {
        if (!IAdminControl(creator).isAdmin(msg.sender)) {
            revert("Must be owner or admin of creator contract");
        }
        _;
    }

    /**
     * @dev Gate for mintSeaDrop — msg.sender must be a SeaDrop deployment the
     *      creator admin has whitelisted via the constructor or
     *      updateAllowedSeaDrop. No admin-bypass: AdminControl ops flow through
     *      initialize / multiConfigure, not this mint path.
     */
    modifier onlyAllowedSeaDrop() {
        if (!_allowedSeaDrop.contains(msg.sender)) revert OnlyAllowedSeaDrop();
        _;
    }

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------

    constructor(
        address creatorContractAddress_,
        uint256 instanceId_,
        address[] memory initialAllowedSeaDrop_
    ) {
        creatorContractAddress = creatorContractAddress_;
        instanceId = instanceId_;

        uint256 length = initialAllowedSeaDrop_.length;
        for (uint256 i; i < length;) {
            _allowedSeaDrop.add(initialAllowedSeaDrop_[i]);
            unchecked {
                ++i;
            }
        }

        _projectAdmin = msg.sender;
    }

    // -----------------------------------------------------------------------
    // Lifecycle
    // -----------------------------------------------------------------------

    /**
     * @notice Seed the Creator Core tokenId and apply the full drop config.
     * @dev One-shot: mints a zero-amount "new token" on Creator Core solely to
     *      reserve the tokenId, then hands off to `_applyConfig` which pushes
     *      local caps + metadata and forwards the SeaDrop setters. Must be
     *      called AFTER the shim is registered as an extension on the creator
     *      contract — otherwise Creator Core reverts with
     *      "Must be registered extension".
     */
    function initialize(MultiConfigureStruct calldata cfg)
        external
        override
        creatorAdminRequired(creatorContractAddress)
    {
        if (_tokenId != 0) revert AlreadyInitialized();

        address[] memory recipients = new address[](1);
        recipients[0] = msg.sender;
        uint256[] memory amounts = new uint256[](1);
        string[] memory uris = new string[](1);
        uint256[] memory minted = IERC1155CreatorCore(creatorContractAddress)
            .mintExtensionNew(recipients, amounts, uris);
        _tokenId = minted[0];

        emit Initialized(instanceId, _tokenId);
        _applyConfig(cfg);
    }

    /**
     * @notice Re-apply drop config after initialize() — used to extend the
     *         drop window, swap metadata, or add/remove fee recipients without
     *         redeploying the shim.
     * @dev Guards on `_tokenId == 0` so admins can't "half-initialize" a shim
     *      by reaching around `initialize()`; all other state transitions flow
     *      through the same `_applyConfig` the initializer uses, keeping the
     *      two paths byte-identical and idempotent for equal inputs.
     */
    function multiConfigure(MultiConfigureStruct calldata cfg)
        external
        override
        creatorAdminRequired(creatorContractAddress)
    {
        if (_tokenId == 0) revert NotInitialized();
        _applyConfig(cfg);
    }

    // -----------------------------------------------------------------------
    // Shared config application (US-005)
    // -----------------------------------------------------------------------

    /**
     * @dev Single source of truth for applying a MultiConfigureStruct. Used by
     *      both initialize() and multiConfigure() so the two paths stay byte
     *      identical — including the Configured event that marks the end.
     *      Setters are invoked in the order SeaDrop expects: publicDrop first
     *      (so the drop window is live), then allow list, then payout, then
     *      the fee-recipient loop.
     */
    function _applyConfig(MultiConfigureStruct calldata cfg) internal {
        _maxSupply = cfg.maxSupply;
        _maxMintsPerWallet = cfg.maxMintsPerWallet;
        _storageProtocol = cfg.storageProtocol;
        _tokenUriLocation = cfg.tokenUriLocation;
        _contractURI = cfg.contractURI;

        ISeaDrop seaDrop = ISeaDrop(cfg.seaDropImpl);
        seaDrop.updatePublicDrop(cfg.publicDrop);
        seaDrop.updateAllowList(cfg.allowListData);
        seaDrop.updateCreatorPayoutAddress(cfg.creatorPayoutAddress);

        uint256 length = cfg.allowedFeeRecipients.length;
        for (uint256 i; i < length;) {
            seaDrop.updateAllowedFeeRecipient(cfg.allowedFeeRecipients[i], true);
            unchecked {
                ++i;
            }
        }

        emit Configured(instanceId, _tokenId);
    }

    // -----------------------------------------------------------------------
    // SeaDrop surface (US-007)
    // -----------------------------------------------------------------------

    /**
     * @notice Mint entry invoked by an allowed SeaDrop on behalf of a minter.
     * @dev Counters are bumped BEFORE the external mint call so the accounting
     *      read by getMintStats is consistent even if Creator Core's
     *      mintExtensionExisting triggers an ERC1155 receiver hook — the shim's
     *      own nonReentrant lock plus the onlyAllowedSeaDrop gate bound the
     *      re-entrancy surface. SeaDrop upstream has already enforced the
     *      per-wallet + maxSupply caps via getMintStats; the shim trusts that
     *      quote and does not double-check them here.
     */
    function mintSeaDrop(address minter, uint256 quantity)
        external
        override
        onlyAllowedSeaDrop
        nonReentrant
    {
        if (_tokenId == 0) revert NotInitialized();

        _minterNumMinted[minter] += quantity;
        _totalMinted += quantity;

        address[] memory recipients = new address[](1);
        recipients[0] = minter;
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = _tokenId;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = quantity;
        IERC1155CreatorCore(creatorContractAddress).mintExtensionExisting(recipients, tokenIds, amounts);

        emit SeaDropMint(minter, quantity);
    }

    /**
     * @notice Tuple SeaDrop reads to enforce per-wallet + drop-wide caps.
     * @dev Order is fixed by the SeaDrop ABI (minterNumMinted, currentTotalSupply,
     *      maxSupply); changing it silently breaks any SeaDrop version that
     *      consumes the quote.
     */
    function getMintStats(address minter)
        external
        view
        override
        returns (uint256 minterNumMinted, uint256 currentTotalSupply, uint256 maxSupply_)
    {
        return (_minterNumMinted[minter], _totalMinted, _maxSupply);
    }

    // -----------------------------------------------------------------------
    // Local admin setters (US-008)
    // -----------------------------------------------------------------------

    /**
     * @notice Update the admin-configured supply cap.
     * @dev Clamps `newMaxSupply` up to `_totalMinted` so the cap never falls
     *      below already-minted supply — otherwise SeaDrop's getMintStats
     *      would imply a drop has over-minted, which breaks its internal
     *      invariants. Emits the post-clamp value.
     */
    function setMaxSupply(uint256 newMaxSupply)
        external
        override
        creatorAdminRequired(creatorContractAddress)
    {
        if (newMaxSupply < _totalMinted) newMaxSupply = _totalMinted;
        _maxSupply = newMaxSupply;
        emit MaxSupplyUpdated(newMaxSupply);
    }

    /**
     * @notice Update the per-wallet cumulative mint cap SeaDrop reads via
     *         getMintStats. No clamping — SeaDrop tolerates per-wallet caps
     *         below a wallet's current mint count (it simply blocks further
     *         mints for that wallet).
     */
    function setMaxMintsPerWallet(uint256 newMax)
        external
        override
        creatorAdminRequired(creatorContractAddress)
    {
        _maxMintsPerWallet = newMax;
        emit MaxMintsPerWalletUpdated(newMax);
    }

    /**
     * @notice Update the OpenSea collection-level metadata pointer.
     */
    function setContractURI(string calldata newContractURI)
        external
        override
        creatorAdminRequired(creatorContractAddress)
    {
        _contractURI = newContractURI;
        emit ContractURIUpdated();
    }

    /**
     * @notice Replace the stored storage protocol + URI location used by both
     *         tokenURI overloads (see US-009).
     * @dev INVALID is rejected so the assembled URI can never be ambiguous.
     *      No content validation on `location` — the storage protocol
     *      determines the prefix, the location is opaque to the shim.
     */
    function updateTokenURI(StorageProtocol storageProtocol, string calldata location)
        external
        override
        creatorAdminRequired(creatorContractAddress)
    {
        if (storageProtocol == StorageProtocol.INVALID) revert InvalidStorageProtocol();
        _storageProtocol = storageProtocol;
        _tokenUriLocation = location;
        emit TokenURIUpdated();
    }

    /**
     * @notice Append a chunk to the stored URI location — used to build up a
     *         large on-chain data URI across multiple admin transactions.
     * @dev Only valid when `_storageProtocol == NONE` (the no-prefix case).
     *      ARWEAVE / IPFS locations are opaque content-addressed IDs; appending
     *      bytes to them would produce a garbage URI, so we refuse.
     */
    function extendTokenURI(string calldata chunk)
        external
        override
        creatorAdminRequired(creatorContractAddress)
    {
        if (_storageProtocol != StorageProtocol.NONE) revert InvalidStorageProtocol();
        _tokenUriLocation = string.concat(_tokenUriLocation, chunk);
        emit TokenURIUpdated();
    }

    function updateAllowedSeaDrop(address[] calldata) external pure override {
        revert NotImplemented();
    }

    // -----------------------------------------------------------------------
    // SeaDrop pass-through stubs (US-010)
    // -----------------------------------------------------------------------

    function updatePublicDrop(address, PublicDrop calldata) external pure override {
        revert NotImplemented();
    }

    function updateAllowList(address, AllowListData calldata) external pure override {
        revert NotImplemented();
    }

    function updateCreatorPayoutAddress(address, address) external pure override {
        revert NotImplemented();
    }

    function updateAllowedFeeRecipient(address, address, bool) external pure override {
        revert NotImplemented();
    }

    function updateDropURI(address, string calldata) external pure override {
        revert NotImplemented();
    }

    function updatePayer(address, address, bool) external pure override {
        revert NotImplemented();
    }

    // -----------------------------------------------------------------------
    // Metadata views (US-009)
    // -----------------------------------------------------------------------

    /**
     * @notice OpenSea collection-level metadata pointer set via setContractURI.
     */
    function contractURI() external view override returns (string memory) {
        return _contractURI;
    }

    /**
     * @notice Assemble the tokenURI for this shim's single drop tokenId.
     * @dev Reverts with TokenDNE on any tokenId other than the one
     *      initialize() seeded. The prefix comes from the stored
     *      StorageProtocol (NONE -> "", ARWEAVE -> "https://arweave.net/",
     *      IPFS -> "ipfs://") and is concatenated with the opaque
     *      _tokenUriLocation suffix maintained by updateTokenURI /
     *      extendTokenURI.
     */
    function tokenURI(uint256 tokenId) external view override returns (string memory) {
        if (tokenId != _tokenId) revert TokenDNE();
        return string.concat(_uriPrefix(), _tokenUriLocation);
    }

    /**
     * @notice ICreatorExtensionTokenURI overload invoked by Creator Core when
     *         it routes a tokenURI read through this extension. Must return
     *         the same assembled URI as the bare-tokenId overload so OpenSea
     *         and Creator Core see identical metadata regardless of which
     *         caller queries.
     */
    function tokenURI(address creator, uint256 tokenId) external view override returns (string memory) {
        if (creator != creatorContractAddress || tokenId != _tokenId) revert TokenDNE();
        return string.concat(_uriPrefix(), _tokenUriLocation);
    }

    /**
     * @notice Empty base URI — the shim returns fully-assembled tokenURIs, so
     *         there is no Creator Core-style base that consumers concatenate
     *         against. Kept on the ABI because SeaDrop-compatible indexers
     *         probe for the field.
     */
    function baseURI() external pure override returns (string memory) {
        return "";
    }

    /**
     * @dev Resolves _storageProtocol to its tokenURI prefix. Kept internal and
     *      pure so both tokenURI overloads share a single source of truth.
     */
    function _uriPrefix() internal view returns (string memory) {
        StorageProtocol sp = _storageProtocol;
        if (sp == StorageProtocol.ARWEAVE) return "https://arweave.net/";
        if (sp == StorageProtocol.IPFS) return "ipfs://";
        return "";
    }

    // -----------------------------------------------------------------------
    // View stubs (US-011)
    // -----------------------------------------------------------------------

    function maxSupply() external pure override returns (uint256) {
        revert NotImplemented();
    }

    function totalSupply() external pure override returns (uint256) {
        revert NotImplemented();
    }

    function provenanceHash() external pure override returns (bytes32) {
        revert NotImplemented();
    }

    function getAllowedSeaDrop() external pure override returns (address[] memory) {
        revert NotImplemented();
    }

    function owner() public pure override(IManifoldERC1155SeaDropShim, Ownable) returns (address) {
        revert NotImplemented();
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AdminControl, IERC165)
        returns (bool)
    {
        return AdminControl.supportsInterface(interfaceId);
    }
}
