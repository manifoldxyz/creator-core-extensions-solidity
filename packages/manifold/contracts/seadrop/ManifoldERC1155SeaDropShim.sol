// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ERC721SeaDrop} from "seadrop/src/ERC721SeaDrop.sol";
import {IERC1155CreatorCore} from "@manifoldxyz/creator-core-solidity/contracts/core/IERC1155CreatorCore.sol";

/**
 * @title  ManifoldERC1155SeaDropShim
 * @notice SeaDrop-compatible registration surface for an ERC1155 drop on a
 *         Manifold Creator Core contract.
 *
 *         OpenSea's drop indexer keys all drop state on `msg.sender` of the
 *         registration calls (`updatePublicDrop`, `updateAllowList`, etc.) and
 *         expects that address to be a SeaDrop-compatible NFT contract. This
 *         shim inherits `ERC721SeaDrop` so OpenSea sees the full surface it
 *         expects, while actual mints are routed to a single ERC1155 tokenId
 *         on a Manifold Creator Core contract via `mintExtensionExisting`.
 *
 *         The shim's own ERC721 supply stays at 0 forever — ERC721A's internal
 *         counters are unused. Per-wallet caps + max supply are tracked
 *         locally and reported through `getMintStats` so SeaDrop's enforcement
 *         hits real numbers.
 *
 *         Auth model: `onlyOwner` (TwoStepOwnable) inherited from
 *         `ERC721SeaDrop`. The deploy wallet owns the drop config.
 *
 *         Deployment order:
 *           1. Deploy this shim (constructor sets immutable creator + instanceId).
 *           2. Call `creator.registerExtension(shim, "")` on the Manifold
 *              Creator Core contract.
 *           3. Call `shim.initialize()` to seed the ERC1155 tokenId on the
 *              creator contract via `mintExtensionNew` (amount=0).
 *           4. Use the inherited `multiConfigure` (or individual setters) to
 *              push `publicDrop` / `allowList` / fee recipients to SeaDrop.
 *
 *         Token metadata (`tokenURI`) is served by the underlying Manifold
 *         creator contract and is set out-of-band (Studio UI or direct admin
 *         call). Drop-page metadata (`contractURI`, `baseURI`) is served by
 *         this shim via the inherited `ERC721ContractMetadata` surface.
 */
