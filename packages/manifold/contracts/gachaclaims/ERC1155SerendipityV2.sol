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
import "./IERC1155SerendipityV2.sol";
import "../libraries/delegation-registry/IDelegationRegistry.sol";
import "../libraries/delegation-registry/IDelegationRegistryV2.sol";

/**
 * @title ERC1155 Serendipity V2
 * @author manifold.xyz
 * @notice Second version of ERC1155Serendipity with three key enhancements:
 *         1. Optional merkle-based allowlist for access control (omit for open mints)
 *         2. Updatable platform fees (base and merkle-specific)
 *         3. Delegation registry support (V1 and V2) for hot/cold wallet patterns
 */
contract ERC1155SerendipityV2 is IERC165, IERC1155SerendipityV2, ICreatorExtensionTokenURI, Serendipity, ReentrancyGuard {
    using Strings for uint256;

    // Fee variables (updatable by admin) - override parent MINT_FEE constant
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
            interfaceId == type(IERC1155SerendipityV2).interfaceId ||
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
    ) external payable creatorAdminRequired(creatorContractAddress) {
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
    function setMintFees(uint256 mintFee, uint256 mintFeeMerkle) external adminRequired {
        _mintFee = mintFee;
        _mintFeeMerkle = mintFeeMerkle;
        emit MintFeesUpdated(mintFee, mintFeeMerkle);
    }

    /**
     * @notice Get the current base mint fee
     */
    function getMintFee() external view returns (uint256) {
        return _mintFee;
    }

    /**
     * @notice Get the current merkle mint fee
     */
    function getMintFeeMerkle() external view returns (uint256) {
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
        if (updateClaimParameters.totalMax > MAX_UINT_32) revert InvalidInput();
        if (updateClaimParameters.cost > MAX_UINT_96) revert InvalidInput();

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
     * @param creatorContractAddress The creator contract address
     * @param instanceId The claim instance ID
     * @param mintCount The number of tokens to mint
     * @param merkleProof The merkle proof for allowlist validation
     * @param mintFor The address to mint for (when using delegation)
     */
    function mintReserve(
        address creatorContractAddress,
        uint256 instanceId,
        uint32 mintCount,
        bytes32[] calldata merkleProof,
        address mintFor
    ) external payable nonReentrant {
        _mintReserveInternal(creatorContractAddress, instanceId, mintCount, mintFor, merkleProof);
    }

    /**
     * @notice Reserve mints with merkle proof but no delegation
     */
    function mintReserve(
        address creatorContractAddress,
        uint256 instanceId,
        uint32 mintCount,
        bytes32[] calldata merkleProof
    ) external payable override nonReentrant {
        _mintReserveInternal(creatorContractAddress, instanceId, mintCount, address(0), merkleProof);
    }

    /**
     * @notice Reserve mints without merkle proof (implements base ISerendipity interface)
     */
    function mintReserve(address creatorContractAddress, uint256 instanceId, uint32 mintCount) external payable override nonReentrant {
        // Delegate to the full version with empty proof and no delegation
        bytes32[] memory emptyProof = new bytes32[](0);
        _mintReserveInternal(creatorContractAddress, instanceId, mintCount, address(0), emptyProof);
    }
    
    /**
     * @notice Internal mint reserve logic
     */
    function _mintReserveInternal(
        address creatorContractAddress,
        uint256 instanceId,
        uint32 mintCount,
        address mintFor,
        bytes32[] memory merkleProof
    ) private {
        // Check that contracts cannot mint
        if (Address.isContract(msg.sender)) revert ISerendipity.CannotMintFromContract();
        
        // Validate mint count
        if (mintCount == 0 || mintCount >= MAX_UINT_32) revert ISerendipity.InvalidMintCount();
        
        Claim storage claim = _claims[creatorContractAddress][instanceId];
        
        // Validate claim is active
        if (claim.storageProtocol == StorageProtocol.INVALID) revert ClaimNotInitialized();
        if (claim.startDate > block.timestamp || (claim.endDate != 0 && claim.endDate < block.timestamp))
            revert ClaimInactive();
        
        // Check supply
        if (claim.totalMax != 0 && claim.total + mintCount > claim.totalMax) revert ClaimSoldOut();
        
        // Determine the actual minter (handle delegation)
        address minter = mintFor;
        if (mintFor == address(0)) {
            minter = msg.sender;
        } else if (mintFor != msg.sender) {
            // Check delegation rights
            _validateDelegation(msg.sender, mintFor);
        }
        
        // Handle merkle validation if merkle root is set
        if (claim.merkleRoot != bytes32(0)) {
            // Verify merkle proof using the actual minter address
            bytes32 leaf = keccak256(abi.encodePacked(minter));
            if (!MerkleProof.verify(merkleProof, claim.merkleRoot, leaf)) {
                revert InvalidMerkleProof();
            }
            
            // Check wallet max for merkle claims
            if (claim.walletMax != 0) {
                uint256 newTotal = _mintsPerWallet[creatorContractAddress][instanceId][minter] + mintCount;
                if (newTotal > claim.walletMax) revert TooManyRequested();
                _mintsPerWallet[creatorContractAddress][instanceId][minter] = newTotal;
            }
        } else if (claim.walletMax != 0) {
            // Non-merkle wallet limit
            uint256 newTotal = _mintsPerWallet[creatorContractAddress][instanceId][minter] + mintCount;
            if (newTotal > claim.walletMax) revert TooManyRequested();
            _mintsPerWallet[creatorContractAddress][instanceId][minter] = newTotal;
        }
        
        // Process payment
        uint256 totalCost = _processPayment(claim, mintCount);
        
        // Update claim totals
        claim.total += mintCount;
        
        // Track user mints for the actual minter
        UserMintDetails storage userMintDetails = _mintDetailsPerWallet[creatorContractAddress][instanceId][minter];
        userMintDetails.reservedCount += mintCount;
        
        emit SerendipityMintReserved(creatorContractAddress, instanceId, minter, mintCount);
        
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
        external
        view
        returns (Claim memory)
    {
        return _claims[creatorContractAddress][instanceId];
    }

    /**
     * @notice Get claim for a token
     */
    function getClaimForToken(
        address creatorContractAddress,
        uint256 tokenId
    ) external view returns (uint256 instanceId, Claim memory claim) {
        instanceId = _tokenInstances[creatorContractAddress][tokenId];
        claim = _claims[creatorContractAddress][instanceId];
        if (claim.storageProtocol == StorageProtocol.INVALID) revert ClaimNotInitialized();
    }

    /**
     * @notice Get user mint details
     */
    function getUserMints(
        address minter,
        address creatorContractAddress,
        uint256 instanceId
    ) external view returns (UserMintDetails memory)
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
     * @notice Process payment for minting
     */
    function _processPayment(Claim storage claim, uint32 mintCount) private returns (uint256) {
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
     * @notice Validate delegation rights
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

    /**
     * @notice Recover signer from signature
     */
    function _recoverSigner(bytes32 message, bytes memory signature) private pure returns (address) {
        if (signature.length != 65) revert ISerendipity.InvalidSignature();
        
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
        
        if (v != 27 && v != 28) revert ISerendipity.InvalidSignature();
        
        return ecrecover(keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", message)), v, r, s);
    }
}