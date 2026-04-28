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
import {
    AllowListData,
    MultiConfigureStruct,
    PublicDrop,
    SignedMintValidationParams,
    StorageProtocol,
    TokenGatedDropStage
} from "./SeaDropStructs.sol";

/**
 * @notice ManifoldERC1155SeaDropShim — SeaDrop-facing extension that fronts a
 *         single ERC1155 drop living on a Manifold Creator Core contract.
 * @dev One shim per drop. The (creatorContractAddress, instanceId) pair is
 *      immutable, and _tokenId becomes effectively immutable after the first
 *      initialize(). The shim binds OpenSea's SeaDrop drop surface (mint,
 *      cap accounting, metadata views, admin pass-through) to Creator Core's
 *      mintExtensionExisting flow.
 */
contract ManifoldERC1155SeaDropShim is
    AdminControl,
    INonFungibleSeaDropToken,
    IManifoldERC1155SeaDropShim,
    ICreatorExtensionTokenURI,
    ReentrancyGuard
{
    using EnumerableSet for EnumerableSet.AddressSet;

    // tokenURI prefixes
    string internal constant ARWEAVE_PREFIX = "https://arweave.net/";
    string internal constant IPFS_PREFIX = "ipfs://";

    // -----------------------------------------------------------------------
    // Immutable binding (constructor)
    // -----------------------------------------------------------------------

    /// @notice The Manifold Creator Core contract this shim drops onto.
    address public immutable creatorContractAddress;

    /// @notice Manifold drop instanceId —
    ///         Bound at deploy time and never re-assigned.
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

    /// @dev Per-wallet cumulative mints across allowlist + public phases.
    mapping(address => uint256) internal _minterNumMinted;

    /// @dev SeaDrop deployments authorized to call mintSeaDrop on this shim.
    EnumerableSet.AddressSet internal _allowedSeaDrop;

    /// @dev Resolves the tokenURI prefix ("", "https://arweave.net/", "ipfs://").
    StorageProtocol internal _storageProtocol;

    /// @dev Suffix appended to the storage-protocol prefix to form tokenURI.
    string internal _tokenUriLocation;

    /// @dev Collection-level metadata pointer.
    string internal _contractURI;

    // -----------------------------------------------------------------------
    // Auth
    // -----------------------------------------------------------------------

    /**
     * @dev Admin gate for every config setter. Resolves against the bound
     *      Creator Core's AdminControl — only wallets flagged as admins on
     *      the creator contract pass.
     */
    modifier creatorAdminRequired(address creator) {
        if (!IAdminControl(creator).isAdmin(msg.sender)) {
            revert("Must be owner or admin of creator contract");
        }
        _;
    }

    /**
     * @dev Reverts if `seaDrop` is not in the shim's allowed-SeaDrop set.
     *      Inlined (not a modifier) to save contract space — used by both `mintSeaDrop` (against msg.sender)
     *      and every SeaDrop pass-through setter (against seaDropImpl).
     */
    function _onlyAllowedSeaDrop(address seaDrop) internal view {
        if (!_allowedSeaDrop.contains(seaDrop)) revert OnlyAllowedSeaDrop();
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

        emit ManifoldSeaDropTokenDeployed();
    }

    // -----------------------------------------------------------------------
    // Lifecycle
    // -----------------------------------------------------------------------

    /**
     * @notice Seed the Creator Core tokenId and apply the full drop config.
     * @dev One-shot: mints a zero-amount "new token" on Creator Core solely
     *      to reserve the tokenId, then hands off to `_applyConfig` which
     *      runs the shared zero-gated dispatch. Must be called AFTER the
     *      shim is registered as an extension on the creator contract —
     *      otherwise Creator Core reverts with "Must be registered
     *      extension". Because `_applyConfig` skips zero-value fields, the
     *      admin must pass a complete cfg on the first call.
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

        _applyConfig(cfg);
        emit Initialized(instanceId, _tokenId);
    }

    /**
     * @notice Re-apply a partial drop config after initialize().
     * @dev Gated by creatorAdminRequired on the bound Creator Core.
     *      Delegates to `_applyConfig` — zero-value / empty-array fields are
     *      ignored so admins can tweak just the fields they care about.
     *      Admins use the individual external setters to unset or reset a
     *      property to zero.
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
    // Shared config application (internal)
    // -----------------------------------------------------------------------

    /**
     * @dev Shared zero-gated dispatch used by both initialize() and
     *      multiConfigure(). Routes each populated field through its internal
     *      `_setX` / `_updateX` helper so bounds checks + per-field events live
     *      in exactly one place (reused by the external setters). Auth lives on
     *      the outer entry points, not here, because every caller of this
     *      helper has already passed `creatorAdminRequired`.
     */
    function _applyConfig(MultiConfigureStruct calldata cfg) internal {
        if (cfg.maxSupply > 0) {
            _setMaxSupply(cfg.maxSupply);
        }
        if (bytes(cfg.contractURI).length != 0) {
            _setContractURI(cfg.contractURI);
        }
        if (cfg.storageProtocol != StorageProtocol.INVALID) {
            _updateTokenURI(cfg.storageProtocol, cfg.tokenUriLocation);
        }
        if (
            _cast(cfg.publicDrop.startTime != 0) |
            _cast(cfg.publicDrop.endTime != 0) == 1
        ) {
            _updatePublicDrop(cfg.seaDropImpl, cfg.publicDrop);
        }
        if (bytes(cfg.dropURI).length != 0) {
            _updateDropURI(cfg.seaDropImpl, cfg.dropURI);
        }
        if (cfg.allowListData.merkleRoot != bytes32(0)) {
            _updateAllowList(cfg.seaDropImpl, cfg.allowListData);
        }
        if (cfg.creatorPayoutAddress != address(0)) {
            _updateCreatorPayoutAddress(cfg.seaDropImpl, cfg.creatorPayoutAddress);
        }
        if (cfg.allowedFeeRecipients.length > 0) {
            for (uint256 i = 0; i < cfg.allowedFeeRecipients.length;) {
                _updateAllowedFeeRecipient(cfg.seaDropImpl, cfg.allowedFeeRecipients[i], true);
                unchecked { ++i; }
            }
        }
        if (cfg.disallowedFeeRecipients.length > 0) {
            for (uint256 i = 0; i < cfg.disallowedFeeRecipients.length;) {
                _updateAllowedFeeRecipient(cfg.seaDropImpl, cfg.disallowedFeeRecipients[i], false);
                unchecked { ++i; }
            }
        }
        if (cfg.allowedPayers.length > 0) {
            for (uint256 i = 0; i < cfg.allowedPayers.length;) {
                _updatePayer(cfg.seaDropImpl, cfg.allowedPayers[i], true);
                unchecked { ++i; }
            }
        }
        if (cfg.disallowedPayers.length > 0) {
            for (uint256 i = 0; i < cfg.disallowedPayers.length;) {
                _updatePayer(cfg.seaDropImpl, cfg.disallowedPayers[i], false);
                unchecked { ++i; }
            }
        }
        if (cfg.tokenGatedDropStages.length > 0) {
            if (cfg.tokenGatedDropStages.length != cfg.tokenGatedAllowedNftTokens.length) {
                revert TokenGatedMismatch();
            }
            for (uint256 i = 0; i < cfg.tokenGatedDropStages.length;) {
                _updateTokenGatedDrop(
                    cfg.seaDropImpl,
                    cfg.tokenGatedAllowedNftTokens[i],
                    cfg.tokenGatedDropStages[i]
                );
                unchecked { ++i; }
            }
        }
        if (cfg.disallowedTokenGatedAllowedNftTokens.length > 0) {
            for (uint256 i = 0; i < cfg.disallowedTokenGatedAllowedNftTokens.length;) {
                TokenGatedDropStage memory emptyStage;
                _updateTokenGatedDrop(
                    cfg.seaDropImpl,
                    cfg.disallowedTokenGatedAllowedNftTokens[i],
                    emptyStage
                );
                unchecked { ++i; }
            }
        }
        if (cfg.signedMintValidationParams.length > 0) {
            if (cfg.signedMintValidationParams.length != cfg.signers.length) {
                revert SignersMismatch();
            }
            for (uint256 i = 0; i < cfg.signedMintValidationParams.length;) {
                _updateSignedMintValidationParams(
                    cfg.seaDropImpl,
                    cfg.signers[i],
                    cfg.signedMintValidationParams[i]
                );
                unchecked { ++i; }
            }
        }
        if (cfg.disallowedSigners.length > 0) {
            for (uint256 i = 0; i < cfg.disallowedSigners.length;) {
                SignedMintValidationParams memory emptyParams;
                _updateSignedMintValidationParams(
                    cfg.seaDropImpl,
                    cfg.disallowedSigners[i],
                    emptyParams
                );
                unchecked { ++i; }
            }
        }
    }

    // -----------------------------------------------------------------------
    // SeaDrop surface (US-007)
    // -----------------------------------------------------------------------

    /**
     * @notice Mint entry invoked by an allowed SeaDrop on behalf of a minter.
     * @dev Counters are bumped BEFORE the external mint call so the accounting
     *      read by getMintStats is consistent even if Creator Core's
     *      mintExtensionExisting triggers an ERC1155 receiver hook — the shim's
     *      own nonReentrant lock plus the _onlyAllowedSeaDrop gate bound the
     *      re-entrancy surface. SeaDrop upstream has already enforced the
     *      per-wallet + maxSupply caps via getMintStats; the shim trusts that
     *      quote and does not double-check them here.
     */
    function mintSeaDrop(address minter, uint256 quantity)
        external
        payable
        override(INonFungibleSeaDropToken)
        nonReentrant
    {
        _onlyAllowedSeaDrop(msg.sender);
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
        override(INonFungibleSeaDropToken)
        returns (uint256 minterNumMinted, uint256 currentTotalSupply, uint256 maxSupply_)
    {
        return (_minterNumMinted[minter], _totalMinted, _maxSupply);
    }

    // -----------------------------------------------------------------------
    // Local admin setters (US-008)
    // -----------------------------------------------------------------------

    /**
     * @notice Update the admin-configured supply cap.
     * @dev Reverts with `CannotExceedMaxSupplyOfUint64` if the new cap exceeds
     *      uint64, and with `NewMaxSupplyCannotBeLessThenTotalMinted` if the
     *      new cap is below already-minted supply — SeaDrop's getMintStats
     *      must never imply a drop has over-minted against its hard cap.
     */
    function setMaxSupply(uint256 newMaxSupply)
        external
        override(ISeaDropTokenContractMetadata)
        creatorAdminRequired(creatorContractAddress)
    {
        _setMaxSupply(newMaxSupply);
    }

    /**
     * @notice Update the OpenSea collection-level metadata pointer.
     */
    function setContractURI(string calldata newContractURI)
        external
        override(ISeaDropTokenContractMetadata)
        creatorAdminRequired(creatorContractAddress)
    {
        _setContractURI(newContractURI);
    }

    /**
     * @notice Canonical SeaDrop setter that writes the URI location backing
     *         tokenURI assembly. The shim's StorageProtocol-flavored
     *         `updateTokenURI` and chunk-append `extendTokenURI` share the
     *         same `_tokenUriLocation` storage slot — `setBaseURI` rewrites
     *         that slot wholesale without changing the storage protocol.
     *         If admin needs to switch protocol (e.g. NONE -> IPFS), use
     *         `updateTokenURI(StorageProtocol, string)` instead.
     */
    function setBaseURI(string calldata tokenURI)
        external
        override(ISeaDropTokenContractMetadata)
        creatorAdminRequired(creatorContractAddress)
    {
        _tokenUriLocation = tokenURI;
        emit BaseURIUpdated(tokenURI);
        emit TokenURIUpdated(_tokenId, _tokenId);
    }

    /**
     * @notice Provenance-hash not supported
     */
    function setProvenanceHash(bytes32)
        external
        override(ISeaDropTokenContractMetadata)
        creatorAdminRequired(creatorContractAddress)
    {
        revert ProvenanceHashNotSupported();
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
        _updateTokenURI(storageProtocol, location);
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
        _tokenUriLocation = string(abi.encodePacked(_tokenUriLocation, chunk));
        emit TokenURIUpdated(_tokenId, _tokenId);
    }

    /**
     * @notice Replace the set of SeaDrop deployments authorized to call
     *         `mintSeaDrop`. Set-semantics: the prior set is drained and the
     *         new members are added in array order; duplicates in `newAllowed`
     *         collapse naturally.
     * @dev Only the shim-local allow list changes here — there is no forward
     *      to ISeaDrop because SeaDrop has no matching setter; it's a pure
     *      local-auth config. Emits the raw input array so indexers can diff
     *      against the prior AllowedSeaDropUpdated state.
     */
    function updateAllowedSeaDrop(address[] calldata newAllowed)
        external
        override(INonFungibleSeaDropToken)
        creatorAdminRequired(creatorContractAddress)
    {
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
    // SeaDrop pass-through
    // -----------------------------------------------------------------------
    //
    // Thin forwards so the creator admin can reconfigure a live drop through
    // the shim's stable address. Each call is gated by `_onlyAllowedSeaDrop`
    // inside the internal helper so a typo in `seaDropImpl` cannot push config
    // to an un-whitelisted SeaDrop deployment. Runbook: admin adds the
    // deployment via the constructor or `updateAllowedSeaDrop` first, then
    // configures it through these forwarders.

    function updatePublicDrop(address seaDropImpl, PublicDrop calldata publicDrop)
        external
        override(INonFungibleSeaDropToken)
        creatorAdminRequired(creatorContractAddress)
    {
        _updatePublicDrop(seaDropImpl, publicDrop);
    }

    function updateAllowList(address seaDropImpl, AllowListData calldata allowListData)
        external
        override(INonFungibleSeaDropToken)
        creatorAdminRequired(creatorContractAddress)
    {
        _updateAllowList(seaDropImpl, allowListData);
    }

    function updateCreatorPayoutAddress(address seaDropImpl, address payoutAddress)
        external
        override(INonFungibleSeaDropToken)
        creatorAdminRequired(creatorContractAddress)
    {
        _updateCreatorPayoutAddress(seaDropImpl, payoutAddress);
    }

    function updateAllowedFeeRecipient(address seaDropImpl, address feeRecipient, bool allowed)
        external
        override(INonFungibleSeaDropToken)
        creatorAdminRequired(creatorContractAddress)
    {
        _updateAllowedFeeRecipient(seaDropImpl, feeRecipient, allowed);
    }

    function updateDropURI(address seaDropImpl, string calldata dropURI)
        external
        override(INonFungibleSeaDropToken)
        creatorAdminRequired(creatorContractAddress)
    {
        _updateDropURI(seaDropImpl, dropURI);
    }

    function updatePayer(address seaDropImpl, address payer, bool allowed)
        external
        override(INonFungibleSeaDropToken)
        creatorAdminRequired(creatorContractAddress)
    {
        _updatePayer(seaDropImpl, payer, allowed);
    }

    function updateTokenGatedDrop(
        address seaDropImpl,
        address allowedNftToken,
        TokenGatedDropStage calldata dropStage
    )
        external
        override(INonFungibleSeaDropToken)
        creatorAdminRequired(creatorContractAddress)
    {
        _updateTokenGatedDrop(seaDropImpl, allowedNftToken, dropStage);
    }

    function updateSignedMintValidationParams(
        address seaDropImpl,
        address signer,
        SignedMintValidationParams calldata signedMintValidationParams
    )
        external
        override(INonFungibleSeaDropToken)
        creatorAdminRequired(creatorContractAddress)
    {
        _updateSignedMintValidationParams(seaDropImpl, signer, signedMintValidationParams);
    }

    // -----------------------------------------------------------------------
    // Internal setter helpers
    // -----------------------------------------------------------------------
    //
    // Each external setter above does `creatorAdminRequired` and delegates to
    // its internal helper here. `_applyConfig` calls the same internal
    // helpers directly so the zero-gated dispatch doesn't need to re-run
    // auth. This keeps bounds checks + per-field events in exactly one place
    // without widening the admin surface to include `address(this)`.

    function _setMaxSupply(uint256 newMaxSupply) internal {
        // Ensure the max supply does not exceed the maximum value of uint64.
        if (newMaxSupply > 2**64 - 1) {
            revert CannotExceedMaxSupplyOfUint64(newMaxSupply);
        }

        // Ensure the max supply does not exceed the total minted.
        if (newMaxSupply < _totalMinted) {
            revert NewMaxSupplyCannotBeLessThenTotalMinted(newMaxSupply, _totalMinted);
        }

        _maxSupply = newMaxSupply;
        emit MaxSupplyUpdated(newMaxSupply);
    }

    function _setContractURI(string memory newContractURI) internal {
        _contractURI = newContractURI;
        emit ContractURIUpdated(newContractURI);
    }

    function _updateTokenURI(StorageProtocol storageProtocol, string memory location) internal {
        if (storageProtocol == StorageProtocol.INVALID) revert InvalidStorageProtocol();
        _storageProtocol = storageProtocol;
        _tokenUriLocation = location;
        emit TokenURIUpdated(_tokenId, _tokenId);
    }

    function _updatePublicDrop(address seaDropImpl, PublicDrop memory publicDrop) internal {
        _onlyAllowedSeaDrop(seaDropImpl);
        ISeaDrop(seaDropImpl).updatePublicDrop(publicDrop);
    }

    function _updateAllowList(address seaDropImpl, AllowListData memory allowListData) internal {
        _onlyAllowedSeaDrop(seaDropImpl);
        ISeaDrop(seaDropImpl).updateAllowList(allowListData);
    }

    function _updateCreatorPayoutAddress(address seaDropImpl, address payoutAddress) internal {
        _onlyAllowedSeaDrop(seaDropImpl);
        ISeaDrop(seaDropImpl).updateCreatorPayoutAddress(payoutAddress);
    }

    function _updateAllowedFeeRecipient(address seaDropImpl, address feeRecipient, bool allowed) internal {
        _onlyAllowedSeaDrop(seaDropImpl);
        ISeaDrop(seaDropImpl).updateAllowedFeeRecipient(feeRecipient, allowed);
    }

    function _updateDropURI(address seaDropImpl, string memory dropURI) internal {
        _onlyAllowedSeaDrop(seaDropImpl);
        ISeaDrop(seaDropImpl).updateDropURI(dropURI);
    }

    function _updatePayer(address seaDropImpl, address payer, bool allowed) internal {
        _onlyAllowedSeaDrop(seaDropImpl);
        ISeaDrop(seaDropImpl).updatePayer(payer, allowed);
    }

    function _updateTokenGatedDrop(
        address seaDropImpl,
        address allowedNftToken,
        TokenGatedDropStage memory dropStage
    ) internal {
        _onlyAllowedSeaDrop(seaDropImpl);
        ISeaDrop(seaDropImpl).updateTokenGatedDrop(allowedNftToken, dropStage);
    }

    function _updateSignedMintValidationParams(
        address seaDropImpl,
        address signer,
        SignedMintValidationParams memory signedMintValidationParams
    ) internal {
        _onlyAllowedSeaDrop(seaDropImpl);
        ISeaDrop(seaDropImpl).updateSignedMintValidationParams(signer, signedMintValidationParams);
    }

    /**
     * @notice OpenSea collection-level metadata pointer set via setContractURI.
     */
    function contractURI() external view override(ISeaDropTokenContractMetadata) returns (string memory) {
        return _contractURI;
    }

    /**
     * @notice Assemble the tokenURI for this shim's single drop tokenId.
     * @dev Reverts with TokenDNE on any tokenId other than the one
     *      initialize() seeded.
     */
    function tokenURI(uint256 tokenId) external view override(IManifoldERC1155SeaDropShim) returns (string memory uri) {
        if (tokenId != _tokenId) revert TokenDNE();

        string memory prefix = "";
        if (_storageProtocol == StorageProtocol.ARWEAVE) {
            prefix = ARWEAVE_PREFIX;
        } else if (_storageProtocol == StorageProtocol.IPFS) {
            prefix = IPFS_PREFIX;
        }
        uri = string(abi.encodePacked(prefix, _tokenUriLocation));
    }

    /**
     * @notice ICreatorExtensionTokenURI overload invoked by Creator Core when
     *         it routes a tokenURI read through this extension. Must return
     *         the same assembled URI as the bare-tokenId overload so OpenSea
     *         and Creator Core see identical metadata regardless of which
     *         caller queries.
     */
    function tokenURI(address creator, uint256 tokenId) external view override(ICreatorExtensionTokenURI) returns (string memory uri) {
        if (creator != creatorContractAddress || tokenId != _tokenId) revert TokenDNE();

        string memory prefix = "";
        if (_storageProtocol == StorageProtocol.ARWEAVE) {
            prefix = ARWEAVE_PREFIX;
        } else if (_storageProtocol == StorageProtocol.IPFS) {
            prefix = IPFS_PREFIX;
        }
        uri = string(abi.encodePacked(prefix, _tokenUriLocation));
    }

    /**
     * @notice Returns the URI location backing tokenURI assembly. Round-trips
     *         with `setBaseURI` so SeaDrop-compatible indexers that probe
     *         `baseURI()` after a `setBaseURI(...)` write see the value they
     *         just wrote. The full tokenURI returned by `tokenURI(...)` may
     *         additionally carry a storage-protocol prefix (ARWEAVE/IPFS) on
     *         top of this raw location — see `updateTokenURI(...)`.
     */
    function baseURI() external view override(ISeaDropTokenContractMetadata) returns (string memory) {
        return _tokenUriLocation;
    }

    /**
     * @notice Admin-configured supply cap. SeaDrop polls this via
     *         getMintStats; OpenSea's drop UI surfaces it directly.
     */
    function maxSupply() external view override(ISeaDropTokenContractMetadata) returns (uint256) {
        return _maxSupply;
    }

    /**
     * @notice Drop-wide cumulative mints.
     */
    function totalSupply() external view override(IManifoldERC1155SeaDropShim) returns (uint256) {
        return _totalMinted;
    }

    /**
     * @notice Provenance hash is intentionally disabled
     */
    function provenanceHash() external pure override(ISeaDropTokenContractMetadata) returns (bytes32) {
        return bytes32(0);
    }

    /**
     * @notice The set of SeaDrop deployments authorized to call mintSeaDrop.
     *         Returned in EnumerableSet insertion order (which matches the
     *         most recent updateAllowedSeaDrop call's input order, since
     *         updateAllowedSeaDrop drains the set before re-adding).
     */
    function getAllowedSeaDrop() external view override(IManifoldERC1155SeaDropShim) returns (address[] memory) {
        return _allowedSeaDrop.values();
    }

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
