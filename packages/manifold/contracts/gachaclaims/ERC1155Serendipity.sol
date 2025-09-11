// SPDX-License-Identifier: MIT
// solhint-disable reason-string
pragma solidity ^0.8.0;

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC1155CreatorCore.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/ICreatorExtensionTokenURI.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./Serendipity.sol";
import "./IERC1155Serendipity.sol";
import "../libraries/delegation-registry/IDelegationRegistry.sol";
import "../libraries/delegation-registry/IDelegationRegistryV2.sol";

/**
 * @title ERC1155 Serendipity
 * @author manifold.xyz
 * @notice ERC1155Serendipity with three key enhancements:
 *         1. Optional merkle-based allowlist for access control (omit for open mints)
 *         2. Updatable platform fees (base and merkle-specific)
 *         3. Delegation registry support (V1 and V2) for hot/cold wallet patterns
 */
contract ERC1155Serendipity is IERC165, IERC1155Serendipity, ICreatorExtensionTokenURI, Serendipity, ReentrancyGuard {
    using Strings for uint256;

    // Fee variables (updatable by admin)
    uint256 private _mintFee = 500000000000000; // 0.0005 ETH default
    uint256 private _mintFeeMerkle = 690000000000000; // 0.00069 ETH default

    // Delegation registry addresses (immutable)
    address public immutable DELEGATION_REGISTRY;
    address public immutable DELEGATION_REGISTRY_V2;

    // Storage mappings following existing pattern
    mapping(address => mapping(uint256 => Claim)) private _claims;
    mapping(address => mapping(uint256 => uint256)) private _tokenInstances;
    
    // Track mints per wallet for wallet max validation
    mapping(address => mapping(uint256 => mapping(address => uint256))) private _mintsPerWallet;
    
    // ONLY USED FOR MERKLE MINTS: stores mapping from claim to indices minted to prevent proof reuse
    // { contractAddress => {instanceId => { instanceIdOffset => index } } }
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) private _claimMintIndices;
    
    uint256 private constant MINT_INDEX_BITMASK = 0xFF;

    constructor(
        address initialOwner,
        address delegationRegistry,
        address delegationRegistryV2
    ) Serendipity(initialOwner) {
        DELEGATION_REGISTRY = delegationRegistry;
        DELEGATION_REGISTRY_V2 = delegationRegistryV2;
    }

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
        if (deprecated) revert ContractDeprecated();
        if (instanceId == 0 || instanceId > MAX_UINT_56) revert ISerendipity.InvalidInstance();
        if (_claims[creatorContractAddress][instanceId].storageProtocol != StorageProtocol.INVALID)
            revert ClaimAlreadyInitialized();
        
        // Validate parameters
        if (claimParameters.storageProtocol == StorageProtocol.INVALID) revert InvalidStorageProtocol();
        if (claimParameters.endDate != 0 && claimParameters.startDate >= claimParameters.endDate)
            revert InvalidDate();
        if (claimParameters.totalMax > MAX_UINT_32) revert InvalidInput();
        if (claimParameters.tokenVariations > MAX_UINT_8) revert InvalidInput();
        if (claimParameters.cost > MAX_UINT_96) revert InvalidInput();
        if (claimParameters.walletMax > MAX_UINT_32) revert InvalidInput();

        // Create tokens
        address[] memory receivers = new address[](1);
        receivers[0] = msg.sender;
        uint256[] memory amounts = new uint256[](claimParameters.tokenVariations);
        string[] memory uris = new string[](claimParameters.tokenVariations);
        uint256[] memory newTokenIds = IERC1155CreatorCore(creatorContractAddress).mintExtensionNew(receivers, amounts, uris);

        if (newTokenIds[0] > MAX_UINT_80) revert InvalidStartingTokenId();

        // Store claim with allowlist fields
        _claims[creatorContractAddress][instanceId] = Claim({
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
            merkleRoot: claimParameters.merkleRoot,
            walletMax: claimParameters.walletMax
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
     * @notice Set the mint fees for claims
     * @param mintFee The base mint fee in wei
     * @param mintFeeMerkle The mint fee for merkle claims in wei
     */
    function setMintFees(uint256 mintFee, uint256 mintFeeMerkle) external override adminRequired {
        _mintFee = mintFee;
        _mintFeeMerkle = mintFeeMerkle;
        emit MintFeesUpdated(mintFee, mintFeeMerkle);
    }

    /**
     * @notice Get the current base mint fee
     */
    function getMintFee() external view override returns (uint256) {
        return _mintFee;
    }

    /**
     * @notice Get the current merkle mint fee
     */
    function getMintFeeMerkle() external view override returns (uint256) {
        return _mintFeeMerkle;
    }

    /**
     * @notice Update an existing claim with all parameters including allowlist
     */
    function updateClaim(
        address creatorContractAddress,
        uint256 instanceId,
        UpdateClaimParameters calldata updateClaimParameters
    ) external override creatorAdminRequired(creatorContractAddress) {
        if (deprecated) revert ContractDeprecated();
        
        Claim storage claim = _claims[creatorContractAddress][instanceId];
        if (claim.storageProtocol == StorageProtocol.INVALID) revert ClaimNotInitialized();
        if (updateClaimParameters.storageProtocol == StorageProtocol.INVALID) revert InvalidStorageProtocol();
        if (updateClaimParameters.endDate != 0 && updateClaimParameters.startDate >= updateClaimParameters.endDate)
            revert InvalidDate();
        if (updateClaimParameters.totalMax != 0 && updateClaimParameters.totalMax < claim.total) 
            revert CannotLowerTotalMaxBeyondTotal();
        if (updateClaimParameters.totalMax > MAX_UINT_32) revert InvalidInput();
        if (updateClaimParameters.cost > MAX_UINT_96) revert InvalidInput();
        if (updateClaimParameters.walletMax > MAX_UINT_32) revert InvalidInput();

        // Update all claim fields including allowlist
        claim.storageProtocol = updateClaimParameters.storageProtocol;
        claim.totalMax = updateClaimParameters.totalMax;
        claim.startDate = updateClaimParameters.startDate;
        claim.endDate = updateClaimParameters.endDate;
        claim.location = updateClaimParameters.location;
        claim.cost = updateClaimParameters.cost;
        claim.paymentReceiver = updateClaimParameters.paymentReceiver;
        claim.merkleRoot = updateClaimParameters.merkleRoot;
        claim.walletMax = updateClaimParameters.walletMax;

        emit SerendipityClaimUpdated(creatorContractAddress, instanceId);
    }

    /**
     * @notice Reserve mints with optional merkle proof validation and delegation support
     * @dev Contracts cannot mint directly (will revert with CannotMintFromContract)
     *      This restriction exists because during phase 2 delivery (deliverMints), we use
     *      safeTransferFrom which triggers onERC1155Received hooks on receiving contracts.
     *      These hooks could contain arbitrary logic with unpredictable gas costs that we
     *      cannot afford to pay for during the delivery phase. By restricting to EOAs only,
     *      we ensure predictable gas costs during delivery.
     * @dev Supports three minting patterns for EOAs:
     *      1. Direct minting: mintFor = address(0) or mintFor = msg.sender
     *      2. Delegated minting: mintFor != msg.sender (requires valid delegation via registry)
     *      3. Open minting: No merkleRoot set on claim (anyone can mint up to walletMax)
     * @dev IMPORTANT: Mints are always delivered to msg.sender regardless of mintFor value
     *      This avoids potential gas issues with complex contracts during delivery phase
     * @dev Automatically refunds excess ETH if the mint count is adjusted due to supply limits
     * @param creatorContractAddress The creator contract address
     * @param instanceId The claim instance ID
     * @param mintCount The number of tokens to mint (may be reduced if exceeds available supply)
     * @param mintIndices The mint indices for merkle claims (prevents proof reuse), empty for non-merkle
     * @param merkleProofs The merkle proofs for allowlist validation (empty for non-merkle)
     * @param mintFor The address on whose behalf to mint (for delegation validation):
     *                - address(0): direct mint (no delegation check)
     *                - msg.sender: direct mint (no delegation check)
     *                - other address: delegated mint (requires delegation from mintFor to msg.sender)
     *                NOTE: Regardless of mintFor, tokens are always delivered to msg.sender
     */
    function mintReserve(
        address creatorContractAddress,
        uint256 instanceId,
        uint16 mintCount,
        uint32[] calldata mintIndices,
        bytes32[][] calldata merkleProofs,
        address mintFor
    ) external payable override(IERC1155Serendipity, ISerendipity) nonReentrant {
        // Block contracts from minting to avoid unpredictable gas costs during delivery
        // When we deliver mints via safeTransferFrom, receiving contracts can execute
        // arbitrary logic in their onERC1155Received hooks, which we cannot afford to pay for
        if (Address.isContract(msg.sender)) revert ISerendipity.CannotMintFromContract();
        
        // Validate mint count
        if (mintCount == 0 || mintCount > MAX_UINT_32) revert ISerendipity.InvalidMintCount();
        
        Claim storage claim = _claims[creatorContractAddress][instanceId];
        
        // Validate claim is active
        if (claim.storageProtocol == StorageProtocol.INVALID) revert ClaimNotInitialized();
        if (claim.startDate > block.timestamp || (claim.endDate != 0 && claim.endDate < block.timestamp))
            revert ClaimInactive();
        
        // Check supply and adjust amount if necessary
        if (claim.totalMax != 0 && claim.total + mintCount > claim.totalMax) {
            // Check if already sold out
            if (claim.total == claim.totalMax) revert ClaimSoldOut();
            // Adjust mint count to available supply
            mintCount = uint16(claim.totalMax - claim.total);
        }
        
        // Determine merkle validation address
        address merkleAddress = mintFor;
        if (mintFor == address(0)) {
            merkleAddress = msg.sender;
        } else if (mintFor != msg.sender) {
            // Check delegation rights from mintFor to msg.sender
            _validateDelegation(msg.sender, mintFor);
        }
        
        // Always use msg.sender as the minter to avoid delivery to complex contracts
        address minter = msg.sender;
        
        // Validate mint based on merkle or wallet limits
        // Use merkleAddress for proof validation, minter for tracking
        _validateMintReserve(
            creatorContractAddress,
            instanceId,
            claim.walletMax,
            claim.merkleRoot,
            mintCount,
            mintIndices,
            merkleProofs,
            merkleAddress,
            minter
        );
        
        // Process payment for mint count
        uint256 totalCost = _processPayment(claim, mintCount);
        
        // Update claim totals
        claim.total += mintCount;
        
        // Track user mints for the actual minter
        UserMintDetails storage userMintDetails = _mintDetailsPerWallet[creatorContractAddress][instanceId][minter];
        userMintDetails.reservedCount += mintCount;
        
        emit SerendipityMintReserved(creatorContractAddress, instanceId, minter, mintCount);
        
        // Refund excess payment
        // This handles two scenarios:
        // 1. User overpaid for their intended mint count
        // 2. Mint count was automatically reduced due to supply limits
        // Uses OpenZeppelin's Address.sendValue for safe ETH transfer
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
            Claim storage claim = _claims[mintData.creatorContractAddress][mintData.instanceId];
            if (claim.storageProtocol == StorageProtocol.INVALID) revert ClaimNotInitialized();
            
            address[] memory receivers = new address[](mintData.variationMints.length);
            uint256[] memory amounts = new uint256[](mintData.variationMints.length);
            uint256[] memory tokenIds = new uint256[](mintData.variationMints.length);

            for (uint256 j; j < mintData.variationMints.length; ) {
                VariationMint calldata variationMint = mintData.variationMints[j];
                if (variationMint.variationIndex > MAX_UINT_8) revert ISerendipity.InvalidVariationIndex();
                uint8 variationIndex = variationMint.variationIndex;
                if (variationIndex > claim.tokenVariations || variationIndex < 1) revert ISerendipity.InvalidVariationIndex();
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
     * @notice Get claim details including allowlist parameters
     */
    function getClaim(address creatorContractAddress, uint256 instanceId)
        public
        view
        override
        returns (Claim memory)
    {
        return _getClaim(creatorContractAddress, instanceId);
    }

    /**
     * @notice Internal function to get claim details
     */
    function _getClaim(address creatorContractAddress, uint256 instanceId)
        private
        view
        returns (Claim storage claim)
    {
        claim = _claims[creatorContractAddress][instanceId];
        if (claim.storageProtocol == StorageProtocol.INVALID) revert ClaimNotInitialized();
    }

    /**
     * @notice Get claim for a token
     */
    function getClaimForToken(
        address creatorContractAddress,
        uint256 tokenId
    ) external view override returns (uint256 instanceId, Claim memory claim) {
        instanceId = _tokenInstances[creatorContractAddress][tokenId];
        claim = _getClaim(creatorContractAddress, instanceId);
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
     * @notice check if a mint index has been consumed or not (only for merkle claims)
     * 
     * @param creatorContractAddress    the address of the creator contract for the claim
     * @param instanceId                the claim instance for the creator contract
     * @param mintIndex                 the mint index to check
     * @return                          whether or not the mint index was consumed
     */
    function checkMintIndex(address creatorContractAddress, uint256 instanceId, uint32 mintIndex)
        external
        view
        returns (bool)
    {
        Claim memory claim = getClaim(creatorContractAddress, instanceId);
        return _checkMintIndex(creatorContractAddress, instanceId, claim.merkleRoot, mintIndex);
    }

    /**
     * @notice check if multiple mint indices has been consumed or not (only for merkle claims)
     *
     * @param creatorContractAddress    the address of the creator contract for the claim
     * @param instanceId                the claim instance for the creator contract
     * @param mintIndices               the mint indices to check
     * @return minted                   whether or not the mint indices were consumed
     */
    function checkMintIndices(address creatorContractAddress, uint256 instanceId, uint32[] calldata mintIndices)
        external
        view
        returns (bool[] memory minted)
    {
        Claim memory claim = getClaim(creatorContractAddress, instanceId);
        uint256 mintIndicesLength = mintIndices.length;
        minted = new bool[](mintIndices.length);
        for (uint256 i; i < mintIndicesLength;) {
            minted[i] = _checkMintIndex(creatorContractAddress, instanceId, claim.merkleRoot, mintIndices[i]);
            unchecked {
                ++i;
            }
        }
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
        Claim storage claim = _claims[creatorContractAddress][instanceId];
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
        
        Claim storage claim = _claims[creatorContractAddress][instanceId];
        
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
     * @notice Validate mint reserve based on merkle proofs or wallet limits
     */
    function _validateMintReserve(
        address creatorContractAddress,
        uint256 instanceId,
        uint32 walletMax,
        bytes32 merkleRoot,
        uint16 mintCount,
        uint32[] calldata mintIndices,
        bytes32[][] calldata merkleProofs,
        address merkleAddress,  // For merkle proof validation
        address minter          // For tracking (always msg.sender)
    ) private {
        if (merkleRoot != bytes32(0)) {
            // Merkle validation
            if (!(mintCount == mintIndices.length && mintCount == merkleProofs.length)) {
                revert InvalidInput();
            }
            
            // Validate each mint index
            for (uint256 i; i < mintCount;) {
                // Create leaf using merkleAddress (the delegate-from address) and mint index
                bytes32 leaf = keccak256(abi.encodePacked(merkleAddress, mintIndices[i]));
                
                // Verify merkle proof
                if (!MerkleProof.verify(merkleProofs[i], merkleRoot, leaf)) {
                    revert InvalidMerkleProof();
                }
                
                // Check and mark mint index as used
                _checkAndSetMintIndex(creatorContractAddress, instanceId, mintIndices[i]);
                
                unchecked {
                    ++i;
                }
            }
            
            // Check wallet max for merkle claims if set
            if (walletMax != 0) {
                uint256 newTotal = _mintsPerWallet[creatorContractAddress][instanceId][minter] + mintCount;
                if (newTotal > walletMax) revert TooManyRequested();
                _mintsPerWallet[creatorContractAddress][instanceId][minter] = newTotal;
            }
        } else {
            // Non-merkle validation - just check wallet max
            if (walletMax != 0) {
                uint256 newTotal = _mintsPerWallet[creatorContractAddress][instanceId][minter] + mintCount;
                if (newTotal > walletMax) revert TooManyRequested();
                _mintsPerWallet[creatorContractAddress][instanceId][minter] = newTotal;
            }
        }
    }

    /**
     * @notice Process payment for minting
     * @dev Calculates total cost based on claim settings and platform fees
     *      Supports both ETH and ERC20 payments (ERC20 for creator, ETH for platform)
     *      Returns the actual amount of ETH that should be deducted from msg.value
     * @param claim The claim data containing cost and payment settings
     * @param mintCount The number of tokens being minted
     * @return totalCost The total ETH amount that was required for this mint
     */
    function _processPayment(Claim storage claim, uint16 mintCount) private returns (uint256) {
        uint256 creatorCost = claim.cost * mintCount;
        uint256 platformFee = (claim.merkleRoot != bytes32(0) ? _mintFeeMerkle : _mintFee) * mintCount;
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
     * @notice Check and set mint index to prevent reuse
     */
    function _checkAndSetMintIndex(address creatorContractAddress, uint256 instanceId, uint32 mintIndex) private {
        uint256 claimMintIndex = mintIndex >> 8;
        uint256 claimMintTracking = _claimMintIndices[creatorContractAddress][instanceId][claimMintIndex];
        uint256 mintBitmask = 1 << (mintIndex & MINT_INDEX_BITMASK);
        if (mintBitmask & claimMintTracking != 0) revert InvalidMerkleProof(); // Already minted with this index
        _claimMintIndices[creatorContractAddress][instanceId][claimMintIndex] = claimMintTracking | mintBitmask;
    }

    /**
     * @notice Check if a mint index has been consumed (internal)
     */
    function _checkMintIndex(address creatorContractAddress, uint256 instanceId, bytes32 merkleRoot, uint32 mintIndex)
        internal
        view
        returns (bool)
    {
        uint256 claimMintIndex = mintIndex >> 8;
        require(merkleRoot != "", "Can only check merkle claims");
        uint256 claimMintTracking = _claimMintIndices[creatorContractAddress][instanceId][claimMintIndex];
        uint256 mintBitmask = 1 << (mintIndex & MINT_INDEX_BITMASK);
        return mintBitmask & claimMintTracking != 0;
    }

    /**
     * @notice Validate delegation rights between a delegate and vault
     * @dev Checks both V2 and V1 delegation registries for valid delegation
     *      V2 is checked first if available, then falls back to V1
     *      Delegation allows a hot wallet (delegate) to mint on behalf of a cold wallet (vault)
     * @param delegate The address attempting to perform the action (msg.sender)
     * @param vault The address on whose behalf the action is being performed (mintFor)
     */
    function _validateDelegation(address delegate, address vault) private view {
        bool isValid = false;
        
        // Check V2 delegation first (if available)
        if (DELEGATION_REGISTRY_V2 != address(0)) {
            try IDelegationRegistryV2(DELEGATION_REGISTRY_V2).checkDelegateForContract(
                delegate,
                vault,
                address(this),
                ""
            ) returns (bool valid) {
                isValid = valid;
            } catch {}
        }
        
        // If V2 didn't validate, check V1
        if (!isValid && DELEGATION_REGISTRY != address(0)) {
            try IDelegationRegistry(DELEGATION_REGISTRY).checkDelegateForContract(
                delegate,
                vault,
                address(this)
            ) returns (bool valid) {
                isValid = valid;
            } catch {}
        }
        
        if (!isValid) revert InvalidDelegate();
    }
}