// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC1155LazyPayableClaimCore.sol";
import "./LazyPayableClaim.sol";

/**
 * @title Lazy Payable Claim
 * @author manifold.xyz
 * @notice Lazy claim with optional whitelist ERC1155 tokens
 */
contract ERC1155LazyPayableClaim is ERC1155LazyPayableClaimCore, LazyPayableClaim {
    constructor(address initialOwner, address delegationRegistry, address delegationRegistryV2)
        LazyPayableClaim(initialOwner, delegationRegistry, delegationRegistryV2)
    {}

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC1155LazyPayableClaimCore, AdminControl)
        returns (bool)
    {
        return type(ILazyPayableClaim).interfaceId == interfaceId
            || ERC1155LazyPayableClaimCore.supportsInterface(interfaceId);
    }

    /**
     * See {ILazyPayableClaim-mint}.
     */
    function mint(
        address creatorContractAddress,
        uint256 instanceId,
        uint32 mintIndex,
        bytes32[] calldata merkleProof,
        address mintFor
    ) external payable override {
        Claim storage claim = _getClaim(creatorContractAddress, instanceId);

        if (claim.signingAddress != address(0)) revert MustUseSignatureMinting();
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
        address[] memory recipients = new address[](1);
        recipients[0] = msg.sender;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1;
        _mintClaim(creatorContractAddress, claim, recipients, amounts);

        emit ClaimMint(creatorContractAddress, instanceId);
    }

    /**
     * See {ILazyPayableClaim-mintBatch}.
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
        if ((claim.totalMax != 0 && claim.total > claim.totalMax)) revert ILazyPayableClaimCore.TooManyRequested();

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

        // Transfer funds
        _transferFunds(claim.erc20, claim.cost, claim.paymentReceiver, mintCount, claim.merkleRoot != "", true);

        // Do mint
        address[] memory recipients = new address[](1);
        recipients[0] = msg.sender;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = mintCount;
        _mintClaim(creatorContractAddress, claim, recipients, amounts);

        emit ClaimMintBatch(creatorContractAddress, instanceId, mintCount);
    }

    /**
     * See {ILazyPayableClaim-mintProxy}.
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
        if ((claim.totalMax != 0 && claim.total > claim.totalMax)) revert ILazyPayableClaimCore.TooManyRequested();

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

        // Transfer funds
        _transferFunds(claim.erc20, claim.cost, claim.paymentReceiver, mintCount, claim.merkleRoot != "", false);

        // Do mint
        address[] memory recipients = new address[](1);
        recipients[0] = mintFor;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = mintCount;
        _mintClaim(creatorContractAddress, claim, recipients, amounts);

        emit ClaimMintProxy(creatorContractAddress, instanceId, mintCount, msg.sender, mintFor);
    }

    /**
     * See {ILazyPayableClaim-mintSignature}.
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
        if ((claim.totalMax != 0 && claim.total > claim.totalMax)) revert ILazyPayableClaimCore.TooManyRequested();
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

        // Transfer funds
        _transferFunds(claim.erc20, claim.cost, claim.paymentReceiver, mintCount, claim.merkleRoot != "", false);

        // Do mint
        address[] memory recipients = new address[](1);
        recipients[0] = mintFor;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = mintCount;
        _mintClaim(creatorContractAddress, claim, recipients, amounts);

        emit ClaimMintSignature(creatorContractAddress, instanceId, mintCount, msg.sender, mintFor, nonce);
    }
}
