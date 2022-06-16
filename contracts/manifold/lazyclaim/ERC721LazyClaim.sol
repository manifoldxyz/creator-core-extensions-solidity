// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

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
    uint256 private constant MINT_INDEX_BITMASK = 0xFF;

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
        uint32 mintOrder;
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
     * @param creatorContractAddress    the address of the creator contract to check the admin against
     */
    modifier creatorAdminRequired(address creatorContractAddress) {
        AdminControl creatorCoreContract = AdminControl(creatorContractAddress);
        require(creatorCoreContract.isAdmin(msg.sender), "Wallet is not an administrator for contract");
        _;
    }

    /**
     * See {IERC721LazyClaim-initializeClaim}.
     */
    function initializeClaim(
        address creatorContractAddress,
        ClaimParameters calldata claimParameters
    ) external override creatorAdminRequired(creatorContractAddress) returns (uint256) {
        // Sanity checks
        require(claimParameters.storageProtocol != StorageProtocol.INVALID, "Cannot initialize with invalid storage protocol");
        require(claimParameters.endDate == 0 || claimParameters.startDate < claimParameters.endDate, "Cannot have startDate greater than or equal to endDate");
        require(claimParameters.merkleRoot == "" || claimParameters.walletMax == 0, "Cannot provide both mintsPerWallet and merkleRoot");
    
        // Get the index for the new claim
        _claimCounts[creatorContractAddress]++;
        uint224 newIndex = _claimCounts[creatorContractAddress];

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
     * See {IERC721LazyClaim-udpateClaim}.
     */
    function updateClaim(
        address creatorContractAddress,
        uint256 claimIndex,
        ClaimParameters calldata claimParameters
    ) external override creatorAdminRequired(creatorContractAddress) {
        // Sanity checks
        require(_claims[creatorContractAddress][claimIndex].storageProtocol != StorageProtocol.INVALID, "Claim not initialized");
        require(claimParameters.storageProtocol != StorageProtocol.INVALID, "Cannot set invalid storage protocol");
        require(_claims[creatorContractAddress][claimIndex].totalMax == 0 ||  _claims[creatorContractAddress][claimIndex].totalMax <= claimParameters.totalMax, "Cannot decrease totalMax");
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
     * See {IERC721LazyClaim-getClaimCount}.
     */
    function getClaimCount(address creatorContractAddress) external override view returns(uint256) {
        return _claimCounts[creatorContractAddress];
    }

    /**
     * See {IERC721LazyClaim-getClaim}.
     */
    function getClaim(address creatorContractAddress, uint256 claimIndex) external override view returns(Claim memory) {
        require(_claims[creatorContractAddress][claimIndex].storageProtocol != StorageProtocol.INVALID, "Claim not initialized");
        return _claims[creatorContractAddress][claimIndex];
    }

    /**
     * See {IERC721LazyClaim-checkMintIndex}.
     */
    function checkMintIndex(address creatorContractAddress, uint256 claimIndex, uint32 mintIndex) public override view returns(bool) {
        Claim storage claim = _claims[creatorContractAddress][claimIndex];
        require(claim.storageProtocol != StorageProtocol.INVALID, "Claim not initialized");
        require(claim.merkleRoot != "", "Can only check merkle claims");
        uint256 claimMintIndex = mintIndex >> 8;
        uint256 claimMintTracking = _claimMintIndices[creatorContractAddress][claimIndex][claimMintIndex];
        uint256 mintBitmask = 1 << (mintIndex & MINT_INDEX_BITMASK);
        return mintBitmask & claimMintTracking != 0;
    }

    /**
     * See {IERC721LazyClaim-checkMintIndices}.
     */
    function checkMintIndices(address creatorContractAddress, uint256 claimIndex, uint32[] calldata mintIndices) external override view returns(bool[] memory minted) {
        minted = new bool[](mintIndices.length);
        for (uint i = 0; i < mintIndices.length; i++) {
            minted[i] = checkMintIndex(creatorContractAddress, claimIndex, mintIndices[i]);
        }
    }

    /**
     * See {IERC721LazyClaim-getTotalMints}.
     */
    function getTotalMints(address minter, address creatorContractAddress, uint256 claimIndex) external override view returns(uint32) {
        Claim storage claim = _claims[creatorContractAddress][claimIndex];
        require(claim.storageProtocol != StorageProtocol.INVALID, "Claim not initialized");
        require(claim.walletMax != 0, "Can only retrieve for non-merkle claims with walletMax");
        return  uint32(_mintsPerWallet[creatorContractAddress][claimIndex][minter]);
    }

    /**
     * See {IERC721LazyClaim-mint}.
     */
    function mint(address creatorContractAddress, uint256 claimIndex, uint32 mintIndex, bytes32[] calldata merkleProof) external override {
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
            _checkMerkleAndUpdate(claim, creatorContractAddress, claimIndex, mintIndex, merkleProof);
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

        emit ClaimMint(creatorContractAddress, claimIndex);
    }

    /**
     * See {IERC721LazyClaim-mintBatch}.
     */
    function mintBatch(address creatorContractAddress, uint256 claimIndex, uint16 mintCount, uint32[] calldata mintIndices, bytes32[][] calldata merkleProofs) external override {
        Claim storage claim = _claims[creatorContractAddress][claimIndex];
        
        // Safely retrieve the claim
        require(claim.storageProtocol != StorageProtocol.INVALID, "Claim not initialized");

        // Check timestamps
        require(claim.startDate == 0 || claim.startDate < block.timestamp, "Transaction before start date");
        require(claim.endDate == 0 || claim.endDate >= block.timestamp, "Transaction after end date");

        // Check totalMax
        require(claim.totalMax == 0 || claim.total+mintCount <= claim.totalMax, "Too many requested for this claim");
        
        uint256 newMintIndex = claim.total+1;
        unchecked{ claim.total += mintCount; }

        if (claim.merkleRoot != "") {
            require(mintCount == mintIndices.length && mintCount == merkleProofs.length, "Invalid input");
            // Merkle mint
            for (uint i = 0; i < mintCount; ) {
                uint32 mintIndex = mintIndices[i];
                bytes32[] memory merkleProof = merkleProofs[i];
                
                _checkMerkleAndUpdate(claim, creatorContractAddress, claimIndex, mintIndex, merkleProof);
                unchecked { i++; }
            }
        } else {
            // Non-merkle mint
            if (claim.walletMax != 0) {
                require(_mintsPerWallet[creatorContractAddress][claimIndex][msg.sender]+mintCount <= claim.walletMax, "Too many requested for this wallet");
                unchecked{ _mintsPerWallet[creatorContractAddress][claimIndex][msg.sender] += mintCount; }
            }
            
        }
        uint256[] memory newTokenIds = IERC721CreatorCore(creatorContractAddress).mintExtensionBatch(msg.sender, mintCount);
        for (uint i = 0; i < mintCount; ) {
            _tokenClaims[creatorContractAddress][newTokenIds[i]] = TokenClaim(uint224(claimIndex), uint32(newMintIndex+i));
            unchecked { i++; }
        }

        emit ClaimMintBatch(creatorContractAddress, claimIndex, mintCount);
    }

    /**
     * Helper to check merkle proof and whether or not the mintIndex was consumed. Also updates the consumed counts
     */
    function _checkMerkleAndUpdate(Claim storage claim, address creatorContractAddress, uint256 claimIndex, uint32 mintIndex, bytes32[] memory merkleProof) private {
        // Merkle mint
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, mintIndex));
        require(MerkleProof.verify(merkleProof, claim.merkleRoot, leaf), "Could not verify merkle proof");

        // Check if mintIndex has been minted
        uint256 claimMintIndex = mintIndex >> 8;
        uint256 claimMintTracking = _claimMintIndices[creatorContractAddress][claimIndex][claimMintIndex];
        uint256 mintBitmask = 1 << (mintIndex & MINT_INDEX_BITMASK);
        require(mintBitmask & claimMintTracking == 0, "Already minted");
        _claimMintIndices[creatorContractAddress][claimIndex][claimMintIndex] = claimMintTracking | mintBitmask;
    }

    /**
     * See {ICreatorExtensionTokenURI-tokenURI}.
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
            uri = string(abi.encodePacked(uri, "/", uint256(tokenClaim.mintOrder).toString()));
        }
    }
}
