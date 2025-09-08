// SPDX-License-Identifier: MIT
// solhint-disable reason-string
pragma solidity ^0.8.0;

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC1155CreatorCore.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/ICreatorExtensionTokenURI.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./Serendipity.sol";
import "./IERC1155Serendipity.sol";

/**
 * @title ERC1155 Serendipity With Allowlist
 * @author manifold.xyz
 * @notice Extends ERC1155Serendipity with merkle-based allowlist functionality
 */
contract ERC1155SerendipityWithAllowlist is IERC165, IERC1155Serendipity, ICreatorExtensionTokenURI, Serendipity, ReentrancyGuard {
    using Strings for uint256;

    // Additional constants for merkle functionality
    uint256 public constant MINT_FEE_MERKLE = 690000000000000; // 0.00069 ETH
    uint256 private constant MINT_INDEX_BITMASK = 0xff;

    // Extended claim structure with allowlist fields
    struct ClaimWithAllowlist {
        StorageProtocol storageProtocol;
        uint32 total;
        uint32 totalMax;
        uint48 startDate;
        uint48 endDate;
        uint80 startingTokenId;
        uint8 tokenVariations;
        string location;
        address payable paymentReceiver;
        uint96 cost;
        address erc20;
        // Additional allowlist fields
        bytes32 merkleRoot;
        uint32 walletMax;
    }

    // Storage mappings following existing pattern
    mapping(address => mapping(uint256 => ClaimWithAllowlist)) private _claims;
    mapping(address => mapping(uint256 => uint256)) private _tokenInstances;
    
    // Merkle proof tracking (same pattern as LazyPayableClaimCore)
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) private _claimMintIndices;
    
    // Track mints per wallet for non-merkle claims
    mapping(address => mapping(uint256 => mapping(address => uint256))) private _mintsPerWallet;

    constructor(address initialOwner) Serendipity(initialOwner) {}

    function supportsInterface(bytes4 interfaceId) 
        public 
        view 
        virtual 
        override(IERC165, AdminControl) 
        returns (bool) 
    {
        return
            interfaceId == type(IERC1155Serendipity).interfaceId ||
            interfaceId == type(ISerendipity).interfaceId ||
            interfaceId == type(ICreatorExtensionTokenURI).interfaceId ||
            interfaceId == type(IAdminControl).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }

    /**
     * @notice Initialize a claim with optional merkle allowlist
     */
    function initializeClaim(
        address creatorContractAddress,
        uint256 instanceId,
        ClaimParameters calldata claimParameters
    ) external payable override creatorAdminRequired(creatorContractAddress) {
        // Initialize with empty merkle root and no wallet max (backward compatible)
        _initializeClaimWithAllowlist(
            creatorContractAddress,
            instanceId,
            claimParameters,
            bytes32(0),
            0
        );
    }

    /**
     * @notice Initialize a claim with merkle allowlist
     */
    function initializeClaimWithAllowlist(
        address creatorContractAddress,
        uint256 instanceId,
        ClaimParameters calldata claimParameters,
        bytes32 merkleRoot,
        uint32 walletMax
    ) external payable creatorAdminRequired(creatorContractAddress) {
        _initializeClaimWithAllowlist(
            creatorContractAddress,
            instanceId,
            claimParameters,
            merkleRoot,
            walletMax
        );
    }

    function _initializeClaimWithAllowlist(
        address creatorContractAddress,
        uint256 instanceId,
        ClaimParameters memory claimParameters,
        bytes32 merkleRoot,
        uint32 walletMax
    ) private {
        if (deprecated) revert ContractDeprecated();
        if (instanceId == 0 || instanceId > MAX_UINT_56) revert InvalidInstance();
        if (_claims[creatorContractAddress][instanceId].storageProtocol != StorageProtocol.INVALID)
            revert ClaimAlreadyInitialized();
        
        // Validate parameters
        if (claimParameters.storageProtocol == StorageProtocol.INVALID) revert InvalidStorageProtocol();
        if (claimParameters.endDate != 0 && claimParameters.startDate >= claimParameters.endDate)
            revert InvalidDate();
        if (claimParameters.totalMax > MAX_UINT_32) revert InvalidInput();
        if (claimParameters.tokenVariations > MAX_UINT_8) revert InvalidInput();
        if (claimParameters.cost > MAX_UINT_96) revert InvalidInput();

        // Create tokens
        address[] memory receivers = new address[](1);
        receivers[0] = msg.sender;
        uint256[] memory amounts = new uint256[](claimParameters.tokenVariations);
        string[] memory uris = new string[](claimParameters.tokenVariations);
        uint256[] memory newTokenIds = IERC1155CreatorCore(creatorContractAddress).mintExtensionNew(receivers, amounts, uris);

        if (newTokenIds[0] > MAX_UINT_80) revert InvalidStartingTokenId();

        // Store claim with allowlist fields
        _claims[creatorContractAddress][instanceId] = ClaimWithAllowlist({
            storageProtocol: claimParameters.storageProtocol,
            total: 0,
            totalMax: claimParameters.totalMax,
            startDate: claimParameters.startDate,
            endDate: claimParameters.endDate,
            startingTokenId: uint80(newTokenIds[0]),
            tokenVariations: claimParameters.tokenVariations,
            location: claimParameters.location,
            paymentReceiver: claimParameters.paymentReceiver,
            cost: claimParameters.cost,
            erc20: claimParameters.erc20,
            merkleRoot: merkleRoot,
            walletMax: walletMax
        });

        for (uint256 i; i < claimParameters.tokenVariations; ) {
            _tokenInstances[creatorContractAddress][newTokenIds[i]] = instanceId;
            unchecked {
                ++i;
            }
        }

        emit SerendipityClaimInitialized(creatorContractAddress, instanceId, msg.sender);
    }

    /**
     * @notice Update an existing claim
     */
    function updateClaim(
        address creatorContractAddress,
        uint256 instanceId,
        UpdateClaimParameters calldata updateClaimParameters
    ) external override creatorAdminRequired(creatorContractAddress) {
        ClaimWithAllowlist storage claim = _claims[creatorContractAddress][instanceId];
        if (claim.storageProtocol == StorageProtocol.INVALID) revert ClaimNotInitialized();
        
        // Update claim parameters
        if (updateClaimParameters.storageProtocol != StorageProtocol.INVALID) {
            claim.storageProtocol = updateClaimParameters.storageProtocol;
        }
        claim.paymentReceiver = updateClaimParameters.paymentReceiver;
        claim.totalMax = updateClaimParameters.totalMax;
        claim.startDate = updateClaimParameters.startDate;
        claim.endDate = updateClaimParameters.endDate;
        claim.cost = updateClaimParameters.cost;
        claim.location = updateClaimParameters.location;
        
        emit SerendipityClaimUpdated(creatorContractAddress, instanceId);
    }

    /**
     * @notice Update claim with new allowlist parameters
     */
    function updateClaimWithAllowlist(
        address creatorContractAddress,
        uint256 instanceId,
        ClaimParameters calldata claimParameters,
        bytes32 merkleRoot,
        uint32 walletMax
    ) external creatorAdminRequired(creatorContractAddress) {
        _updateClaimWithAllowlist(
            creatorContractAddress,
            instanceId,
            claimParameters,
            merkleRoot,
            walletMax
        );
    }

    function _updateClaimWithAllowlist(
        address creatorContractAddress,
        uint256 instanceId,
        ClaimParameters memory claimParameters,
        bytes32 merkleRoot,
        uint32 walletMax
    ) private {
        if (deprecated) revert ContractDeprecated();
        
        ClaimWithAllowlist storage claim = _claims[creatorContractAddress][instanceId];
        if (claim.storageProtocol == StorageProtocol.INVALID) revert ClaimNotInitialized();
        if (claimParameters.storageProtocol == StorageProtocol.INVALID) revert InvalidStorageProtocol();
        if (claimParameters.endDate != 0 && claimParameters.startDate >= claimParameters.endDate)
            revert InvalidDate();
        if (claimParameters.totalMax > MAX_UINT_32) revert InvalidInput();
        if (claimParameters.cost > MAX_UINT_96) revert InvalidInput();

        // Update claim
        claim.storageProtocol = claimParameters.storageProtocol;
        claim.totalMax = claimParameters.totalMax;
        claim.startDate = claimParameters.startDate;
        claim.endDate = claimParameters.endDate;
        claim.location = claimParameters.location;
        claim.cost = claimParameters.cost;
        claim.paymentReceiver = claimParameters.paymentReceiver;
        claim.erc20 = claimParameters.erc20;
        claim.merkleRoot = merkleRoot;
        claim.walletMax = walletMax;

        emit SerendipityClaimUpdated(creatorContractAddress, instanceId);
    }

    /**
     * @notice Basic mint reserve function (no merkle proof)
     */
    function mintReserve(address creatorContractAddress, uint256 instanceId, uint32 mintCount) external payable override {
        // For non-merkle mints, call the overloaded function with empty arrays
        uint32[] memory mintIndices = new uint32[](0);
        bytes32[][] memory merkleProofs = new bytes32[][](0);
        this.mintReserve{value: msg.value}(creatorContractAddress, instanceId, mintCount, mintIndices, merkleProofs, msg.sender);
    }

    /**
     * @notice Reserve mints with merkle proof validation
     */
    function mintReserve(
        address creatorContractAddress,
        uint256 instanceId,
        uint32 mintCount,
        uint32[] calldata mintIndices,
        bytes32[][] calldata merkleProofs,
        address mintFor
    ) external payable nonReentrant {
        ClaimWithAllowlist storage claim = _claims[creatorContractAddress][instanceId];
        
        // Validate claim is active
        if (claim.storageProtocol == StorageProtocol.INVALID) revert ClaimNotInitialized();
        if (claim.startDate > block.timestamp || (claim.endDate != 0 && claim.endDate < block.timestamp))
            revert ClaimInactive();
        
        // Check supply
        if (claim.totalMax != 0 && claim.total + mintCount > claim.totalMax) revert ClaimSoldOut();
        
        // Handle merkle validation if merkle root is set
        if (claim.merkleRoot != bytes32(0)) {
            if (mintIndices.length != mintCount || merkleProofs.length != mintCount)
                revert InvalidInput();
            
            for (uint256 i = 0; i < mintCount; i++) {
                _checkMerkleAndUpdate(
                    msg.sender,
                    creatorContractAddress,
                    instanceId,
                    claim.merkleRoot,
                    mintIndices[i],
                    merkleProofs[i],
                    mintFor
                );
            }
        } else if (claim.walletMax != 0) {
            // Non-merkle wallet limit
            uint256 newTotal = _mintsPerWallet[creatorContractAddress][instanceId][mintFor] + mintCount;
            if (newTotal > claim.walletMax) revert TooManyRequested();
            _mintsPerWallet[creatorContractAddress][instanceId][mintFor] = newTotal;
        }
        
        // Process payment
        uint256 totalCost = _processPayment(claim, mintCount);
        
        // Update claim totals
        claim.total += mintCount;
        
        // Track user mints
        UserMintDetails storage userMintDetails = _mintDetailsPerWallet[creatorContractAddress][instanceId][mintFor];
        userMintDetails.reservedCount += mintCount;
        
        emit SerendipityMintReserved(creatorContractAddress, instanceId, mintFor, mintCount);
        
        // Refund excess payment
        if (msg.value > totalCost) {
            Address.sendValue(payable(msg.sender), msg.value - totalCost);
        }
    }

    /**
     * @notice Deliver mints to recipients (called by backend with signature)
     */
    function deliverMints(ClaimMint[] calldata mints) external override {
        _validateSigner();
        for (uint256 i; i < mints.length; ) {
            ClaimMint calldata mintData = mints[i];
            ClaimWithAllowlist storage claim = _claims[mintData.creatorContractAddress][mintData.instanceId];
            if (claim.storageProtocol == StorageProtocol.INVALID) revert ClaimNotInitialized();
            
            address[] memory receivers = new address[](mintData.variationMints.length);
            uint256[] memory amounts = new uint256[](mintData.variationMints.length);
            uint256[] memory tokenIds = new uint256[](mintData.variationMints.length);

            for (uint256 j; j < mintData.variationMints.length; ) {
                VariationMint calldata variationMint = mintData.variationMints[j];
                if (variationMint.variationIndex > MAX_UINT_8) revert InvalidVariationIndex();
                uint8 variationIndex = variationMint.variationIndex;
                if (variationIndex > claim.tokenVariations || variationIndex < 1) revert InvalidVariationIndex();
                address recipient = variationMint.recipient;
                if (variationMint.amount > MAX_UINT_32) revert TooManyRequested();
                uint32 amount = variationMint.amount;
                UserMintDetails storage userMintDetails = _mintDetailsPerWallet[mintData.creatorContractAddress][
                    mintData.instanceId
                ][recipient];

                if (userMintDetails.deliveredCount + amount > userMintDetails.reservedCount)
                    revert CannotMintMoreThanReserved();
                if (claim.startingTokenId > MAX_UINT_80) revert InvalidStartingTokenId();
                tokenIds[j] = claim.startingTokenId + variationIndex - 1;
                amounts[j] = amount;
                receivers[j] = recipient;
                userMintDetails.deliveredCount += amount;
                
                emit SerendipityMintDelivered(mintData.creatorContractAddress, mintData.instanceId, recipient, amount);
                
                unchecked {
                    j++;
                }
            }

            IERC1155CreatorCore(mintData.creatorContractAddress).mintExtensionExisting(receivers, tokenIds, amounts);
            unchecked {
                i++;
            }
        }
    }

    /**
     * @notice Get claim details
     */
    function getClaim(address creatorContractAddress, uint256 instanceId)
        external
        view
        override
        returns (Claim memory)
    {
        ClaimWithAllowlist storage claim = _claims[creatorContractAddress][instanceId];
        // Return as standard Claim for backward compatibility
        return Claim({
            storageProtocol: claim.storageProtocol,
            total: claim.total,
            totalMax: claim.totalMax,
            startDate: claim.startDate,
            endDate: claim.endDate,
            startingTokenId: claim.startingTokenId,
            tokenVariations: claim.tokenVariations,
            location: claim.location,
            paymentReceiver: claim.paymentReceiver,
            cost: claim.cost,
            erc20: claim.erc20
        });
    }

    /**
     * @notice Get claim with allowlist details
     */
    function getClaimWithAllowlist(address creatorContractAddress, uint256 instanceId)
        external
        view
        returns (ClaimWithAllowlist memory)
    {
        return _claims[creatorContractAddress][instanceId];
    }

    /**
     * @notice Get claim for a token
     */
    function getClaimForToken(
        address creatorContractAddress,
        uint256 tokenId
    ) external view override returns (uint256 instanceId, Claim memory claim) {
        instanceId = _tokenInstances[creatorContractAddress][tokenId];
        ClaimWithAllowlist storage claimWithAllowlist = _claims[creatorContractAddress][instanceId];
        if (claimWithAllowlist.storageProtocol == StorageProtocol.INVALID) revert ClaimNotInitialized();
        
        // Convert ClaimWithAllowlist to Claim
        claim = Claim({
            storageProtocol: claimWithAllowlist.storageProtocol,
            total: claimWithAllowlist.total,
            totalMax: claimWithAllowlist.totalMax,
            startDate: claimWithAllowlist.startDate,
            endDate: claimWithAllowlist.endDate,
            startingTokenId: claimWithAllowlist.startingTokenId,
            tokenVariations: claimWithAllowlist.tokenVariations,
            location: claimWithAllowlist.location,
            paymentReceiver: claimWithAllowlist.paymentReceiver,
            cost: claimWithAllowlist.cost,
            erc20: claimWithAllowlist.erc20
        });
    }

    /**
     * @notice Get user mint details
     */
    function getUserMints(
        address minter,
        address creatorContractAddress,
        uint256 instanceId
    ) external view override returns (UserMintDetails memory)
    {
        return _mintDetailsPerWallet[creatorContractAddress][instanceId][minter];
    }
    
    /**
     * @notice Update token URI parameters
     */
    function updateTokenURIParams(
        address creatorContractAddress,
        uint256 instanceId,
        StorageProtocol storageProtocol,
        string calldata location
    ) external override creatorAdminRequired(creatorContractAddress) {
        ClaimWithAllowlist storage claim = _claims[creatorContractAddress][instanceId];
        if (claim.storageProtocol == StorageProtocol.INVALID) revert ClaimNotInitialized();
        if (storageProtocol == StorageProtocol.INVALID) revert InvalidStorageProtocol();
        claim.storageProtocol = storageProtocol;
        claim.location = location;
        emit SerendipityClaimUpdated(creatorContractAddress, instanceId);
    }

    /**
     * @notice Generate token URI
     */
    function tokenURI(address creatorContractAddress, uint256 tokenId) 
        external 
        view 
        override 
        returns (string memory) 
    {
        uint256 instanceId = _tokenInstances[creatorContractAddress][tokenId];
        if (instanceId == 0) revert InvalidToken();
        
        ClaimWithAllowlist storage claim = _claims[creatorContractAddress][instanceId];
        
        string memory prefix = "";
        if (claim.storageProtocol == StorageProtocol.ARWEAVE) {
            prefix = ARWEAVE_PREFIX;
        } else if (claim.storageProtocol == StorageProtocol.IPFS) {
            prefix = IPFS_PREFIX;
        }
        
        uint256 tokenNumber = tokenId - claim.startingTokenId + 1;
        return string(abi.encodePacked(prefix, claim.location, "/", tokenNumber.toString()));
    }

    /**
     * @notice Check merkle proof and update tracking (following LazyPayableClaimCore pattern)
     */
    function _checkMerkleAndUpdate(
        address sender,
        address creatorContractAddress,
        uint256 instanceId,
        bytes32 merkleRoot,
        uint32 mintIndex,
        bytes32[] memory merkleProof,
        address mintFor
    ) private {
        // Generate leaf
        bytes32 leaf = keccak256(abi.encodePacked(mintFor, mintIndex));
        
        // Verify proof
        if (!MerkleProof.verify(merkleProof, merkleRoot, leaf)) {
            revert InvalidMerkleProof();
        }
        
        // Check if mintIndex has been used (same pattern as LazyPayableClaimCore)
        uint256 claimMintIndex = mintIndex >> 8;
        uint256 claimMintTracking = _claimMintIndices[creatorContractAddress][instanceId][claimMintIndex];
        uint256 mintBitmask = 1 << (mintIndex & MINT_INDEX_BITMASK);
        
        if (mintBitmask & claimMintTracking != 0) {
            revert AlreadyMinted();
        }
        
        // Mark as used
        _claimMintIndices[creatorContractAddress][instanceId][claimMintIndex] = claimMintTracking | mintBitmask;
    }

    /**
     * @notice Process payment for minting
     */
    function _processPayment(ClaimWithAllowlist storage claim, uint32 mintCount) private returns (uint256) {
        uint256 creatorCost = claim.cost * mintCount;
        uint256 platformFee = (claim.merkleRoot != bytes32(0) ? MINT_FEE_MERKLE : MINT_FEE) * mintCount;
        uint256 totalCost = creatorCost + platformFee;
        
        if (claim.erc20 != address(0)) {
            // ERC20 payment for creator portion, ETH for platform fee
            if (msg.value < platformFee) revert InvalidPayment();
            if (creatorCost > 0) {
                IERC20(claim.erc20).transferFrom(msg.sender, claim.paymentReceiver, creatorCost);
            }
            return platformFee;
        } else {
            // ETH payment
            if (msg.value < totalCost) revert InvalidPayment();
            if (creatorCost > 0) {
                Address.sendValue(claim.paymentReceiver, creatorCost);
            }
            return totalCost;
        }
    }

    /**
     * @notice Recover signer from signature
     */
    function _recoverSigner(bytes32 message, bytes memory signature) private pure returns (address) {
        if (signature.length != 65) revert InvalidSignature();
        
        bytes32 r;
        bytes32 s;
        uint8 v;
        
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }
        
        if (v < 27) {
            v += 27;
        }
        
        if (v != 27 && v != 28) revert InvalidSignature();
        
        return ecrecover(keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", message)), v, r, s);
    }

    // Additional helper functions for testing compatibility
    function updateAllowlist(
        address creatorContractAddress,
        uint256 instanceId,
        bytes32 merkleRoot,
        uint32 walletMax
    ) external creatorAdminRequired(creatorContractAddress) {
        ClaimWithAllowlist storage claim = _claims[creatorContractAddress][instanceId];
        if (claim.storageProtocol == StorageProtocol.INVALID) revert ClaimNotInitialized();
        claim.merkleRoot = merkleRoot;
        claim.walletMax = walletMax;
        emit SerendipityClaimUpdated(creatorContractAddress, instanceId);
    }

    // Additional error definitions (not in base contracts)
    error InvalidMerkleProof();
    error AlreadyMinted();
    error InvalidToken();
    
    // Additional event for delivery tracking
    event SerendipityMintDelivered(
        address indexed creatorContract,
        uint256 indexed instanceId,
        address indexed recipient,
        uint32 amount
    );
}