contract ManifoldERC1155SeaDropShim is ERC721SeaDrop {
    /// @notice Reverts if `initialize()` is called more than once.
    error AlreadyInitializedShim();

    /// @notice Reverts if the constructor is given a zero `initialOwner_`.
    error InitialOwnerIsZeroAddress();

    /// @notice The Manifold Creator Core contract this shim mints on.
    address public immutable creatorContractAddress;

    /// @notice An opaque identifier carried by Manifold's drop tooling so a
    ///         single creator contract can host multiple shim deployments.
    uint256 public immutable instanceId;

    /// @notice The ERC1155 tokenId on the creator contract this shim mints.
    ///         Set exactly once by `initialize()`. Zero until initialized.
    uint256 public tokenId;

    /// @notice Total mints routed through this shim. Used for SeaDrop's
    ///         max-supply enforcement (the shim's ERC721A `_totalMinted()`
    ///         stays at 0 forever, so we cannot rely on it).
    uint256 internal _shimTotalMinted;

    /// @notice Per-minter mint count routed through this shim. Used for
    ///         SeaDrop's per-wallet cap enforcement.
    mapping(address => uint256) internal _shimMinterNumMinted;

    /**
     * @notice Deploy the shim.
     *
     * @param name_                     ERC721 name (used by ERC721A).
     * @param symbol_                   ERC721 symbol (used by ERC721A).
     * @param allowedSeaDrop_           SeaDrop contract addresses allowed to
     *                                  call `mintSeaDrop` on this shim.
     * @param creatorContractAddress_   Manifold Creator Core contract.
     * @param instanceId_               Opaque drop instance identifier.
     * @param initialOwner_             The wallet to transfer ownership to
     *                                  immediately after deploy. Required
     *                                  when deploying through a CREATE2
     *                                  factory (where the broadcaster is the
     *                                  factory address, not the intended
     *                                  drop admin).
     */
    constructor(
        string memory name_,
        string memory symbol_,
        address[] memory allowedSeaDrop_,
        address creatorContractAddress_,
        uint256 instanceId_,
        address initialOwner_
    ) ERC721SeaDrop(name_, symbol_, allowedSeaDrop_) {
        if (initialOwner_ == address(0)) revert InitialOwnerIsZeroAddress();
        creatorContractAddress = creatorContractAddress_;
        instanceId = instanceId_;
        // ERC721SeaDrop's TwoStepOwnable constructor already set the owner
        // to msg.sender; transfer to the explicit initialOwner.
        _transferOwnership(initialOwner_);
    }

    /**
     * @notice Seed the ERC1155 `tokenId` on the Manifold Creator Core contract.
     *
     *         Calls `mintExtensionNew` on the creator with amount=0 to register
     *         the tokenId and bind it to this shim as the originating
     *         extension (Creator Core enforces `_tokenExtension[tokenId] ==
     *         msg.sender` inside `mintExtensionExisting`, so the shim must be
     *         the extension that created the tokenId).
     *
     *         Must be called after the shim has been registered as an
     *         extension on the creator contract via `registerExtension`.
     *         Reverts if called twice.
     */
    function initialize() external onlyOwner {
        if (tokenId != 0) revert AlreadyInitializedShim();

        address[] memory to = new address[](1);
        to[0] = msg.sender;
        uint256[] memory amounts = new uint256[](1);
        // amounts[0] = 0 — registers the tokenId without minting.
        string[] memory uris = new string[](1);
        // uris[0] = "" — token URI is set on the creator contract out-of-band.

        uint256[] memory mintedTokenIds = IERC1155CreatorCore(
            creatorContractAddress
        ).mintExtensionNew(to, amounts, uris);

        tokenId = mintedTokenIds[0];
    }

    /**
     * @notice Mint via SeaDrop. Routes to `mintExtensionExisting` on the
     *         Manifold Creator Core contract for the bound `tokenId`.
     *
     * @param minter   The address to mint to.
     * @param quantity The number of ERC1155 tokens to mint.
     */
    function mintSeaDrop(address minter, uint256 quantity)
        external
        override
        nonReentrant
    {
        // Ensure the SeaDrop is allowed.
        _onlyAllowedSeaDrop(msg.sender);

        // Extra safety check to ensure the max supply is not exceeded.
        // SeaDrop already checks against `getMintStats` before calling, but
        // this guards against misconfigured callers.
        uint256 newTotal = _shimTotalMinted + quantity;
        uint256 cap = maxSupply();
        if (newTotal > cap) {
            revert MintQuantityExceedsMaxSupply(newTotal, cap);
        }

        // Update local accounting *before* the external call so SeaDrop's
        // re-entry checks see consistent state. The `nonReentrant` modifier
        // is the primary defense; this is belt-and-suspenders.
        _shimMinterNumMinted[minter] += quantity;
        _shimTotalMinted = newTotal;

        // Route the mint to the underlying Manifold Creator Core contract.
        address[] memory to = new address[](1);
        to[0] = minter;
        uint256[] memory ids = new uint256[](1);
        ids[0] = tokenId;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = quantity;

        IERC1155CreatorCore(creatorContractAddress).mintExtensionExisting(
            to,
            ids,
            amounts
        );
    }

    /**
     * @notice Returns the mint stats SeaDrop uses to enforce per-wallet and
     *         max-supply caps. The shim's ERC721A counters are unused and
     *         always zero, so we report the shim-local counters instead.
     *
     *         Note: per-wallet counts only see mints routed through this
     *         shim — not mints from other extensions registered on the same
     *         creator contract.
     *
     * @param minter The minter address.
     */
    function getMintStats(address minter)
        external
        view
        override
        returns (
            uint256 minterNumMinted,
            uint256 currentTotalSupply,
            uint256 maxSupply_
        )
    {
        minterNumMinted = _shimMinterNumMinted[minter];
        currentTotalSupply = _shimTotalMinted;
        maxSupply_ = maxSupply();
    }

    /**
     * @notice Update the metadata URI for the bound ERC1155 tokenId on the
     *         Manifold Creator Core contract.
     *
     *         Creator Core gates `setTokenURIExtension` on `msg.sender`
     *         being the registered extension that originally minted the
     *         tokenId — that's this shim — so this passthrough is the only
     *         way to drive token metadata after `initialize()`. Auth is
     *         `onlyOwner` (the deploy wallet); see contract-level NatSpec
     *         for the auth-model rationale.
     *
     *         `creator.uri(tokenId)` returns this value verbatim — no
     *         tokenId suffix, no prefix — because we're writing the
     *         per-token override (`_tokenURIs[tokenId]`), which Creator
     *         Core's URI resolution prefers over the extension base URI.
     *
     * @param uri_ The metadata URI to set for the bound tokenId.
     */
    function updateURI(string calldata uri_) external onlyOwner {
        require(tokenId != 0, "Not initialized");
        IERC1155CreatorCore(creatorContractAddress).setTokenURIExtension(
            tokenId,
            uri_
        );
    }
}
