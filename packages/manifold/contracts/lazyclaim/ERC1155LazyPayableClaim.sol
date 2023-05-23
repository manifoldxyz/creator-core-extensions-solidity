// SPDX-License-Identifier: MIT
// solhint-disable reason-string
pragma solidity ^0.8.0;

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC1155CreatorCore.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/ICreatorExtensionTokenURI.sol";

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import "./LazyPayableClaim.sol";
import "./IERC1155LazyPayableClaim.sol";

/**
 * @title Lazy Payable Claim
 * @author manifold.xyz
 * @notice Lazy claim with optional whitelist ERC1155 tokens
 */
contract ERC1155LazyPayableClaim is IERC165, IERC1155LazyPayableClaim, ICreatorExtensionTokenURI, LazyPayableClaim {
    using Strings for uint256;

    // stores mapping from contractAddress/instanceId to the claim it represents
    // { contractAddress => { instanceId => Claim } }
    mapping(address => mapping(uint256 => Claim)) private _claims;

    // { contractAddress => { tokenId => { instanceId } }
    mapping(address => mapping(uint256 => uint256)) private _claimTokenIds;

    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, AdminControl) returns (bool) {
        return interfaceId == type(IERC1155LazyPayableClaim).interfaceId ||
            interfaceId == type(ILazyPayableClaim).interfaceId ||
            interfaceId == type(ICreatorExtensionTokenURI).interfaceId ||
            interfaceId == type(IAdminControl).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }

    constructor(address initialOwner, address delegationRegistry) LazyPayableClaim(initialOwner, delegationRegistry) {}

    /**
     * See {IERC1155LazyClaim-initializeClaim}.
     */
    function initializeClaim(
        address creatorContractAddress,
        uint256 instanceId,
        ClaimParameters calldata claimParameters
    ) external override creatorAdminRequired(creatorContractAddress) {
        // Revert if claim at instanceId already exists
        require(_claims[creatorContractAddress][instanceId].storageProtocol == StorageProtocol.INVALID, "Claim already initialized");

        // Sanity checks
        require(claimParameters.storageProtocol != StorageProtocol.INVALID, "Cannot initialize with invalid storage protocol");
        require(claimParameters.endDate == 0 || claimParameters.startDate < claimParameters.endDate, "Cannot have startDate greater than or equal to endDate");
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
            erc20: claimParameters.erc20
        });
        _claimTokenIds[creatorContractAddress][newTokenIds[0]] = instanceId;
        
        emit ClaimInitialized(creatorContractAddress, instanceId, msg.sender);
    }

    /**
     * See {IERC1155LazyClaim-updateClaim}.
     */
    function updateClaim(
        address creatorContractAddress,
        uint256 instanceId,
        ClaimParameters memory claimParameters
    ) external override creatorAdminRequired(creatorContractAddress) {
        Claim memory claim = _claims[creatorContractAddress][instanceId];
        require(claim.storageProtocol != StorageProtocol.INVALID, "Claim not initialized");
        require(claimParameters.storageProtocol != StorageProtocol.INVALID, "Cannot set invalid storage protocol");
        require(claimParameters.endDate == 0 || claimParameters.startDate < claimParameters.endDate, "Cannot have startDate greater than or equal to endDate");
        require(claimParameters.erc20 == claim.erc20, "Cannot change payment token");
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
            erc20: claimParameters.erc20
        });
        emit ClaimUpdated(creatorContractAddress, instanceId);
    }

    /**
     * See {IERC1155LazyClaim-updateTokenURIParams}.
     */
    function updateTokenURIParams(
        address creatorContractAddress, uint256 instanceId,
        StorageProtocol storageProtocol,
        string calldata location
    ) external override creatorAdminRequired(creatorContractAddress) {
        Claim storage claim = _claims[creatorContractAddress][instanceId];
        require(claim.storageProtocol != StorageProtocol.INVALID, "Claim not initialized");
        require(storageProtocol != StorageProtocol.INVALID, "Cannot set invalid storage protocol");

        claim.storageProtocol = storageProtocol;
        claim.location = location;
        emit ClaimUpdated(creatorContractAddress, instanceId);
    }

    /**
     * See {IERC1155LazyClaim-extendTokenURI}.
     */
    function extendTokenURI(
        address creatorContractAddress, uint256 instanceId,
        string calldata locationChunk
    ) external override creatorAdminRequired(creatorContractAddress) {
        Claim storage claim = _claims[creatorContractAddress][instanceId];
        require(claim.storageProtocol == StorageProtocol.NONE, "Invalid storage protocol");
        claim.location = string(abi.encodePacked(claim.location, locationChunk));
    }

    /**
     * See {IERC1155LazyClaim-getClaim}.
     */
    function getClaim(address creatorContractAddress, uint256 instanceId) public override view returns(Claim memory claim) {
        return _getClaim(creatorContractAddress, instanceId);
    }

    /**
     * See {IERC1155LazyClaim-getClaimForToken}.
     */
    function getClaimForToken(address creatorContractAddress, uint256 tokenId) external override view returns(uint256 instanceId, Claim memory claim) {
        instanceId = _claimTokenIds[creatorContractAddress][tokenId];
        claim = _getClaim(creatorContractAddress, instanceId);
    }

    function _getClaim(address creatorContractAddress, uint256 instanceId) private view returns(Claim storage claim) {
        claim = _claims[creatorContractAddress][instanceId];
        require(claim.storageProtocol != StorageProtocol.INVALID, "Claim not initialized");
    }

    /**
     * See {ILazyPayableClaim-checkMintIndex}.
     */
    function checkMintIndex(address creatorContractAddress, uint256 instanceId, uint32 mintIndex) external override view returns(bool) {
        Claim memory claim = getClaim(creatorContractAddress, instanceId);
        return _checkMintIndex(creatorContractAddress, instanceId, claim.merkleRoot, mintIndex);
    }

    /**
     * See {ILazyPayableClaim-checkMintIndices}.
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
     * See {ILazyPayableClaim-getTotalMints}.
     */
    function getTotalMints(address minter, address creatorContractAddress, uint256 instanceId) external override view returns(uint32) {
        Claim memory claim = getClaim(creatorContractAddress, instanceId);
        return _getTotalMints(claim.walletMax, minter, creatorContractAddress, instanceId);
    }

    /**
     * See {ILazyPayableClaim-mint}.
     */
    function mint(address creatorContractAddress, uint256 instanceId, uint32 mintIndex, bytes32[] calldata merkleProof, address mintFor) external payable override {
        Claim storage claim = _getClaim(creatorContractAddress, instanceId);

        // Check totalMax
        require(++claim.total <= claim.totalMax || claim.totalMax == 0, "Maximum tokens already minted for this claim");

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
     * See {ILazyPayableClaim-mintBatch}.
     */
    function mintBatch(address creatorContractAddress, uint256 instanceId, uint16 mintCount, uint32[] calldata mintIndices, bytes32[][] calldata merkleProofs, address mintFor) external payable override {
        Claim storage claim = _getClaim(creatorContractAddress, instanceId);

        // Check totalMax
        claim.total += mintCount;
        require(claim.totalMax == 0 || claim.total <= claim.totalMax, "Too many requested for this claim");

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
     * See {ILazyPayableClaim-mintProxy}.
     */
    function mintProxy(address creatorContractAddress, uint256 instanceId, uint16 mintCount, uint32[] calldata mintIndices, bytes32[][] calldata merkleProofs, address mintFor) external payable override {
        Claim storage claim = _getClaim(creatorContractAddress, instanceId);

        // Check totalMax
        claim.total += mintCount;
        require(claim.totalMax == 0 || claim.total <= claim.totalMax, "Too many requested for this claim");

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
     * See {IERC1155LazyPayableClaim-airdrop}.
     */
    function airdrop(address creatorContractAddress, uint256 instanceId, address[] calldata recipients,
        uint256[] calldata amounts) external override creatorAdminRequired(creatorContractAddress) {
        require(recipients.length == amounts.length, "Unequal number of recipients and amounts provided");

        // Fetch the claim
        Claim storage claim = _claims[creatorContractAddress][instanceId];

        uint256 totalAmount;
        for (uint256 i; i < amounts.length;) {
            totalAmount += amounts[i];
            unchecked{ ++i; }
        }
        require(totalAmount <= MAX_UINT_32, "Too many requested");
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
        uint224 tokenClaim = uint224(_claimTokenIds[creatorContractAddress][tokenId]);
        require(tokenClaim > 0, "Token does not exist");
        Claim memory claim = _claims[creatorContractAddress][tokenClaim];

        string memory prefix = "";
        if (claim.storageProtocol == StorageProtocol.ARWEAVE) {
            prefix = ARWEAVE_PREFIX;
        } else if (claim.storageProtocol == StorageProtocol.IPFS) {
            prefix = IPFS_PREFIX;
        }
        uri = string(abi.encodePacked(prefix, claim.location));
    }
}
