// SPDX-License-Identifier: MIT
// solhint-disable reason-string
pragma solidity ^0.8.0;

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC1155CreatorCore.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/ICreatorExtensionTokenURI.sol";

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import "./LazyPayableClaimV2.sol";
import "./IERC1155LazyPayableClaimV2.sol";
import "./IERC1155LazyPayableClaimMetadataV2.sol";

/**
 * @title Lazy Payable Claim
 * @author manifold.xyz
 * @notice Lazy claim with optional whitelist ERC1155 tokens
 */
contract ERC1155LazyPayableClaimV2 is IERC165, IERC1155LazyPayableClaimV2, ICreatorExtensionTokenURI, LazyPayableClaimV2 {
    using Strings for uint256;

    // stores mapping from contractAddress/instanceId to the claim it represents
    // { contractAddress => { instanceId => Claim } }
    mapping(address => mapping(uint256 => Claim)) private _claims;

    // { contractAddress => { tokenId => { instanceId } }
    mapping(address => mapping(uint256 => uint256)) private _claimTokenIds;

    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, AdminControl) returns (bool) {
        return interfaceId == type(IERC1155LazyPayableClaimV2).interfaceId ||
            interfaceId == type(ILazyPayableClaimV2).interfaceId ||
            interfaceId == type(ICreatorExtensionTokenURI).interfaceId ||
            interfaceId == type(IAdminControl).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }

    constructor(address initialOwner, address delegationRegistry, address delegationRegistryV2) LazyPayableClaimV2(initialOwner, delegationRegistry, delegationRegistryV2) {}

    /**
     * See {IERC1155LazyPayableClaimV2-initializeClaim}.
     */
    function initializeClaim(
        address creatorContractAddress,
        uint256 instanceId,
        ClaimParameters calldata claimParameters
    ) external override creatorAdminRequired(creatorContractAddress) {
        if (!active) revert ILazyPayableClaimV2.Inactive();
        // Revert if claim at instanceId already exists
        require(_claims[creatorContractAddress][instanceId].storageProtocol == StorageProtocol.INVALID, "Claim already initialized");

        // Sanity checks
        if (claimParameters.storageProtocol == StorageProtocol.INVALID) revert ILazyPayableClaimV2.InvalidStorageProtocol();
        if (claimParameters.storageProtocol == StorageProtocol.ADDRESS && bytes(claimParameters.location).length != 20) revert ILazyPayableClaimV2.InvalidStorageProtocol();
        if (claimParameters.endDate != 0 && claimParameters.startDate >= claimParameters.endDate) revert ILazyPayableClaimV2.InvalidStartDate();
        require(claimParameters.merkleRoot == "" || claimParameters.walletMax == 0, "Cannot provide both walletMax and merkleRoot");

        address[] memory receivers = new address[](1);
        receivers[0] = msg.sender;
        string[] memory uris = new string[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory newTokenIds = IERC1155CreatorCore(creatorContractAddress).mintExtensionNew(receivers, amounts, uris);

         // Create the claim
        _claims[creatorContractAddress][instanceId] = Claim({
            total: 0,
            totalMax: claimParameters.totalMax,
            walletMax: claimParameters.walletMax,
            startDate: claimParameters.startDate,
            endDate: claimParameters.endDate,
            storageProtocol: claimParameters.storageProtocol,
            merkleRoot: claimParameters.merkleRoot,
            location: claimParameters.location,
            tokenId: newTokenIds[0],
            cost: claimParameters.cost,
            paymentReceiver: claimParameters.paymentReceiver,
            erc20: claimParameters.erc20,
            signingAddress: claimParameters.signingAddress
        });
        _claimTokenIds[creatorContractAddress][newTokenIds[0]] = instanceId;
        
        emit ClaimInitialized(creatorContractAddress, instanceId, msg.sender);
    }

    /**
     * See {IERC1155LazyPayableClaimV2-updateClaim}.
     */
    function updateClaim(
        address creatorContractAddress,
        uint256 instanceId,
        ClaimParameters memory claimParameters
    ) external override creatorAdminRequired(creatorContractAddress) {
        Claim memory claim = _getClaim(creatorContractAddress, instanceId);
        if (claimParameters.storageProtocol == StorageProtocol.INVALID) revert ILazyPayableClaimV2.InvalidStorageProtocol();
        if (claimParameters.storageProtocol == StorageProtocol.ADDRESS && bytes(claimParameters.location).length != 20) revert ILazyPayableClaimV2.InvalidStorageProtocol();
        if (claimParameters.endDate != 0 && claimParameters.startDate >= claimParameters.endDate) revert ILazyPayableClaimV2.InvalidStartDate();
        if (claimParameters.erc20 != claim.erc20) revert ILazyPayableClaimV2.CannotChangePaymentToken();
        if (claimParameters.totalMax != 0 && claim.total > claimParameters.totalMax) {
            claimParameters.totalMax = claim.total;
        }

        // Overwrite the existing claim
        _claims[creatorContractAddress][instanceId] = Claim({
            total: claim.total,
            totalMax: claimParameters.totalMax,
            walletMax: claimParameters.walletMax,
            startDate: claimParameters.startDate,
            endDate: claimParameters.endDate,
            storageProtocol: claimParameters.storageProtocol,
            merkleRoot: claimParameters.merkleRoot,
            location: claimParameters.location,
            tokenId: claim.tokenId,
            cost: claimParameters.cost,
            paymentReceiver: claimParameters.paymentReceiver,
            erc20: claimParameters.erc20,
            signingAddress: claimParameters.signingAddress
        });
        emit ClaimUpdated(creatorContractAddress, instanceId);
    }

    /**
     * See {IERC1155LazyPayableClaimV2-updateTokenURIParams}.
     */
    function updateTokenURIParams(
        address creatorContractAddress, uint256 instanceId,
        StorageProtocol storageProtocol,
        string calldata location
    ) external override creatorAdminRequired(creatorContractAddress) {
        Claim storage claim = _getClaim(creatorContractAddress, instanceId);
        if (storageProtocol == StorageProtocol.INVALID) revert ILazyPayableClaimV2.InvalidStorageProtocol();
        if (storageProtocol == StorageProtocol.ADDRESS && bytes(location).length != 20) revert ILazyPayableClaimV2.InvalidStorageProtocol();

        claim.storageProtocol = storageProtocol;
        claim.location = location;
        emit ClaimUpdated(creatorContractAddress, instanceId);
    }

    /**
     * See {IERC1155LazyPayableClaimV2-extendTokenURI}.
     */
    function extendTokenURI(
        address creatorContractAddress, uint256 instanceId,
        string calldata locationChunk
    ) external override creatorAdminRequired(creatorContractAddress) {
        Claim storage claim = _getClaim(creatorContractAddress, instanceId);
        if (claim.storageProtocol != StorageProtocol.NONE) revert ILazyPayableClaimV2.InvalidStorageProtocol();
        claim.location = string(abi.encodePacked(claim.location, locationChunk));
    }

    /**
     * See {IERC1155LazyPayableClaimV2-getClaim}.
     */
    function getClaim(address creatorContractAddress, uint256 instanceId) public override view returns(Claim memory claim) {
        return _getClaim(creatorContractAddress, instanceId);
    }

    /**
     * See {IERC1155LazyPayableClaimV2-getClaimForToken}.
     */
    function getClaimForToken(address creatorContractAddress, uint256 tokenId) external override view returns(uint256 instanceId, Claim memory claim) {
        instanceId = _claimTokenIds[creatorContractAddress][tokenId];
        claim = _getClaim(creatorContractAddress, instanceId);
    }

    function _getClaim(address creatorContractAddress, uint256 instanceId) private view returns(Claim storage claim) {
        claim = _claims[creatorContractAddress][instanceId];
        if (claim.storageProtocol == StorageProtocol.INVALID) revert ILazyPayableClaimV2.ClaimNotInitialized();
    }

    /**
     * See {ILazyPayableClaimV2-checkMintIndex}.
     */
    function checkMintIndex(address creatorContractAddress, uint256 instanceId, uint32 mintIndex) external override view returns(bool) {
        Claim memory claim = getClaim(creatorContractAddress, instanceId);
        return _checkMintIndex(creatorContractAddress, instanceId, claim.merkleRoot, mintIndex);
    }

    /**
     * See {ILazyPayableClaimV2-checkMintIndices}.
     */
    function checkMintIndices(address creatorContractAddress, uint256 instanceId, uint32[] calldata mintIndices) external override view returns(bool[] memory minted) {
        Claim memory claim = getClaim(creatorContractAddress, instanceId);
        uint256 mintIndicesLength = mintIndices.length;
        minted = new bool[](mintIndices.length);
        for (uint256 i; i < mintIndicesLength;) {
            minted[i] = _checkMintIndex(creatorContractAddress, instanceId, claim.merkleRoot, mintIndices[i]);
            unchecked{ ++i; }
        }
    }

    /**
     * See {ILazyPayableClaimV2-getTotalMints}.
     */
    function getTotalMints(address minter, address creatorContractAddress, uint256 instanceId) external override view returns(uint32) {
        Claim memory claim = getClaim(creatorContractAddress, instanceId);
        return _getTotalMints(claim.walletMax, minter, creatorContractAddress, instanceId);
    }

    /**
     * See {ILazyPayableClaimV2-mint}.
     */
    function mint(address creatorContractAddress, uint256 instanceId, uint32 mintIndex, bytes32[] calldata merkleProof, address mintFor) external payable override {
        Claim storage claim = _getClaim(creatorContractAddress, instanceId);

        if (claim.signingAddress != address(0)) revert MustUseSignatureMinting();
        // Check totalMax
        if (((++claim.total > claim.totalMax && claim.totalMax != 0) || claim.total > MAX_UINT_24)) revert ILazyPayableClaimV2.TooManyRequested();

        // Validate mint
        _validateMint(creatorContractAddress, instanceId, claim.startDate, claim.endDate, claim.walletMax, claim.merkleRoot, mintIndex, merkleProof, mintFor);

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
     * See {ILazyPayableClaimV2-mintBatch}.
     */
    function mintBatch(address creatorContractAddress, uint256 instanceId, uint16 mintCount, uint32[] calldata mintIndices, bytes32[][] calldata merkleProofs, address mintFor) external payable override {
        Claim storage claim = _getClaim(creatorContractAddress, instanceId);

        if (claim.signingAddress != address(0)) revert ILazyPayableClaimV2.MustUseSignatureMinting();
        // Check totalMax
        claim.total += mintCount;
        if ((claim.totalMax != 0 && claim.total > claim.totalMax)) revert ILazyPayableClaimV2.TooManyRequested();

        // Validate mint
        _validateMint(creatorContractAddress, instanceId, claim.startDate, claim.endDate, claim.walletMax, claim.merkleRoot, mintCount, mintIndices, merkleProofs, mintFor);

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
     * See {ILazyPayableClaimV2-mintProxy}.
     */
    function mintProxy(address creatorContractAddress, uint256 instanceId, uint16 mintCount, uint32[] calldata mintIndices, bytes32[][] calldata merkleProofs, address mintFor) external payable override {
        Claim storage claim = _getClaim(creatorContractAddress, instanceId);

        if (claim.signingAddress != address(0)) revert ILazyPayableClaimV2.MustUseSignatureMinting();
        // Check totalMax
        claim.total += mintCount;
        if ((claim.totalMax != 0 && claim.total > claim.totalMax)) revert ILazyPayableClaimV2.TooManyRequested();

        // Validate mint
        _validateMintProxy(creatorContractAddress, instanceId, claim.startDate, claim.endDate, claim.walletMax, claim.merkleRoot, mintCount, mintIndices, merkleProofs, mintFor);

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
     * See {ILazyPayableClaimV2-mintSignature}.
     */
    function mintSignature(address creatorContractAddress, uint256 instanceId, uint16 mintCount, bytes calldata signature, bytes32 message, bytes32 nonce, address mintFor, uint256 expiration) external payable override {
        address creatorContractAddress = creatorContractAddress;
        uint16 mintCount = mintCount;
        Claim storage claim = _getClaim(creatorContractAddress, instanceId);

        // Check totalMax
        claim.total += mintCount;
        if ((claim.totalMax != 0 && claim.total > claim.totalMax)) revert ILazyPayableClaimV2.TooManyRequested();
        // Validate mint
        _validateMintSignature(claim.startDate, claim.endDate, signature, claim.signingAddress);
        _checkSignatureAndUpdate(creatorContractAddress, instanceId, signature, message, nonce, claim.signingAddress, mintFor, expiration, mintCount);

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

    /**
     * See {IERC1155LazyPayableClaimV2-airdrop}.
     */
    function airdrop(address creatorContractAddress, uint256 instanceId, address[] calldata recipients,
        uint256[] calldata amounts) external override creatorAdminRequired(creatorContractAddress) {
        if (recipients.length != amounts.length) revert ILazyPayableClaimV2.InvalidAirdrop();

        // Fetch the claim
        Claim storage claim = _getClaim(creatorContractAddress, instanceId);

        uint256 totalAmount;
        for (uint256 i; i < amounts.length;) {
            totalAmount += amounts[i];
            unchecked{ ++i; }
        }
        if (totalAmount > MAX_UINT_32) revert TooManyRequested();
        claim.total += uint32(totalAmount);
        if (claim.totalMax != 0 && claim.total > claim.totalMax) {
            claim.totalMax = claim.total;
        }

        // Airdrop the tokens
        _mintClaim(creatorContractAddress, claim, recipients, amounts);
    }

    /**
     * Mint a claim
     */
    function _mintClaim(address creatorContractAddress, Claim storage claim, address[] memory recipients, uint256[] memory amounts) private {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = claim.tokenId;
        IERC1155CreatorCore(creatorContractAddress).mintExtensionExisting(recipients, tokenIds, amounts);
    }

    /**
     * See {ICreatorExtensionTokenURI-tokenURI}.
     */
    function tokenURI(address creatorContractAddress, uint256 tokenId) external override view returns(string memory uri) {
        uint224 instanceId = uint224(_claimTokenIds[creatorContractAddress][tokenId]);
        if (instanceId == 0) revert ILazyPayableClaimV2.TokenDNE();
        Claim memory claim = _claims[creatorContractAddress][instanceId];

        if (claim.storageProtocol == StorageProtocol.ADDRESS) {
            return IERC1155LazyPayableClaimMetadataV2(_bytesToAddress(bytes(claim.location))).tokenURI(creatorContractAddress, tokenId, instanceId);
        }

        string memory prefix = "";
        if (claim.storageProtocol == StorageProtocol.ARWEAVE) {
            prefix = ARWEAVE_PREFIX;
        } else if (claim.storageProtocol == StorageProtocol.IPFS) {
            prefix = IPFS_PREFIX;
        }
        uri = string(abi.encodePacked(prefix, claim.location));
    }
}