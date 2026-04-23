// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

/// @author: manifold.xyz

import {AdminControl} from "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";
import {IAdminControl} from "@manifoldxyz/libraries-solidity/contracts/access/IAdminControl.sol";
import {ICreatorExtensionTokenURI} from "@manifoldxyz/creator-core-solidity/contracts/extensions/ICreatorExtensionTokenURI.sol";
import {IERC1155CreatorCore} from "@manifoldxyz/creator-core-solidity/contracts/core/IERC1155CreatorCore.sol";

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IManifoldERC1155SeaDropShim} from "./IManifoldERC1155SeaDropShim.sol";
import {INonFungibleSeaDropToken} from "./INonFungibleSeaDropToken.sol";
import {ISeaDrop} from "./ISeaDrop.sol";
import {ISeaDropTokenContractMetadata} from "./ISeaDropTokenContractMetadata.sol";
import {AllowListData, MultiConfigureStruct, PublicDrop, StorageProtocol} from "./SeaDropStructs.sol";

/**
 * @notice ManifoldERC1155SeaDropShim — SeaDrop-facing extension that fronts a
 *         single ERC1155 drop living on a Manifold Creator Core contract.
 * @dev One shim per drop. The (creatorContractAddress, instanceId) pair is
 *      immutable, and _tokenId becomes effectively immutable after the first
 *      initialize(). The shim binds OpenSea's SeaDrop drop surface (mint,
 *      cap accounting, metadata views, admin pass-through) to Creator Core's
 *      mintExtensionExisting flow without minting a parallel token. See
 *      specs/manifold-seadrop-shim-erc1155.md for the full architecture and
 *      auth boundaries.
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

    // -----------------------------------------------------------------------
    // Auth
    // -----------------------------------------------------------------------

    /**
     * @dev Admin gate for every config setter. Accepts either a creator-
     *      contract admin OR the shim itself (`address(this)`) as caller.
     *      The "or self" branch is what lets multiConfigure dispatch via
     *      `this.updateX(...)` — the inner setter sees msg.sender == this
     *      and passes without being a creator admin. Mirrors upstream
     *      ERC721SeaDrop's `_onlyOwnerOrSelf` pattern.
     *
     *      Inlined as a helper rather than a modifier so the check costs the
     *      same bytecode per call site (and matches upstream style). Note:
     *      accepting `address(this)` widens the trust boundary by exactly one
     *      address. The shim has no delegatecall, no fallback, and no
     *      arbitrary-call forwarder, so the only way msg.sender becomes
     *      `address(this)` is via a `this.` self-call from within the
     *      contract's own code. Any future primitive that forwards external
     *      calls must explicitly exclude the shim's own admin surface.
     */
    function _onlyCreatorAdminOrSelf() internal view {
        if (
            msg.sender != address(this) &&
            !IAdminControl(creatorContractAddress).isAdmin(msg.sender)
        ) {
            revert("Must be owner or admin of creator contract");
        }
    }

    /**
     * @dev Gate for mintSeaDrop — msg.sender must be a SeaDrop deployment the
     *      creator admin has whitelisted via the constructor or
     *      updateAllowedSeaDrop. Deliberately does NOT admit self: this is a
     *      mint path, not a config path, and the self-bypass must not leak
     *      into token accounting.
     */
    modifier onlyAllowedSeaDrop() {
        if (!_allowedSeaDrop.contains(msg.sender)) revert OnlyAllowedSeaDrop();
        _;
    }

    /**
     * @dev Cheap bool -> uint256 coercion used to OR two boolean conditions
     *      into a single branch inside multiConfigure's publicDrop guard.
     *      Mirrors upstream SeaDrop; saves a JUMPI vs `||`.
     */
    function _cast(bool b) internal pure returns (uint256 u) {
        assembly {
            u := b
        }
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
    }

    // -----------------------------------------------------------------------
    // Lifecycle
    // -----------------------------------------------------------------------

    /**
     * @notice Seed the Creator Core tokenId, then delegate the rest of the
     *         drop config to multiConfigure via a self-call.
     * @dev One-shot: mints a zero-amount "new token" on Creator Core solely to
     *      reserve the tokenId. After `_tokenId` is populated, calls
     *      `this.multiConfigure(cfg)` so initialize and reconfigure share a
     *      single dispatch path — same zero-gating, same per-setter events.
     *      Because multiConfigure skips zero-value fields, the admin must
     *      pass a complete cfg on the first call (matching upstream SeaDrop's
     *      multiConfigure convention). Must be called AFTER the shim is
     *      registered as an extension on the creator contract — otherwise
     *      Creator Core reverts with "Must be registered extension".
     */
    function initialize(MultiConfigureStruct calldata cfg) external override {
        _onlyCreatorAdminOrSelf();
        if (_tokenId != 0) revert AlreadyInitialized();

        address[] memory recipients = new address[](1);
        recipients[0] = msg.sender;
        uint256[] memory amounts = new uint256[](1);
        string[] memory uris = new string[](1);
        uint256[] memory minted = IERC1155CreatorCore(creatorContractAddress)
            .mintExtensionNew(recipients, amounts, uris);
        _tokenId = minted[0];

        emit Initialized(instanceId, _tokenId);
        this.multiConfigure(cfg);
    }

    /**
     * @notice Configure multiple properties at a time.
     * @dev Zero-value / empty-array fields are skipped — admins use the
     *      individual external setters to unset or reset a property to zero.
     *      Each populated field dispatches through `this.updateX(...)`; the
     *      self-call is accepted by `_onlyCreatorAdminOrSelf` so the targeted
     *      setter applies its own clamping (e.g. setMaxSupply) and emits its
     *      own per-field event alongside the Configured summary. Guards on
     *      `_tokenId == 0` so admins can't "half-initialize" a shim by
     *      reaching around initialize().
     */
    function multiConfigure(MultiConfigureStruct calldata cfg) external override {
        _onlyCreatorAdminOrSelf();
        if (_tokenId == 0) revert NotInitialized();

        if (cfg.maxSupply > 0) {
            this.setMaxSupply(cfg.maxSupply);
        }
        if (cfg.maxMintsPerWallet > 0) {
            this.setMaxMintsPerWallet(cfg.maxMintsPerWallet);
        }
        if (bytes(cfg.contractURI).length != 0) {
            this.setContractURI(cfg.contractURI);
        }
        if (cfg.storageProtocol != StorageProtocol.INVALID) {
            this.updateTokenURI(cfg.storageProtocol, cfg.tokenUriLocation);
        }
        if (
            _cast(cfg.publicDrop.startTime != 0) |
            _cast(cfg.publicDrop.endTime != 0) == 1
        ) {
            this.updatePublicDrop(cfg.seaDropImpl, cfg.publicDrop);
        }
        if (cfg.allowListData.merkleRoot != bytes32(0)) {
            this.updateAllowList(cfg.seaDropImpl, cfg.allowListData);
        }
        if (cfg.creatorPayoutAddress != address(0)) {
            this.updateCreatorPayoutAddress(cfg.seaDropImpl, cfg.creatorPayoutAddress);
        }

        uint256 length = cfg.allowedFeeRecipients.length;
        for (uint256 i; i < length;) {
            this.updateAllowedFeeRecipient(cfg.seaDropImpl, cfg.allowedFeeRecipients[i], true);
            unchecked { ++i; }
        }
        length = cfg.disallowedFeeRecipients.length;
        for (uint256 i; i < length;) {
            this.updateAllowedFeeRecipient(cfg.seaDropImpl, cfg.disallowedFeeRecipients[i], false);
            unchecked { ++i; }
        }
        length = cfg.allowedPayers.length;
        for (uint256 i; i < length;) {
            this.updatePayer(cfg.seaDropImpl, cfg.allowedPayers[i], true);
            unchecked { ++i; }
        }
        length = cfg.disallowedPayers.length;
        for (uint256 i; i < length;) {
            this.updatePayer(cfg.seaDropImpl, cfg.disallowedPayers[i], false);
            unchecked { ++i; }
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
    function setMaxSupply(uint256 newMaxSupply) external override {
        _onlyCreatorAdminOrSelf();
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
    function setMaxMintsPerWallet(uint256 newMax) external override {
        _onlyCreatorAdminOrSelf();
        _maxMintsPerWallet = newMax;
        emit MaxMintsPerWalletUpdated(newMax);
    }

    /**
     * @notice Update the OpenSea collection-level metadata pointer.
     */
    function setContractURI(string calldata newContractURI) external override {
        _onlyCreatorAdminOrSelf();
        _contractURI = newContractURI;
        emit ContractURIUpdated(newContractURI);
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
    {
        _onlyCreatorAdminOrSelf();
        if (storageProtocol == StorageProtocol.INVALID) revert InvalidStorageProtocol();
        _storageProtocol = storageProtocol;
        _tokenUriLocation = location;
        emit TokenURIUpdated();
        emit BatchMetadataUpdate(_tokenId, _tokenId);
    }

    /**
     * @notice Append a chunk to the stored URI location — used to build up a
     *         large on-chain data URI across multiple admin transactions.
     * @dev Only valid when `_storageProtocol == NONE` (the no-prefix case).
     *      ARWEAVE / IPFS locations are opaque content-addressed IDs; appending
     *      bytes to them would produce a garbage URI, so we refuse.
     */
    function extendTokenURI(string calldata chunk) external override {
        _onlyCreatorAdminOrSelf();
        if (_storageProtocol != StorageProtocol.NONE) revert InvalidStorageProtocol();
        _tokenUriLocation = string.concat(_tokenUriLocation, chunk);
        emit TokenURIUpdated();
        emit BatchMetadataUpdate(_tokenId, _tokenId);
    }

    /**
     * @notice Replace the set of SeaDrop deployments authorized to call
     *         `mintSeaDrop`. Set-semantics: the prior set is drained and the
     *         new members are added in array order; duplicates in `newAllowed`
     *         collapse naturally.
     * @dev Only the shim-local allow list changes here — there is no forward
     *      to ISeaDrop because SeaDrop has no matching setter; it's a pure
     *      local-auth config. Emits the raw input array so indexers can diff
     *      against the prior Configured/AllowedSeaDropUpdated state.
     */
    function updateAllowedSeaDrop(address[] calldata newAllowed) external override {
        _onlyCreatorAdminOrSelf();
        uint256 previousLength = _allowedSeaDrop.length();
        for (uint256 i; i < previousLength;) {
            // Always pull index 0 — removal swaps the last element into the
            // vacated slot, so the set shrinks toward empty after `length`
            // iterations regardless of address ordering.
            _allowedSeaDrop.remove(_allowedSeaDrop.at(0));
            unchecked {
                ++i;
            }
        }

        uint256 newLength = newAllowed.length;
        for (uint256 i; i < newLength;) {
            _allowedSeaDrop.add(newAllowed[i]);
            unchecked {
                ++i;
            }
        }

        emit AllowedSeaDropUpdated(newAllowed);
    }

    // -----------------------------------------------------------------------
    // SeaDrop pass-through setters (US-010)
    // -----------------------------------------------------------------------
    //
    // Thin forwards so the creator admin can reconfigure a live drop through
    // the shim's stable address. Each call targets an arbitrary SeaDrop
    // deployment passed in by the admin — intentionally not gated against the
    // shim's own `_allowedSeaDrop` set, because these setters are admin-only
    // config operations, not mint operations, and the admin may want to push
    // config to a SeaDrop instance before whitelisting it for mints.

    function updatePublicDrop(address seaDropImpl, PublicDrop calldata publicDrop)
        external
        override
    {
        _onlyCreatorAdminOrSelf();
        ISeaDrop(seaDropImpl).updatePublicDrop(publicDrop);
    }

    function updateAllowList(address seaDropImpl, AllowListData calldata allowListData)
        external
        override
    {
        _onlyCreatorAdminOrSelf();
        ISeaDrop(seaDropImpl).updateAllowList(allowListData);
    }

    function updateCreatorPayoutAddress(address seaDropImpl, address payoutAddress)
        external
        override
    {
        _onlyCreatorAdminOrSelf();
        ISeaDrop(seaDropImpl).updateCreatorPayoutAddress(payoutAddress);
    }

    function updateAllowedFeeRecipient(address seaDropImpl, address feeRecipient, bool allowed)
        external
        override
    {
        _onlyCreatorAdminOrSelf();
        ISeaDrop(seaDropImpl).updateAllowedFeeRecipient(feeRecipient, allowed);
    }

    function updateDropURI(address seaDropImpl, string calldata dropURI)
        external
        override
    {
        _onlyCreatorAdminOrSelf();
        ISeaDrop(seaDropImpl).updateDropURI(dropURI);
    }

    function updatePayer(address seaDropImpl, address payer, bool allowed)
        external
        override
    {
        _onlyCreatorAdminOrSelf();
        ISeaDrop(seaDropImpl).updatePayer(payer, allowed);
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
    // SeaDrop + indexer views (US-011)
    // -----------------------------------------------------------------------

    /**
     * @notice Admin-configured supply cap. SeaDrop polls this via
     *         getMintStats; OpenSea's drop UI surfaces it directly.
     */
    function maxSupply() external view override returns (uint256) {
        return _maxSupply;
    }

    /**
     * @notice Drop-wide cumulative mints. Mirrors getMintStats.currentTotalSupply
     *         so any ERC721-style indexer reading totalSupply() sees the same
     *         value SeaDrop uses for cap enforcement. Burns on Creator Core do
     *         NOT decrement this counter (intentional — see spec edge case).
     */
    function totalSupply() external view override returns (uint256) {
        return _totalMinted;
    }

    /**
     * @notice Provenance hash is intentionally disabled for v1 — random-reveal
     *         flows are out of scope. Returning bytes32(0) signals "no
     *         pre-committed metadata" to indexers that probe for it.
     */
    function provenanceHash() external pure override returns (bytes32) {
        return bytes32(0);
    }

    /**
     * @notice The set of SeaDrop deployments authorized to call mintSeaDrop.
     *         Returned in EnumerableSet insertion order (which matches the
     *         most recent updateAllowedSeaDrop call's input order, since
     *         updateAllowedSeaDrop drains the set before re-adding).
     */
    function getAllowedSeaDrop() external view override returns (address[] memory) {
        return _allowedSeaDrop.values();
    }

    // owner() is inherited from Ownable (via AdminControl); the shim does not
    // override it. The inherited value is the deployer and is surfaced
    // verbatim for OpenSea / SeaDrop indexers that probe owner() as a UI
    // admin hint. Auth flows through `_onlyCreatorAdminOrSelf` against the
    // bound Creator Core, not through this address.

    /**
     * @notice ERC165 introspection covering every interface the shim claims
     *         compatibility with for SeaDrop and OpenSea indexer recognition:
     *         IERC165 + IAdminControl come from AdminControl;
     *         ICreatorExtensionTokenURI satisfies Creator Core routing;
     *         INonFungibleSeaDropToken + ISeaDropTokenContractMetadata are
     *         claimed via locally-mirrored canonical interfaces (US-022 will
     *         verify the computed IDs against deployed SeaDrop bytecode).
     *         The shim does not fully implement every method on the SeaDrop
     *         interfaces (token-gated drops, signed mints, on-chain royalties,
     *         baseURI / provenanceHash setters are v1 non-goals); claiming the
     *         interfaceId here is a discoverability signal, not a guarantee
     *         that every selector dispatches to a non-revert path.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AdminControl, IERC165)
        returns (bool)
    {
        return interfaceId == type(INonFungibleSeaDropToken).interfaceId
            || interfaceId == type(ISeaDropTokenContractMetadata).interfaceId
            || interfaceId == type(ICreatorExtensionTokenURI).interfaceId
            || AdminControl.supportsInterface(interfaceId);
    }
}
