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
    // SeaDrop surface stubs (US-007)
    // -----------------------------------------------------------------------

    function mintSeaDrop(address, uint256) external pure override {
        revert NotImplemented();
    }

    function getMintStats(address) external pure override returns (uint256, uint256, uint256) {
        revert NotImplemented();
    }

    // -----------------------------------------------------------------------
    // Local admin setters stubs (US-008)
    // -----------------------------------------------------------------------

    function setMaxSupply(uint256) external pure override {
        revert NotImplemented();
    }

    function setMaxMintsPerWallet(uint256) external pure override {
        revert NotImplemented();
    }

    function setContractURI(string calldata) external pure override {
        revert NotImplemented();
    }

    function updateTokenURI(StorageProtocol, string calldata) external pure override {
        revert NotImplemented();
    }

    function extendTokenURI(string calldata) external pure override {
        revert NotImplemented();
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
    // View stubs (US-009, US-011)
    // -----------------------------------------------------------------------

    function maxSupply() external pure override returns (uint256) {
        revert NotImplemented();
    }

    function totalSupply() external pure override returns (uint256) {
        revert NotImplemented();
    }

    function contractURI() external pure override returns (string memory) {
        revert NotImplemented();
    }

    function tokenURI(uint256) external pure override returns (string memory) {
        revert NotImplemented();
    }

    function tokenURI(address, uint256) external pure override returns (string memory) {
        revert NotImplemented();
    }

    function baseURI() external pure override returns (string memory) {
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
