// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../lazyclaim/IERC721LazyPayableClaim.sol";
import "../lazyclaim/ERC721LazyPayableClaimCore.sol";
import "./ILazyPayableClaimV2.sol";
import "./LazyPayableClaimV2.sol";

/**
 * @title Lazy Payable Claim
 * @author manifold.xyz
 * @notice Lazy payable claim with optional whitelist ERC721 tokens
 */
contract ERC721LazyPayableClaimV2 is ERC721LazyPayableClaimCore, LazyPayableClaimV2 {
    constructor(address initialOwner, address delegationRegistry, address delegationRegistryV2)
        LazyPayableClaimV2(initialOwner, delegationRegistry, delegationRegistryV2)
    {}

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721LazyPayableClaimCore, AdminControl)
        returns (bool)
    {
        return type(ILazyPayableClaimV2).interfaceId == interfaceId
            || ERC721LazyPayableClaimCore.supportsInterface(interfaceId);
    }

    /**
     * See {IERC721LazyClaim-initializeClaim}.
     */
    function initializeClaim(
        address creatorContractAddress,
        uint256 instanceId,
        ClaimParameters calldata claimParameters
    ) public override creatorAdminRequired(creatorContractAddress) {
        if (!active) revert Inactive();
        ERC721LazyPayableClaimCore.initializeClaim(creatorContractAddress, instanceId, claimParameters);
    }

    /**
     * See {ILazyPayableClaimV2-mint}.
     */
    function mint(
        address creatorContractAddress,
        uint256 instanceId,
        uint32 mintIndex,
        bytes32[] calldata merkleProof,
        address mintFor
    ) external payable override {
        Claim storage claim = _getClaim(creatorContractAddress, instanceId);

        if (claim.signingAddress != address(0)) revert ILazyPayableClaimCore.MustUseSignatureMinting();
        // Check totalMax
        if (((++claim.total > claim.totalMax && claim.totalMax != 0) || claim.total > MAX_UINT_24)) {
            revert ILazyPayableClaimCore.TooManyRequested();
        }

        // Validate mint
        _validateMint(
            creatorContractAddress,
            instanceId,
            claim.startDate,
            claim.endDate,
            claim.walletMax,
            claim.merkleRoot,
            mintIndex,
            merkleProof,
            mintFor
        );

        // Transfer funds
        _transferFunds(claim.erc20, claim.cost, claim.paymentReceiver, 1, claim.merkleRoot != "", true);

        // Do mint
        if (claim.contractVersion >= 3) {
            uint80 tokenData = uint56(instanceId) << 24 | uint24(claim.total);
            IERC721CreatorCore(creatorContractAddress).mintExtension(msg.sender, tokenData);
        } else {
            uint256 newTokenId = IERC721CreatorCore(creatorContractAddress).mintExtension(msg.sender);
            // Insert the new tokenId into _tokenClaims for the current claim address & instanceId
            _tokenClaims[creatorContractAddress][newTokenId] = TokenClaim(uint224(instanceId), claim.total);
        }

        emit ClaimMint(creatorContractAddress, instanceId);
    }

    /**
     * See {ILazyPayableClaimV2-mintBatch}.
     */
    function mintBatch(
        address creatorContractAddress,
        uint256 instanceId,
        uint16 mintCount,
        uint32[] calldata mintIndices,
        bytes32[][] calldata merkleProofs,
        address mintFor
    ) external payable override {
        Claim storage claim = _getClaim(creatorContractAddress, instanceId);

        if (claim.signingAddress != address(0)) revert ILazyPayableClaimCore.MustUseSignatureMinting();
        // Check totalMax
        claim.total += mintCount;
        if (((claim.totalMax != 0 && claim.total > claim.totalMax) || claim.total > MAX_UINT_24)) {
            revert ILazyPayableClaimCore.TooManyRequested();
        }

        // Validate mint
        _validateMint(
            creatorContractAddress,
            instanceId,
            claim.startDate,
            claim.endDate,
            claim.walletMax,
            claim.merkleRoot,
            mintCount,
            mintIndices,
            merkleProofs,
            mintFor
        );
        uint256 newMintIndex = claim.total - mintCount + 1;

        // Transfer funds
        _transferFunds(claim.erc20, claim.cost, claim.paymentReceiver, mintCount, claim.merkleRoot != "", true);

        _mintBatch(creatorContractAddress, instanceId, mintCount, msg.sender, newMintIndex, claim.contractVersion);
        emit ClaimMintBatch(creatorContractAddress, instanceId, mintCount);
    }

    /**
     * See {ILazyPayableClaimV2-mintProxy}.
     */
    function mintProxy(
        address creatorContractAddress,
        uint256 instanceId,
        uint16 mintCount,
        uint32[] calldata mintIndices,
        bytes32[][] calldata merkleProofs,
        address mintFor
    ) external payable override {
        Claim storage claim = _getClaim(creatorContractAddress, instanceId);

        if (claim.signingAddress != address(0)) revert ILazyPayableClaimCore.MustUseSignatureMinting();
        // Check totalMax
        claim.total += mintCount;
        if (((claim.totalMax != 0 && claim.total > claim.totalMax) || claim.total > MAX_UINT_24)) {
            revert ILazyPayableClaimCore.TooManyRequested();
        }

        // Validate mint
        _validateMintProxy(
            creatorContractAddress,
            instanceId,
            claim.startDate,
            claim.endDate,
            claim.walletMax,
            claim.merkleRoot,
            mintCount,
            mintIndices,
            merkleProofs,
            mintFor
        );
        uint256 newMintIndex = claim.total - mintCount + 1;

        // Transfer funds
        _transferFunds(claim.erc20, claim.cost, claim.paymentReceiver, mintCount, claim.merkleRoot != "", false);

        _mintBatch(creatorContractAddress, instanceId, mintCount, mintFor, newMintIndex, claim.contractVersion);
        emit ClaimMintProxy(creatorContractAddress, instanceId, mintCount, msg.sender, mintFor);
    }

    /**
     * See {ILazyPayableClaimV2-mintSignature}.
     */
    function mintSignature(
        address creatorContractAddress,
        uint256 instanceId,
        uint16 mintCount,
        bytes calldata signature,
        bytes32 message,
        bytes32 nonce,
        address mintFor,
        uint256 expiration
    ) external payable override {
        address creatorContractAddress = creatorContractAddress;
        uint16 mintCount = mintCount;
        Claim storage claim = _getClaim(creatorContractAddress, instanceId);

        // Check totalMax
        claim.total += mintCount;
        if (((claim.totalMax != 0 && claim.total > claim.totalMax) || claim.total > MAX_UINT_24)) {
            revert ILazyPayableClaimCore.TooManyRequested();
        }

        // Validate mint
        _validateMintSignature(claim.startDate, claim.endDate, signature, claim.signingAddress);
        _checkSignatureAndUpdate(
            creatorContractAddress,
            instanceId,
            signature,
            message,
            nonce,
            claim.signingAddress,
            mintFor,
            expiration,
            mintCount
        );
        uint256 newMintIndex = claim.total - mintCount + 1;

        // Transfer funds
        _transferFunds(claim.erc20, claim.cost, claim.paymentReceiver, mintCount, claim.merkleRoot != "", false);

        _mintBatch(creatorContractAddress, instanceId, mintCount, mintFor, newMintIndex, claim.contractVersion);
        emit ClaimMintSignature(creatorContractAddress, instanceId, mintCount, msg.sender, mintFor, nonce);
    }
}
