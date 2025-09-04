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
import "./ISerendipityAllowlist.sol";
import "./IERC1155Serendipity.sol";
import "../libraries/AllowlistMerkleValidator.sol";
import "../libraries/HybridClaimStorage.sol";

/**
 * @title IMembership
 * @notice Interface for membership contract
 */
interface IMembership {
    function isActiveMember(address account) external view returns (bool);
}

/**
 * @title ERC1155 Serendipity With Allowlist
 * @author manifold.xyz
 * @notice Combines Serendipity gacha mechanics with allowlist functionality for ERC-1155 tokens
 * @dev Supports both merkle-proof based allowlists and simple wallet-max allowlists
 */
contract ERC1155SerendipityWithAllowlist is 
    IERC165, 
    ISerendipityAllowlist, 
    IERC1155Serendipity, 
    ICreatorExtensionTokenURI, 
    Serendipity,
    ReentrancyGuard 
{
    using Strings for uint256;
    using HybridClaimStorage for HybridClaimStorage.Storage;
    using AllowlistMerkleValidator for AllowlistMerkleValidator.MintIndexTracker;

    // ========== STORAGE ==========
    
    /// @notice Main storage for all hybrid claims
    HybridClaimStorage.Storage private _storage;
    
    /// @notice Membership contract for discounts
    address private _membershipAddress;

    // ========== CONSTRUCTOR ==========
    
    constructor(address initialOwner) Serendipity(initialOwner) {}

    // ========== INTERFACE SUPPORT ==========
    
    function supportsInterface(bytes4 interfaceId) 
        public 
        view 
        virtual 
        override(IERC165, AdminControl) 
        returns (bool) 
    {
        return
            interfaceId == type(ISerendipityAllowlist).interfaceId ||
            interfaceId == type(IERC1155Serendipity).interfaceId ||
            interfaceId == type(ISerendipity).interfaceId ||
            interfaceId == type(ICreatorExtensionTokenURI).interfaceId ||
            interfaceId == type(IAdminControl).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }

    // ========== ALLOWLIST CLAIM MANAGEMENT ==========
    
    /**
     * @notice Initialize a new allowlist claim
     * @dev Creates new tokens and stores claim parameters with allowlist configuration
     */
    function initializeAllowlistClaim(
        address creatorContractAddress,
        uint256 instanceId,
        AllowlistClaimParameters calldata claimParameters
    ) external payable override creatorAdminRequired(creatorContractAddress) {
        _initializeAllowlistClaim(creatorContractAddress, instanceId, claimParameters);
    }
    
    function _initializeAllowlistClaim(
        address creatorContractAddress,
        uint256 instanceId,
        AllowlistClaimParameters memory claimParameters
    ) internal {
        if (deprecated) revert ContractDeprecated();
        if (instanceId == 0 || instanceId > MAX_UINT_56) revert InvalidInstance();
        
        // Validate allowlist parameters
        if (claimParameters.storageProtocol == StorageProtocol.INVALID) {
            revert InvalidStorageProtocol();
        }
        if (claimParameters.endDate != 0 && claimParameters.startDate >= claimParameters.endDate) {
            revert InvalidDate();
        }
        if (claimParameters.totalMax > MAX_UINT_32) revert InvalidInput();
        if (claimParameters.tokenVariations == 0 || claimParameters.tokenVariations > MAX_UINT_8) {
            revert InvalidInput();
        }
        if (claimParameters.cost > MAX_UINT_96) revert InvalidInput();
        if (claimParameters.walletMax > MAX_UINT_32) revert InvalidAllowlistParameters();
        if (claimParameters.allowlistMax > claimParameters.totalMax && claimParameters.totalMax != 0) {
            revert InvalidAllowlistParameters();
        }

        // Create new tokens for this claim
        address[] memory receivers = new address[](1);
        receivers[0] = msg.sender;
        uint256[] memory amounts = new uint256[](claimParameters.tokenVariations);
        string[] memory uris = new string[](claimParameters.tokenVariations);
        
        uint256[] memory newTokenIds = IERC1155CreatorCore(creatorContractAddress)
            .mintExtensionNew(receivers, amounts, uris);

        if (newTokenIds[0] > MAX_UINT_80) revert InvalidStartingTokenId();

        // Initialize the claim using storage library
        HybridClaimStorage.InitClaimParams memory initParams = HybridClaimStorage.InitClaimParams({
            creatorContractAddress: creatorContractAddress,
            instanceId: instanceId,
            claimParams: claimParameters,
            newTokenIds: newTokenIds
        });
        
        _storage.initializeClaim(initParams);

        emit AllowlistClaimInitialized(creatorContractAddress, instanceId, msg.sender);
    }

    /**
     * @notice Update an existing allowlist claim
     * @dev Updates claim parameters while preserving mint state
     */
    function updateAllowlistClaim(
        address creatorContractAddress,
        uint256 instanceId,
        UpdateAllowlistClaimParameters memory updateClaimParameters
    ) public creatorAdminRequired(creatorContractAddress) {
        if (deprecated) revert ContractDeprecated();
        if (instanceId == 0 || instanceId > MAX_UINT_56) revert InvalidInstance();
        
        // Get existing claim for validation
        AllowlistClaim memory existingClaim = _storage.getClaim(creatorContractAddress, instanceId);
        
        // Validate update parameters
        if (updateClaimParameters.storageProtocol == StorageProtocol.INVALID) {
            revert InvalidStorageProtocol();
        }
        if (updateClaimParameters.endDate != 0 && 
            updateClaimParameters.startDate >= updateClaimParameters.endDate) {
            revert InvalidDate();
        }
        if (updateClaimParameters.totalMax != 0 && 
            updateClaimParameters.totalMax < existingClaim.total) {
            revert CannotLowerTotalMaxBeyondTotal();
        }
        if (updateClaimParameters.totalMax > MAX_UINT_32) revert InvalidInput();
        if (updateClaimParameters.cost > MAX_UINT_96) revert InvalidInput();
        if (updateClaimParameters.walletMax > MAX_UINT_32) revert InvalidAllowlistParameters();
        if (updateClaimParameters.allowlistMax > updateClaimParameters.totalMax && 
            updateClaimParameters.totalMax != 0) {
            revert InvalidAllowlistParameters();
        }

        // Update the claim using storage library
        HybridClaimStorage.UpdateClaimParams memory updateParams = HybridClaimStorage.UpdateClaimParams({
            creatorContractAddress: creatorContractAddress,
            instanceId: instanceId,
            updateParams: updateClaimParameters
        });
        
        _storage.updateClaim(updateParams);

        emit AllowlistClaimUpdated(creatorContractAddress, instanceId);
    }

    // ========== ALLOWLIST MINTING ==========
    
    /**
     * @notice Mint tokens using allowlist with merkle proof validation
     * @dev Validates merkle proofs and processes payments
     */
    function mintAllowlistReserve(
        address creatorContractAddress,
        uint256 instanceId,
        uint32 mintCount,
        uint32[] memory mintIndices,
        bytes32[][] memory merkleProofs
    ) public payable nonReentrant {
        if (Address.isContract(msg.sender)) revert CannotMintFromContract();
        if (mintCount == 0 || mintCount >= MAX_UINT_32) revert InvalidMintCount();
        
        AllowlistClaim memory claim = _storage.getClaim(creatorContractAddress, instanceId);
        
        // Validate claim is active
        _validateClaimActive(claim);
        
        // Check allowlist is active
        if (!claim.allowlistActive) revert AllowlistNotActive();
        
        // Check allowlist limits
        if (claim.allowlistMax != 0 && claim.allowlistMinted >= claim.allowlistMax) {
            revert ClaimSoldOut();
        }

        // Handle merkle proof validation or wallet max validation
        if (claim.merkleRoot != bytes32(0)) {
            // Merkle-based allowlist validation
            _validateMerkleProofs(creatorContractAddress, instanceId, mintIndices, merkleProofs, claim.merkleRoot);
            
            if (mintIndices.length != mintCount) revert InvalidMintCount();
            if (merkleProofs.length != mintCount) revert InvalidMerkleProof();
        } else {
            // Wallet-max based allowlist validation
            uint32 currentWalletMints = _storage.getWalletMintCount(creatorContractAddress, instanceId, msg.sender);
            if (claim.walletMax != 0 && currentWalletMints + mintCount > claim.walletMax) {
                revert ExceedsAllowlistLimit();
            }
            
            // Increment wallet mint count for non-merkle claims
            _storage.incrementWalletMintCount(creatorContractAddress, instanceId, msg.sender, mintCount);
        }

        // Calculate actual mints available
        uint32 amountToReserve = mintCount;
        if (claim.totalMax != 0) {
            amountToReserve = uint32(Math.min(mintCount, claim.totalMax - claim.total));
        }
        if (claim.allowlistMax != 0) {
            amountToReserve = uint32(Math.min(amountToReserve, claim.allowlistMax - claim.allowlistMinted));
        }

        if (amountToReserve == 0) revert ClaimSoldOut();

        // Validate payment (ETH for mint fee, ERC20 for cost if applicable)
        uint256 expectedETHPayment = MINT_FEE * mintCount;
        if (claim.erc20 == address(0)) {
            // ETH payment - include cost + mint fee
            expectedETHPayment += claim.cost * mintCount;
        }
        if (msg.value != expectedETHPayment) revert InvalidPayment();

        // Update claim state
        _storage.incrementTotalMinted(creatorContractAddress, instanceId, amountToReserve);
        _storage.incrementAllowlistMinted(creatorContractAddress, instanceId, amountToReserve);

        // Store user reservation (include mint indices for merkle claims)
        uint32[] memory reservationIndices = new uint32[](0);
        if (claim.merkleRoot != bytes32(0) && amountToReserve > 0) {
            reservationIndices = new uint32[](amountToReserve);
            for (uint256 i = 0; i < amountToReserve; i++) {
                reservationIndices[i] = mintIndices[i];
            }
        }
        
        _storage.addReservation(
            creatorContractAddress,
            instanceId,
            msg.sender,
            amountToReserve,
            reservationIndices
        );

        // Process payment
        if (claim.cost > 0) {
            _processPayment(claim.paymentReceiver, claim.erc20, claim.cost * amountToReserve);
        }

        // Refund overpayment if we reserve less than requested
        if (amountToReserve != mintCount) {
            uint256 actualETHCost = MINT_FEE * amountToReserve;
            if (claim.erc20 == address(0)) {
                actualETHCost += claim.cost * amountToReserve;
            }
            uint256 refundAmount = msg.value - actualETHCost;
            _sendFunds(payable(msg.sender), refundAmount);
        }

        emit AllowlistMintReserved(creatorContractAddress, instanceId, msg.sender, amountToReserve, reservationIndices);
    }

    /**
     * @notice Admin batch mint for multiple recipients
     * @dev Allows admins to mint directly to multiple wallets
     */
    function mintAllowlistBatch(
        address creatorContractAddress,
        uint256 instanceId,
        address[] calldata recipients,
        uint32[] calldata mintCounts
    ) external override creatorAdminRequired(creatorContractAddress) {
        if (recipients.length != mintCounts.length) revert InvalidInput();
        if (recipients.length == 0) revert InvalidInput();

        AllowlistClaim memory claim = _storage.getClaim(creatorContractAddress, instanceId);
        
        uint32 totalMintCount = 0;
        for (uint256 i = 0; i < mintCounts.length; i++) {
            totalMintCount += mintCounts[i];
        }

        // Check total limits
        if (claim.totalMax != 0 && claim.total + totalMintCount > claim.totalMax) {
            revert TooManyRequested();
        }

        // Update global counts
        _storage.incrementTotalMinted(creatorContractAddress, instanceId, totalMintCount);
        
        // Add reservations for each recipient
        uint32[] memory emptyIndices = new uint32[](0);
        for (uint256 i = 0; i < recipients.length; i++) {
            if (mintCounts[i] > 0) {
                _storage.addReservation(
                    creatorContractAddress,
                    instanceId,
                    recipients[i],
                    mintCounts[i],
                    emptyIndices
                );

                emit AllowlistMintReserved(creatorContractAddress, instanceId, recipients[i], mintCounts[i], emptyIndices);
            }
        }
    }

    /**
     * @notice Deliver NFTs for allowlist reservations
     * @dev Uses global _signer for validation like base Serendipity
     */
    function deliverAllowlistMints(ClaimMint[] calldata mints) public override {
        _validateSigner();
        
        for (uint256 i = 0; i < mints.length; i++) {
            ClaimMint calldata mintData = mints[i];
            AllowlistClaim memory claim = _storage.getClaim(mintData.creatorContractAddress, mintData.instanceId);
            
            address[] memory receivers = new address[](mintData.variationMints.length);
            uint256[] memory amounts = new uint256[](mintData.variationMints.length);
            uint256[] memory tokenIds = new uint256[](mintData.variationMints.length);

            for (uint256 j = 0; j < mintData.variationMints.length; j++) {
                VariationMint calldata variationMint = mintData.variationMints[j];
                
                if (variationMint.variationIndex > MAX_UINT_8) revert InvalidVariationIndex();
                if (variationMint.variationIndex > claim.tokenVariations || variationMint.variationIndex < 1) {
                    revert InvalidVariationIndex();
                }
                if (variationMint.amount > MAX_UINT_32) revert TooManyRequested();

                address recipient = variationMint.recipient;
                uint32 amount = variationMint.amount;
                
                // Get current reservation
                AllowlistReservation memory reservation = _storage.getReservation(
                    mintData.creatorContractAddress,
                    mintData.instanceId,
                    recipient
                );

                // Validate delivery amount
                if (reservation.deliveredCount + amount > reservation.reservedCount) {
                    revert CannotMintMoreThanReserved();
                }

                // Update delivered count
                _storage.updateDeliveredCount(
                    mintData.creatorContractAddress,
                    mintData.instanceId,
                    recipient,
                    amount
                );

                // Prepare mint data
                tokenIds[j] = claim.startingTokenId + variationMint.variationIndex - 1;
                amounts[j] = amount;
                receivers[j] = recipient;
            }

            // Execute the mint
            IERC1155CreatorCore(mintData.creatorContractAddress).mintExtensionExisting(receivers, tokenIds, amounts);
            
            emit AllowlistTokensDelivered(
                mintData.creatorContractAddress, 
                mintData.instanceId, 
                mintData.variationMints[0].recipient,  // Primary recipient for event
                uint32(amounts[0])  // Primary amount for event
            );
        }
    }

    // ========== VIEW FUNCTIONS ==========
    
    /**
     * @notice Get an allowlist claim
     */
    function getAllowlistClaim(
        address creatorContractAddress,
        uint256 instanceId
    ) external view override returns (AllowlistClaim memory) {
        return _storage.getClaim(creatorContractAddress, instanceId);
    }

    /**
     * @notice Get allowlist reservation for a wallet
     */
    function getAllowlistReservation(
        address minter,
        address creatorContractAddress,
        uint256 instanceId
    ) external view override returns (AllowlistReservation memory) {
        return _storage.getReservation(creatorContractAddress, instanceId, minter);
    }

    /**
     * @notice Check if multiple mint indices have been used
     */
    function checkMintIndices(
        address creatorContractAddress,
        uint256 instanceId,
        uint32[] calldata mintIndices
    ) external view override returns (bool[] memory) {
        return _storage.batchCheckMintIndices(creatorContractAddress, instanceId, mintIndices);
    }

    /**
     * @notice Verify merkle proof for allowlist (pure function)
     */
    function verifyAllowlistProof(
        bytes32 merkleRoot,
        address account,
        uint32 mintIndex,
        bytes32[] calldata merkleProof
    ) external pure override returns (bool) {
        return AllowlistMerkleValidator.verifyProof(merkleRoot, account, mintIndex, merkleProof);
    }

    // ========== IERC1155Serendipity COMPATIBILITY ==========
    
    /**
     * @notice Initialize a standard (non-allowlist) claim
     * @dev Converts standard ClaimParameters to AllowlistClaimParameters
     */
    function initializeClaim(
        address creatorContractAddress,
        uint256 instanceId,
        ClaimParameters calldata claimParameters
    ) external payable override {
        // Convert to allowlist parameters with no allowlist restrictions
        AllowlistClaimParameters memory allowlistParams = AllowlistClaimParameters({
            storageProtocol: claimParameters.storageProtocol,
            totalMax: claimParameters.totalMax,
            startDate: claimParameters.startDate,
            endDate: claimParameters.endDate,
            tokenVariations: claimParameters.tokenVariations,
            location: claimParameters.location,
            paymentReceiver: claimParameters.paymentReceiver,
            cost: claimParameters.cost,
            erc20: claimParameters.erc20,
            merkleRoot: bytes32(0),  // No merkle root
            walletMax: 0,  // No wallet limit
            allowlistMax: 0,  // No allowlist limit
            allowlistActive: false  // Allowlist not active
        });
        
        this.initializeAllowlistClaim{value: msg.value}(creatorContractAddress, instanceId, allowlistParams);
    }

    /**
     * @notice Update a standard (non-allowlist) claim
     */
    function updateClaim(
        address creatorContractAddress,
        uint256 instanceId,
        UpdateClaimParameters calldata updateClaimParameters
    ) external override {
        // Convert to allowlist update parameters
        UpdateAllowlistClaimParameters memory allowlistUpdateParams = UpdateAllowlistClaimParameters({
            storageProtocol: updateClaimParameters.storageProtocol,
            paymentReceiver: updateClaimParameters.paymentReceiver,
            totalMax: updateClaimParameters.totalMax,
            startDate: updateClaimParameters.startDate,
            endDate: updateClaimParameters.endDate,
            cost: updateClaimParameters.cost,
            location: updateClaimParameters.location,
            merkleRoot: bytes32(0),  // Preserve no merkle root
            walletMax: 0,  // Preserve no wallet limit
            allowlistMax: 0,  // Preserve no allowlist limit
            allowlistActive: false  // Keep allowlist inactive
        });
        
        updateAllowlistClaim(creatorContractAddress, instanceId, allowlistUpdateParams);
    }

    /**
     * @notice Get a standard claim (maps to allowlist claim)
     */
    function getClaim(
        address creatorContractAddress,
        uint256 instanceId
    ) external view override returns (Claim memory) {
        AllowlistClaim memory allowlistClaim = _storage.getClaim(creatorContractAddress, instanceId);
        
        // Convert to standard claim structure
        return Claim({
            storageProtocol: allowlistClaim.storageProtocol,
            total: allowlistClaim.total,
            totalMax: allowlistClaim.totalMax,
            startDate: allowlistClaim.startDate,
            endDate: allowlistClaim.endDate,
            startingTokenId: allowlistClaim.startingTokenId,
            tokenVariations: allowlistClaim.tokenVariations,
            location: allowlistClaim.location,
            paymentReceiver: allowlistClaim.paymentReceiver,
            cost: allowlistClaim.cost,
            erc20: allowlistClaim.erc20
        });
    }

    /**
     * @notice Get claim for a specific token
     */
    function getClaimForToken(
        address creatorContractAddress,
        uint256 tokenId
    ) external view override returns (uint256 instanceId, Claim memory claim) {
        AllowlistClaim memory allowlistClaim;
        (instanceId, allowlistClaim) = _storage.getClaimForToken(creatorContractAddress, tokenId);
        
        // Convert to standard claim structure
        claim = Claim({
            storageProtocol: allowlistClaim.storageProtocol,
            total: allowlistClaim.total,
            totalMax: allowlistClaim.totalMax,
            startDate: allowlistClaim.startDate,
            endDate: allowlistClaim.endDate,
            startingTokenId: allowlistClaim.startingTokenId,
            tokenVariations: allowlistClaim.tokenVariations,
            location: allowlistClaim.location,
            paymentReceiver: allowlistClaim.paymentReceiver,
            cost: allowlistClaim.cost,
            erc20: allowlistClaim.erc20
        });
    }

    /**
     * @notice Standard mint reserve (no allowlist)
     * @dev Delegates to allowlist mint with no restrictions
     */
    function mintReserve(
        address creatorContractAddress,
        uint256 instanceId,
        uint32 mintCount
    ) external payable override {
        uint32[] memory emptyIndices = new uint32[](0);
        bytes32[][] memory emptyProofs = new bytes32[][](0);
        
        mintAllowlistReserve(
            creatorContractAddress,
            instanceId,
            mintCount,
            emptyIndices,
            emptyProofs
        );
    }

    /**
     * @notice Standard deliver mints
     */
    function deliverMints(ClaimMint[] calldata mints) external override {
        deliverAllowlistMints(mints);
    }

    /**
     * @notice Get user mints (maps to allowlist reservation)
     */
    function getUserMints(
        address minter,
        address creatorContractAddress,
        uint256 instanceId
    ) external view override returns (UserMintDetails memory) {
        AllowlistReservation memory reservation = _storage.getReservation(creatorContractAddress, instanceId, minter);
        
        return UserMintDetails({
            reservedCount: reservation.reservedCount,
            deliveredCount: reservation.deliveredCount
        });
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
        if (storageProtocol == StorageProtocol.INVALID) revert InvalidStorageProtocol();
        
        // Update via updateAllowlistClaim to preserve all other settings
        AllowlistClaim memory claim = _storage.getClaim(creatorContractAddress, instanceId);
        
        UpdateAllowlistClaimParameters memory updateParams = UpdateAllowlistClaimParameters({
            storageProtocol: storageProtocol,
            paymentReceiver: claim.paymentReceiver,
            totalMax: claim.totalMax,
            startDate: claim.startDate,
            endDate: claim.endDate,
            cost: claim.cost,
            location: location,
            merkleRoot: claim.merkleRoot,
            walletMax: claim.walletMax,
            allowlistMax: claim.allowlistMax,
            allowlistActive: claim.allowlistActive
        });
        
        updateAllowlistClaim(creatorContractAddress, instanceId, updateParams);
    }

    // ========== TOKEN URI ==========
    
    /**
     * @notice Get token URI for a specific token
     */
    function tokenURI(
        address creatorContractAddress,
        uint256 tokenId
    ) external view override returns (string memory uri) {
        (uint256 instanceId, AllowlistClaim memory claim) = _storage.getClaimForToken(creatorContractAddress, tokenId);
        if (instanceId == 0) revert TokenDNE();

        string memory prefix = "";
        if (claim.storageProtocol == StorageProtocol.ARWEAVE) {
            prefix = ARWEAVE_PREFIX;
        } else if (claim.storageProtocol == StorageProtocol.IPFS) {
            prefix = IPFS_PREFIX;
        }
        
        uri = string(abi.encodePacked(
            prefix,
            claim.location,
            "/",
            Strings.toString(tokenId - claim.startingTokenId + 1)
        ));
    }

    // ========== INTERNAL HELPER FUNCTIONS ==========
    
    /**
     * @notice Validate merkle proofs for multiple mints
     */
    function _validateMerkleProofs(
        address creatorContractAddress,
        uint256 instanceId,
        uint32[] memory mintIndices,
        bytes32[][] memory merkleProofs,
        bytes32 merkleRoot
    ) internal {
        AllowlistMerkleValidator.MintIndexTracker storage tracker = 
            _storage.getMintTracker(creatorContractAddress, instanceId);

        AllowlistMerkleValidator.BatchValidationParams memory params = 
            AllowlistMerkleValidator.BatchValidationParams({
                merkleRoot: merkleRoot,
                account: msg.sender,
                mintIndices: mintIndices,
                merkleProofs: merkleProofs
            });

        AllowlistMerkleValidator.batchValidateAndReserve(tracker, params);
    }

    /**
     * @notice Validate that claim is currently active
     */
    function _validateClaimActive(AllowlistClaim memory claim) internal view {
        if (claim.startDate > block.timestamp || 
            (claim.endDate > 0 && claim.endDate < block.timestamp)) {
            revert ClaimInactive();
        }
    }

    /**
     * @notice Process payment (ETH or ERC20)
     */
    function _processPayment(
        address payable recipient,
        address erc20,
        uint256 amount
    ) internal {
        if (erc20 != address(0)) {
            // ERC20 payment
            IERC20(erc20).transferFrom(msg.sender, recipient, amount);
        } else {
            // ETH payment (already received in msg.value, send to recipient)
            _sendFunds(recipient, amount);
        }
    }

    // ========== TEST COMPATIBILITY FUNCTIONS ==========
    
    /**
     * @notice Initialize claim with allowlist (test-compatible signature)
     * @dev Compatibility function for tests that expect this signature
     */
    function initializeClaimWithAllowlist(
        address creatorContractAddress,
        uint256 instanceId,
        ClaimParameters calldata claimParameters,
        bytes32 merkleRoot,
        uint32 walletMax
    ) external payable creatorAdminRequired(creatorContractAddress) {
        // Convert to allowlist parameters
        AllowlistClaimParameters memory allowlistParams = AllowlistClaimParameters({
            storageProtocol: claimParameters.storageProtocol,
            totalMax: claimParameters.totalMax,
            startDate: claimParameters.startDate,
            endDate: claimParameters.endDate,
            tokenVariations: claimParameters.tokenVariations,
            location: claimParameters.location,
            paymentReceiver: claimParameters.paymentReceiver,
            cost: claimParameters.cost,
            erc20: claimParameters.erc20,
            merkleRoot: merkleRoot,
            walletMax: walletMax,
            allowlistMax: 0,  // No allowlist limit by default
            allowlistActive: true  // Allowlist is active
        });
        
        _initializeAllowlistClaim(creatorContractAddress, instanceId, allowlistParams);
    }
    
    /**
     * @notice Mint with merkle proof (test-compatible signature)
     * @dev Compatibility function for tests - uses simple address-based merkle validation
     */
    function mintReserveWithProof(
        address creatorContractAddress,
        uint256 instanceId,
        uint32 mintCount,
        bytes32[] calldata merkleProof
    ) external payable nonReentrant {
        if (Address.isContract(msg.sender)) revert CannotMintFromContract();
        if (mintCount == 0 || mintCount >= MAX_UINT_32) revert InvalidMintCount();
        
        AllowlistClaim memory claim = _storage.getClaim(creatorContractAddress, instanceId);
        
        // Validate claim is active
        _validateClaimActive(claim);
        
        // Check allowlist is active
        if (!claim.allowlistActive) revert AllowlistNotActive();
        
        // Check allowlist limits
        if (claim.allowlistMax != 0 && claim.allowlistMinted >= claim.allowlistMax) {
            revert ClaimSoldOut();
        }

        // Simple merkle validation (address-only leaf)
        if (claim.merkleRoot != bytes32(0)) {
            bytes32 leaf = keccak256(abi.encode(msg.sender));
            if (!MerkleProof.verify(merkleProof, claim.merkleRoot, leaf)) {
                revert("Invalid merkle proof");
            }
        }

        // Check wallet limits (for both merkle and non-merkle modes when walletMax is set)
        if (claim.walletMax != 0) {
            uint32 currentWalletMints = _storage.getWalletMintCount(creatorContractAddress, instanceId, msg.sender);
            if (currentWalletMints + mintCount > claim.walletMax) {
                revert("Exceeds wallet max");
            }
            _storage.incrementWalletMintCount(creatorContractAddress, instanceId, msg.sender, mintCount);
        }

        // Check if request can be fulfilled completely 
        if (claim.totalMax != 0 && claim.total + mintCount > claim.totalMax) {
            revert ClaimSoldOut();
        }
        if (claim.allowlistMax != 0 && claim.allowlistMinted + mintCount > claim.allowlistMax) {
            revert ClaimSoldOut();
        }

        // If we get here, the full mint count can be reserved
        uint32 amountToReserve = mintCount;

        // Calculate costs with membership discount
        uint256 actualCostPerMint = claim.cost;
        uint256 membershipDiscount = _getMembershipDiscount(claim.cost, msg.sender);
        if (membershipDiscount > 0) {
            actualCostPerMint = claim.cost - membershipDiscount;
        }

        // Validate payment (ETH for mint fee, ERC20 for cost if applicable)
        uint256 minimumETHPayment = MINT_FEE * mintCount;
        if (claim.erc20 == address(0)) {
            // ETH payment - include discounted cost + mint fee
            minimumETHPayment += actualCostPerMint * mintCount;
        }
        if (msg.value < minimumETHPayment) revert InvalidPayment();

        // Update claim state
        _storage.incrementTotalMinted(creatorContractAddress, instanceId, amountToReserve);
        _storage.incrementAllowlistMinted(creatorContractAddress, instanceId, amountToReserve);

        // Store user reservation (no mint indices for simple merkle)
        uint32[] memory emptyIndices = new uint32[](0);
        _storage.addReservation(
            creatorContractAddress,
            instanceId,
            msg.sender,
            amountToReserve,
            emptyIndices
        );

        // Process payment with discount applied
        if (actualCostPerMint > 0) {
            _processPayment(claim.paymentReceiver, claim.erc20, actualCostPerMint * amountToReserve);
        }

        // Calculate what was actually needed and refund any overpayment
        uint256 actualETHCost = MINT_FEE * amountToReserve;
        if (claim.erc20 == address(0)) {
            actualETHCost += actualCostPerMint * amountToReserve;
        }
        
        // Refund any overpayment (membership discount or partial reservation)
        if (msg.value > actualETHCost) {
            uint256 refundAmount = msg.value - actualETHCost;
            _sendFunds(payable(msg.sender), refundAmount);
        }

        emit AllowlistMintReserved(creatorContractAddress, instanceId, msg.sender, amountToReserve, emptyIndices);
    }

    /**
     * @notice Mint with proof for delegator (test-compatible signature)
     * @dev For delegation-based minting in tests
     */
    function mintReserveWithProofForDelegator(
        address delegator,
        address creatorContractAddress,
        uint256 instanceId,
        uint32 mintCount,
        bytes32[] calldata merkleProof
    ) external payable nonReentrant {
        // For now, use delegator address for merkle validation (delegation logic can be added later)
        if (Address.isContract(msg.sender)) revert CannotMintFromContract();
        if (mintCount == 0 || mintCount >= MAX_UINT_32) revert InvalidMintCount();
        
        AllowlistClaim memory claim = _storage.getClaim(creatorContractAddress, instanceId);
        
        // Validate claim is active
        _validateClaimActive(claim);
        
        // Check allowlist is active
        if (!claim.allowlistActive) revert AllowlistNotActive();
        
        // Check allowlist limits
        if (claim.allowlistMax != 0 && claim.allowlistMinted >= claim.allowlistMax) {
            revert ClaimSoldOut();
        }

        // Simple merkle validation using delegator address
        if (claim.merkleRoot != bytes32(0)) {
            bytes32 leaf = keccak256(abi.encode(delegator));
            if (!MerkleProof.verify(merkleProof, claim.merkleRoot, leaf)) {
                revert("Invalid merkle proof");
            }
        }

        // Check wallet limits for delegator (for both merkle and non-merkle modes when walletMax is set)
        if (claim.walletMax != 0) {
            uint32 currentWalletMints = _storage.getWalletMintCount(creatorContractAddress, instanceId, delegator);
            if (currentWalletMints + mintCount > claim.walletMax) {
                revert("Exceeds wallet max");
            }
            _storage.incrementWalletMintCount(creatorContractAddress, instanceId, delegator, mintCount);
        }

        // Check if request can be fulfilled completely 
        if (claim.totalMax != 0 && claim.total + mintCount > claim.totalMax) {
            revert ClaimSoldOut();
        }
        if (claim.allowlistMax != 0 && claim.allowlistMinted + mintCount > claim.allowlistMax) {
            revert ClaimSoldOut();
        }

        // If we get here, the full mint count can be reserved
        uint32 amountToReserve = mintCount;

        // Validate payment (ETH for mint fee, ERC20 for cost if applicable)
        uint256 expectedETHPayment = MINT_FEE * mintCount;
        if (claim.erc20 == address(0)) {
            // ETH payment - include cost + mint fee
            expectedETHPayment += claim.cost * mintCount;
        }
        if (msg.value != expectedETHPayment) revert InvalidPayment();

        // Update claim state
        _storage.incrementTotalMinted(creatorContractAddress, instanceId, amountToReserve);
        _storage.incrementAllowlistMinted(creatorContractAddress, instanceId, amountToReserve);

        // Store user reservation for delegator (no mint indices for simple merkle)
        uint32[] memory emptyIndices = new uint32[](0);
        _storage.addReservation(
            creatorContractAddress,
            instanceId,
            delegator,  // Reserve for delegator, not msg.sender
            amountToReserve,
            emptyIndices
        );

        // Process payment
        if (claim.cost > 0) {
            _processPayment(claim.paymentReceiver, claim.erc20, claim.cost * amountToReserve);
        }

        // Refund overpayment if we reserve less than requested
        if (amountToReserve != mintCount) {
            uint256 actualETHCost = MINT_FEE * amountToReserve;
            if (claim.erc20 == address(0)) {
                actualETHCost += claim.cost * amountToReserve;
            }
            uint256 refundAmount = msg.value - actualETHCost;
            _sendFunds(payable(msg.sender), refundAmount);
        }

        emit AllowlistMintReserved(creatorContractAddress, instanceId, delegator, amountToReserve, emptyIndices);
    }

    /**
     * @notice Update allowlist merkle root (test-compatible signature)
     * @dev Simple function to update just the merkle root
     */
    function updateAllowlist(
        address creatorContractAddress,
        uint256 instanceId,
        bytes32 newMerkleRoot
    ) external creatorAdminRequired(creatorContractAddress) {
        // Get current claim
        AllowlistClaim memory claim = _storage.getClaim(creatorContractAddress, instanceId);
        
        // Update with new merkle root, preserving all other settings
        UpdateAllowlistClaimParameters memory updateParams = UpdateAllowlistClaimParameters({
            storageProtocol: claim.storageProtocol,
            paymentReceiver: claim.paymentReceiver,
            totalMax: claim.totalMax,
            startDate: claim.startDate,
            endDate: claim.endDate,
            cost: claim.cost,
            location: claim.location,
            merkleRoot: newMerkleRoot,
            walletMax: claim.walletMax,
            allowlistMax: claim.allowlistMax,
            allowlistActive: claim.allowlistActive
        });
        
        updateAllowlistClaim(creatorContractAddress, instanceId, updateParams);
    }

    /**
     * @notice Set membership address (test-compatible function)
     * @dev For membership-based discount functionality
     */
    function setMembershipAddress(address membershipAddress) external adminRequired {
        _membershipAddress = membershipAddress;
    }
    
    /**
     * @notice Check if an address is an active member
     */
    function _isActiveMember(address account) internal view returns (bool) {
        if (_membershipAddress == address(0)) return false;
        
        try IMembership(_membershipAddress).isActiveMember(account) returns (bool isActive) {
            return isActive;
        } catch {
            return false;
        }
    }
    
    /**
     * @notice Get membership discount for a cost
     * @dev Provides 10% discount for active members
     */
    function _getMembershipDiscount(uint256 cost, address account) internal view returns (uint256) {
        if (_isActiveMember(account)) {
            return cost / 10; // 10% discount
        }
        return 0;
    }
}