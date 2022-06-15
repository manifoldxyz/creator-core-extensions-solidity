// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC721CreatorCore.sol";
import "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/ICreatorExtensionTokenURI.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/interfaces/IERC165.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "./IERC721LazyClaim.sol";

/**
 * @title Lazy Claim
 * @author manifold.xyz
 * @notice Lazy claim with optional whitelist ERC721 tokens
 */
contract ERC721LazyClaim is IERC165, IERC721LazyClaim, ICreatorExtensionTokenURI, ReentrancyGuard {
    using Strings for uint256;

    string private constant ARWEAVE_PREFIX = "https://arweave.net/";
    string private constant IPFS_PREFIX = "ipfs://";
    uint256 private constant BITMASK = 0xFF;

    // stores the number of claim instances made by a given creator contract
    // used to determine the next claimIndex for a creator contract
    // { contractAddress => claimCount }
    mapping(address => uint224) private _claimCounts;

    // stores mapping from tokenId to the claim it represents
    // { contractAddress => { tokenId => Claim } }
    mapping(address => mapping(uint256 => Claim)) private _claims;

    // ONLY USED FOR NON-MERKLE MINTS: stores the number of tokens minted per wallet per claim, in order to limit maximum
    // { contractAddress => { claimIndex => { walletAddress => walletMints } } }
    mapping(address => mapping(uint256 => mapping(address => uint256))) private _mintsPerWallet;

    // ONLY USED FOR MERKLE MINTS: stores mapping from claim to indices minted
    // { contractAddress => {claimIndex => { claimIndexOffset => index } } }
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) private _claimMintIndices;

    struct TokenClaim {
        uint224 claimIndex;
        uint32 mintIndex;
    }
    // stores which tokenId corresponds to which claimIndex, used to generate token uris
    // { contractAddress => { tokenId => TokenClaim } }
    mapping(address => mapping(uint256 => TokenClaim)) private _tokenClaims;

    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165) returns (bool) {
        return interfaceId == type(IERC721LazyClaim).interfaceId ||
            interfaceId == type(ICreatorExtensionTokenURI).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }

    
    /**
     * @notice This extension is shared, not single-creator. So we must ensure
     * that a claim's initializer is an admin on the creator contract
     * @param creatorContractAddress the address of the creator contract to check the admin against
     */
    modifier creatorAdminRequired(address creatorContractAddress) {
        AdminControl creatorCoreContract = AdminControl(creatorContractAddress);
        require(creatorCoreContract.isAdmin(msg.sender), "Wallet is not an administrator for contract");
        _;
    }

    /*
     * @notice initialize a new claim, emit initialize event, and return the newly created index
     * @param creatorContractAddress the creator contract the claim will mint tokens for
     * @param claimParameters the parameters which will affect the minting behavior of the claim
     * @return the index of the newly created claim
     */
    function initializeClaim(
        address creatorContractAddress,
        ClaimParameters calldata claimParameters
    ) external override creatorAdminRequired(creatorContractAddress) returns (uint256) {
        // Sanity checks
        require(claimParameters.storageProtocol != StorageProtocol.INVALID, "Cannot initialize with invalid storage protocol");
        require(claimParameters.endDate == 0 || claimParameters.startDate < claimParameters.endDate, "Cannot have startDate greater than or equal to endDate");
        require(claimParameters.merkleRoot == "" || claimParameters.walletMax == 0, "Cannot provide both mintsPerWallet and merkleRoot");
        require(claimParameters.totalMax < 10000, "Cannot have totalMax greater than 10000");
    
        // Get the index for the new claim
        _claimCounts[creatorContractAddress]++;
        uint256 newIndex = _claimCounts[creatorContractAddress];

        // Create the claim
        _claims[creatorContractAddress][newIndex] = Claim({
            total: 0,
            totalMax: claimParameters.totalMax,
            walletMax: claimParameters.walletMax,
            startDate: claimParameters.startDate,
            endDate: claimParameters.endDate,
            storageProtocol: claimParameters.storageProtocol,
            identical: claimParameters.identical,
            merkleRoot: claimParameters.merkleRoot,
            location: claimParameters.location
        });

        emit ClaimInitialized(creatorContractAddress, newIndex, msg.sender);
        return newIndex;
    }

    /**
     * @notice update an existing claim at claimIndex
     * @param creatorContractAddress the creator contract corresponding to the claim
     * @param claimIndex the index of the claim in the list of creatorContractAddress' _claims
     * @param claimParameters the parameters which will affect the minting behavior of the claim
     */
    function updateClaim(
        address creatorContractAddress,
        uint256 claimIndex,
        ClaimParameters calldata claimParameters
    ) external override creatorAdminRequired(creatorContractAddress) {
        // Sanity checks
        require(_claims[creatorContractAddress][claimIndex].storageProtocol != StorageProtocol.INVALID, "Claim not initialized");
        require(claimParameters.storageProtocol != StorageProtocol.INVALID, "Cannot set invalid storage protocol");
        require(_claims[creatorContractAddress][claimIndex].totalMax == claimParameters.totalMax, "Cannot modify totalMax");
        require(_claims[creatorContractAddress][claimIndex].walletMax == 0 || _claims[creatorContractAddress][claimIndex].walletMax <= claimParameters.walletMax, "Cannot decrease walletMax");
        require(claimParameters.endDate == 0 || claimParameters.startDate < claimParameters.endDate, "Cannot have startDate greater than or equal to endDate");

        // Overwrite the existing claim
        _claims[creatorContractAddress][claimIndex] = Claim({
            total: _claims[creatorContractAddress][claimIndex].total,
            totalMax: claimParameters.totalMax,
            walletMax: claimParameters.walletMax,
            startDate: claimParameters.startDate,
            endDate: claimParameters.endDate,
            storageProtocol: claimParameters.storageProtocol,
            identical: claimParameters.identical,
            merkleRoot: claimParameters.merkleRoot,
            location: claimParameters.location
        });
    }

    /**
     * @notice get the number of _claims initialized for a given creator contract
     * @param creatorContractAddress the address of the creator contract
     * @return the number of _claims initialized for this creator contract
     */
    function getClaimCount(address creatorContractAddress) external override view returns(uint256) {
        return _claimCounts[creatorContractAddress];
    }

    /**
     * @notice get a claim corresponding to a creator contract and index
     * @param creatorContractAddress the address of the creator contract
     * @param claimIndex the index of the claim
     * @return the claim object
     */
    function getClaim(address creatorContractAddress, uint256 claimIndex) external override view returns(Claim memory) {
        require(_claims[creatorContractAddress][claimIndex].storageProtocol != StorageProtocol.INVALID, "Claim not initialized");
        return _claims[creatorContractAddress][claimIndex];
    }

    /**
     * @notice check if a person can mint
     * @param creatorContractAddress the address of the creator contract for the claim
     * @param claimIndex the index of the claim
     * @param mintIndex  the mint index of the claim
     * @return whether or not the claim was minted
     */
    function canMint(address creatorContractAddress, uint256 claimIndex, uint32 mintIndex) external override view returns(bool) {
        Claim storage claim = _claims[creatorContractAddress][claimIndex];
        require(claim.storageProtocol != StorageProtocol.INVALID, "Claim not initialized");
        if (claim.merkleRoot != "") {
            uint256 claimMintIndex = mintIndex >> 8;
            uint256 claimMintTracking = _claimMintIndices[creatorContractAddress][claimIndex][claimMintIndex];
            uint256 claimMintBitmask = mintIndex & BITMASK;
            uint256 mintBitmask = 1 << claimMintBitmask;
            return mintBitmask & claimMintTracking != 0;
        } else {
            if (claim.walletMax != 0) {
                return _mintsPerWallet[creatorContractAddress][claimIndex][msg.sender] < claim.walletMax;
            }
            return true;
        }
    }

    /**
     * @notice allow a wallet to lazily claim a token according to parameters
     * @param creatorContractAddress the creator contract address
     * @param claimIndex the index of the claim for which we will mint
     * @param mintIndex the mint index
     * @param merkleProof if the claim has a merkleRoot, verifying merkleProof ensures that address + minterValue was used to construct it
     * @return the tokenId of the newly minted token
     */
    function mint(address creatorContractAddress, uint256 claimIndex, uint32 mintIndex, bytes32[] calldata merkleProof) external override returns (uint256) {
        Claim storage claim = _claims[creatorContractAddress][claimIndex];
        // Safely retrieve the claim
        require(claim.storageProtocol != StorageProtocol.INVALID, "Claim not initialized");

        // Check timestamps
        require(claim.startDate == 0 || claim.startDate < block.timestamp, "Transaction before start date");
        require(claim.endDate == 0 || claim.endDate >= block.timestamp, "Transaction after end date");

        // Check totalMax
        require(claim.totalMax == 0 || claim.total < claim.totalMax, "Maximum tokens already minted for this claim");

        if (claim.merkleRoot != "") {
            // Merkle mint
            bytes32 leaf = keccak256(abi.encodePacked(msg.sender, mintIndex));
            require(MerkleProof.verify(merkleProof, claim.merkleRoot, leaf), "Could not verify merkle proof");

            // Check if mintIndex has been minted
            uint256 claimMintIndex = mintIndex >> 8;
            uint256 claimMintTracking = _claimMintIndices[creatorContractAddress][claimIndex][claimMintIndex];
            uint256 claimMintBitmask = mintIndex & BITMASK;
            uint256 mintBitmask = 1 << claimMintBitmask;
            require(mintBitmask & claimMintTracking == 0, "Already minted");
            _claimMintIndices[creatorContractAddress][claimIndex][claimMintIndex] = claimMintTracking | mintBitmask;
        } else {
            // Non-merkle mint
            if (claim.walletMax != 0) {
                require(_mintsPerWallet[creatorContractAddress][claimIndex][msg.sender] < claim.walletMax, "Maximum tokens already minted for this wallet");
                unchecked{ _mintsPerWallet[creatorContractAddress][claimIndex][msg.sender]++; }
            }
        }
        unchecked{ claim.total++; }

        // Do mint
        uint256 newTokenId = IERC721CreatorCore(creatorContractAddress).mintExtension(msg.sender);

        // Insert the new tokenId into _tokenClaims for the current claim address & index
        _tokenClaims[creatorContractAddress][newTokenId] = TokenClaim(uint224(claimIndex), claim.total);

        emit Mint(creatorContractAddress, claimIndex, newTokenId, msg.sender);
        return newTokenId;
    }

    /**
     * @notice construct the uri for the erc721 token metadata
     * @param creatorContractAddress the creator contract address
     * @param tokenId the token id to construct the uri for
     * @return uri the uri constructed according to the params of the claim corresponding to tokenId
     * @inheritdoc ICreatorExtensionTokenURI
     */
    function tokenURI(address creatorContractAddress, uint256 tokenId) external override view returns(string memory uri) {
        TokenClaim memory tokenClaim = _tokenClaims[creatorContractAddress][tokenId];
        require(tokenClaim.claimIndex > 0, "Token does not exist");
        Claim memory claim = _claims[creatorContractAddress][tokenClaim.claimIndex];

        string memory prefix = "";
        if (claim.storageProtocol == StorageProtocol.ARWEAVE) {
            prefix = ARWEAVE_PREFIX;
        } else if (claim.storageProtocol == StorageProtocol.IPFS) {
            prefix = IPFS_PREFIX;
        }
        uri = string(abi.encodePacked(prefix, claim.location));

        // Depending on params, we may want to append a suffix to location
        if (!claim.identical) {
            uri = string(abi.encodePacked(uri, "/", uint256(tokenClaim.mintIndex).toString()));
        }
    }
}
