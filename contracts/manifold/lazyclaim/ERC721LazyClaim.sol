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
    string constant ARWEAVE_PREFIX = "https://arweave.net/";
    string constant IPFS_PREFIX = "ipfs://";

    event ClaimInitialized(address indexed creatorContract, uint256 indexed claimIndex, address initializer);
    event Mint(address indexed creatorContract, uint256 indexed claimIndex, uint256 tokenId, address claimer);

    struct IndexRange {
        uint256 start;
        uint256 count;
    }

    // stores the size of the mapping in claims, since we can have multiple claims per creator contract
    // { contractAddress => claimCount }
    mapping(address => uint256) claimCounts;

    // stores the claim data structure, including params and total supply
    // { contractAddress => { claimIndex => Claim } }
    mapping(address => mapping(uint256 => Claim)) claims;

    // stores the number of tokens minted per wallet per claim, in order to limit maximum
    // { contractAddress => { claimIndex => { walletAddress => walletMints } } }
    mapping(address => mapping(uint256 => mapping(address => uint32))) mintsPerWallet;

    // stores which tokenId corresponds to which claimIndex, used to generate token uris
    // { contractAddress => { claimIndex => indexRanges } }
    mapping(address => mapping(uint256 => IndexRange[])) tokenClaims;

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
        require(bytes(claimParameters.location).length != 0, "Cannot initialize with empty location");
        require(claimParameters.storageProtocol != StorageProtocol.INVALID, "Cannot initialize with invalid storage protocol");
        require(claimParameters.endDate == 0 || claimParameters.startDate < claimParameters.endDate, "Cannot have startDate greater than or equal to endDate");
        require(claimParameters.totalMax < 10000, "Cannot have totalMax greater than 10000");
    
        // Get the index for the new claim
        claimCounts[creatorContractAddress]++;
        uint256 newIndex = claimCounts[creatorContractAddress];

        // Create the claim
        claims[creatorContractAddress][newIndex] = Claim({
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
     * @param claimIndex the index of the claim in the list of creatorContractAddress' claims
     * @param claimParameters the parameters which will affect the minting behavior of the claim
     */
    function overwriteClaim(
        address creatorContractAddress,
        uint256 claimIndex,
        ClaimParameters calldata claimParameters
    ) external override creatorAdminRequired(creatorContractAddress) {
        // Sanity checks
        require(bytes(claims[creatorContractAddress][claimIndex].location).length != 0, "Cannot overwrite uninitialized claim");
        require(claimParameters.storageProtocol != StorageProtocol.INVALID, "Cannot set invalid storage protocol");
        require(claims[creatorContractAddress][claimIndex].totalMax == claimParameters.totalMax, "Cannot modify totalMax");
        require(claims[creatorContractAddress][claimIndex].walletMax <= claimParameters.walletMax, "Cannot decrease walletMax");
        require(claimParameters.endDate == 0 || claimParameters.startDate < claimParameters.endDate, "Cannot have startDate greater than or equal to endDate");

        // Overwrite the existing claim
        claims[creatorContractAddress][claimIndex] = Claim({
            total: claims[creatorContractAddress][claimIndex].total,
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
     * @notice get the number of claims initialized for a given creator contract
     * @param creatorContractAddress the address of the creator contract
     * @return the number of claims initialized for this creator contract
     */
    function getClaimCount(address creatorContractAddress) external override view returns(uint256) {
        return claimCounts[creatorContractAddress];
    }

    /**
     * @notice get a claim corresponding to a creator contract and index
     * @param creatorContractAddress the address of the creator contract
     * @param claimIndex the index of the claim
     * @return the claim object
     */
    function getClaim(address creatorContractAddress, uint256 claimIndex) external override view returns(Claim memory) {
        require(bytes(claims[creatorContractAddress][claimIndex].location).length != 0, "Claim not initialized");
        return claims[creatorContractAddress][claimIndex];
    }

    /**
     * @notice get the number of tokens minted for the current wallet for a given claim
     * @param creatorContractAddress the address of the creator contract for the claim
     * @param claimIndex the index of the claim
     * @return the number of tokens minted for the current wallet
     */
    function getWalletMinted(address creatorContractAddress, uint256 claimIndex, address walletAddress) external override view returns(uint32) {
        require(bytes(claims[creatorContractAddress][claimIndex].location).length != 0, "Claim not initialized");
        return uint32(mintsPerWallet[creatorContractAddress][claimIndex][walletAddress]);
    }

    /**
     * @notice get the claim index corresponding to a creator contract and tokenId
     * @param creatorContractAddress the address of the creator contract
     * @param tokenId the token id
     * @return the index of the claim
     */
    function getTokenClaim(address creatorContractAddress, uint256 tokenId) external override view returns(uint256) {
        return _getTokenClaim(creatorContractAddress, tokenId);
    }

    /**
     * @notice update tokenClaim with a newly minted token.
     * increment the count of the current indexRange if this mint is consecutive, or start a new one if continuity was broken
     * @param creatorContractAddress the creator contract address
     * @param claimIndex the index of the claim
     * @param start the token id marking the start of a new index range or the extension of an existing one
     */
    function _updateIndexRanges(address creatorContractAddress, uint256 claimIndex, uint256 start) internal {
        IndexRange[] storage indexRanges = tokenClaims[creatorContractAddress][claimIndex];
        if (indexRanges.length == 0) {
            indexRanges.push(IndexRange(start, 1));
        } else {
            IndexRange storage lastIndexRange = indexRanges[indexRanges.length-1];
            if ((lastIndexRange.start + lastIndexRange.count) == start) {
                lastIndexRange.count++;
            } else {
                indexRanges.push(IndexRange(start, 1));
            }
        }
    }

    /**
     * @notice get the claim corresponding to a token by searching through the indexRanges in tokenClaims
     * @param creatorContractAddress the creator contract address
     * @param tokenId the token id to search for in tokenClaims
     * @return the claim index corresponding to this token
     */
    function _getTokenClaim(address creatorContractAddress, uint256 tokenId) internal view returns(uint256) {
        require(claimCounts[creatorContractAddress] > 0, "No claims for creator contract");
        for (uint256 index=1; index <= claimCounts[creatorContractAddress]; index++) {
            IndexRange[] memory indexRanges = tokenClaims[creatorContractAddress][index];
            uint256 offset;
            for (uint256 i = 0; i < indexRanges.length; i++) {
                IndexRange memory currentIndex = indexRanges[i];
                if (tokenId < currentIndex.start) break;
                if (tokenId >= currentIndex.start && tokenId < currentIndex.start + currentIndex.count) {
                    return index;
                }
                offset += currentIndex.count;
            }
        }
        revert("Invalid token");
    }



    /**
     * @notice allow a wallet to lazily claim a token according to parameters
     * @param creatorContractAddress the creator contract address
     * @param claimIndex the index of the claim for which we will mint
     * @param merkleProof if the claim has a merkleRoot, verifying merkleProof ensures that address + minterValue was used to construct it
     * @param minterValue the value portion which combines with msg.sender to form the merkle leaf corresponding to merkleProof
     * @return the tokenId of the newly minted token
     */
    function mint(address creatorContractAddress, uint256 claimIndex, bytes32[] calldata merkleProof, uint32 minterValue) external override returns (uint256) {
        Claim storage claim = claims[creatorContractAddress][claimIndex];
        // Safely retrieve the claim
        require(claim.storageProtocol != StorageProtocol.INVALID, "Claim not initialized");

        // Check timestamps
        require(claim.startDate == 0 || claim.startDate < block.timestamp, "Transaction before start date");
        require(claim.endDate == 0 || claim.endDate >= block.timestamp, "Transaction after end date");

        // Check totalMax
        require(claim.totalMax == 0 || claim.total < claim.totalMax, "Maximum tokens already minted for this claim");

        // Verify merkle proof
        if (claim.merkleRoot != "") {
            bytes32 leaf = keccak256(abi.encodePacked(msg.sender, minterValue));
            require(MerkleProof.verify(merkleProof, claim.merkleRoot, leaf), "Could not verify merkle proof");

            if (minterValue != 0) {
                uint256 mintCount = mintsPerWallet[creatorContractAddress][claimIndex][msg.sender];
                // Check minterValue and walletMax against minter's wallet
                require((claim.walletMax == 0 || mintCount < claim.walletMax) && mintCount < minterValue, "Maximum tokens already minted for this wallet per allocation");
            } else {
                // Check walletMax against minter's wallet
                require(claim.walletMax == 0 || mintsPerWallet[creatorContractAddress][claimIndex][msg.sender] < claim.walletMax, "Maximum tokens already minted for this wallet");
            }
        } else {
            // Check walletMax against minter's wallet
            require(claim.walletMax == 0 || mintsPerWallet[creatorContractAddress][claimIndex][msg.sender] < claim.walletMax, "Maximum tokens already minted for this wallet");
        }

        // Do mint
        uint256 newTokenId = IERC721CreatorCore(creatorContractAddress).mintExtension(msg.sender);

        // Insert the new tokenId into tokenClaims for the current claim address & index
        _updateIndexRanges(creatorContractAddress, claimIndex, newTokenId);

        // Increment the wallet mints & total mints - already checked for safety
        unchecked{ mintsPerWallet[creatorContractAddress][claimIndex][msg.sender]++; }
        unchecked{ claim.total++; }
        
        emit Mint(creatorContractAddress, claimIndex, newTokenId, msg.sender);
        return newTokenId;
    }

    /**
     * @notice construct the uri for the erc721 token metadata
     * @param creatorContractAddress the creator contract address
     * @param tokenId the token id to construct the uri for
     * @return the uri constructed according to the params of the claim corresponding to tokenId
     * @inheritdoc ICreatorExtensionTokenURI
     */
    function tokenURI(address creatorContractAddress, uint256 tokenId) external override view returns(string memory) {
        // First, find the claim corresponding to this token id
        uint256 claimIndex = _getTokenClaim(creatorContractAddress, tokenId);

        // Depending on params, we may want to append a suffix to location
        string memory suffix = "";
        if (!claims[creatorContractAddress][claimIndex].identical) {
            suffix = string(abi.encodePacked("/", Strings.toString(tokenId)));

            // IPFS blobs need .json at the end
            if (claims[creatorContractAddress][claimIndex].storageProtocol == StorageProtocol.IPFS) {
                suffix = string(abi.encodePacked(suffix, ".json"));
            }
        }

        // Likewise, may have a prefix for different protocols
        string memory prefix = "";
        if (claims[creatorContractAddress][claimIndex].storageProtocol == StorageProtocol.IPFS) {
            prefix = IPFS_PREFIX;
        } else if (claims[creatorContractAddress][claimIndex].storageProtocol == StorageProtocol.ARWEAVE) {
            prefix = ARWEAVE_PREFIX;
        }

        // Return the fully-affixed uri
        return string(abi.encodePacked(prefix, claims[creatorContractAddress][claimIndex].location, suffix));
    }
}
