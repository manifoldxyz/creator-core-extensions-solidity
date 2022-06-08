// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC721CreatorCore.sol";
import "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/ICreatorExtensionTokenURI.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/interfaces/IERC165.sol";

import "./IERC721LazyClaim.sol";

/**
 * Lazy claim with optional whitelist ERC721 tokens
 */
contract ERC721LazyClaim is IERC165, IERC721LazyClaim, ICreatorExtensionTokenURI, ReentrancyGuard {
  string constant ARWEAVE_PREFIX = "https://arweave.net/";
  string constant IPFS_PREFIX = "https://ipfs.io/ipfs/";

  event ClaimInitialized(address indexed creatorContract, uint indexed index, address initializer);
  event Mint(address indexed creatorContract, uint indexed index, uint indexed tokenId, address minter);

  struct IndexRange {
    uint256 start;
    uint256 count;
  }

  // stores the size of the mapping in claims, since we can have multiple claims per creator contract
  // { contractAddress => claimCount }
  mapping(address => uint) public claimCounts;

  // stores the claim data structure, including params and total supply
  // { contractAddress => { claimIndex => Claim } }
  mapping(address => mapping(uint => Claim)) public claims;

  // stores the number of tokens minted per wallet per claim, in order to limit maximum
  // { contractAddress => { claimIndex => { walletAddress => walletMints } } }
  mapping(address => mapping(uint => mapping(address => uint32))) public mintsPerWallet;

  // stores which claim corresponds to which tokenId, used to generate token uris
  // { contractAddress => { tokenId => indexRanges } }
  mapping(address => mapping(uint => IndexRange[])) public tokenClaims;

  function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165) returns (bool) {
    return interfaceId == type(IERC721LazyClaim).interfaceId ||
      interfaceId == type(ICreatorExtensionTokenURI).interfaceId ||
      interfaceId == type(IERC165).interfaceId;
  }

  // This extension is shared, not single-creator. So we must ensure
  // that a claim's initializer is an admin on the creator contract
  modifier creatorAdminRequired(address creatorContractAddress) {
    AdminControl creatorCoreContract = AdminControl(creatorContractAddress);
    require(creatorCoreContract.isAdmin(msg.sender), "Wallet is not an administrator for contract");
    _;
  }

  // Initialize
  function initializeClaim(
    address creatorContractAddress,
    bytes32 merkleRoot,
    string calldata location,
    uint32 totalMax,
    uint32 walletMax,
    uint48 startDate,
    uint48 endDate,
    StorageProtocol storageProtocol,
    bool identical
  ) external creatorAdminRequired(creatorContractAddress) returns (uint) {
    // Sanity checks
    require(endDate == 0 || startDate < endDate, "Cannot have startDate greater than or equal to endDate");
    require(totalMax < 10000, "Cannot have totalMax greater than 10000");
  
    // Get the index for the new claim
    uint newIndex = claimCounts[creatorContractAddress];
    claimCounts[creatorContractAddress] = newIndex + 1;

    // Create the claim
    claims[creatorContractAddress][newIndex] = Claim({
      total: 0,
      totalMax: totalMax,
      walletMax: walletMax,
      startDate: startDate,
      endDate: endDate,
      storageProtocol: storageProtocol,
      identical: identical,
      merkleRoot: merkleRoot,
      location: location
    });

    emit ClaimInitialized(creatorContractAddress, newIndex, msg.sender);
    return newIndex;
  }

  // Update
  function overwriteClaim(
    address creatorContractAddress,
    uint index,
    bytes32 merkleRoot,
    string calldata location,
    uint32 totalMax,
    uint32 walletMax,
    uint48 startDate,
    uint48 endDate,
    StorageProtocol storageProtocol,
    bool identical
  ) external creatorAdminRequired(creatorContractAddress) {
    // Sanity checks
    require(claims[creatorContractAddress][index].totalMax == totalMax, "Cannot modify totalMax");
    require(claims[creatorContractAddress][index].walletMax <= walletMax, "Cannot decrease walletMax");
    require(endDate == 0 || startDate < endDate, "Cannot have startDate greater than or equal to endDate");

    // Overwrite the existing claim
    claims[creatorContractAddress][index] = Claim({
      total: claims[creatorContractAddress][index].total,
      totalMax: totalMax,
      walletMax: walletMax,
      startDate: startDate,
      endDate: endDate,
      storageProtocol: storageProtocol,
      identical: identical,
      merkleRoot: merkleRoot,
      location: location
    });
  }

  // Public getters
  function getClaimCount(address creatorContractAddress) external view returns(uint) {
    return claimCounts[creatorContractAddress];
  }
  function getClaim(address creatorContractAddress, uint index) external view returns(Claim memory) {
    require(index < claimCounts[creatorContractAddress], "Claim does not exist");
    return claims[creatorContractAddress][index];
  }
  function getWalletMinted(address creatorContractAddress, uint index) external view returns(uint32) {
    require(index < claimCounts[creatorContractAddress], "Claim does not exist");
    return mintsPerWallet[creatorContractAddress][index][msg.sender];
  }

  // Internal: Update tokenClaim with a newly minted token.
  // Increment the count of the current indexRange if this mint is consecutive, or start a new one if continuity was broken
  function _updateIndexRanges(address creatorContractAddress, uint256 index, uint256 start) internal {
    IndexRange[] storage indexRanges = tokenClaims[creatorContractAddress][index];
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

  // Internal: Get the claim corresponding to a token by searching through the indexRanges in tokenClaims
  function _getTokenClaim(address creatorContractAddress, uint256 tokenId) internal view returns(uint256) {
    require(claimCounts[creatorContractAddress] > 0, "No claims for creator contract");
    for (uint index=1; index <= claimCounts[creatorContractAddress]; index++) {
      IndexRange[] memory indexRanges = tokenClaims[creatorContractAddress][index];
      uint256 offset;
      for (uint i = 0; i < indexRanges.length; i++) {
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


  // Public mint
  function mint(address creatorContractAddress, uint index, bytes32[] calldata merkleProof, uint32 minterValue) external {
      // Safely retrieve the claim
      require(index < claimCounts[creatorContractAddress], "Claim does not exist");
      Claim storage claim = claims[creatorContractAddress][index];

      // Check timestamps
      if (claim.startDate != 0) require(claim.startDate < block.timestamp, "Transaction before start date");
      if (claim.endDate != 0) require(claim.endDate >= block.timestamp, "Transaction after end date");

      // Check walletMax against minter's wallet
      if (claim.walletMax != 0) {
        require(mintsPerWallet[creatorContractAddress][index][msg.sender] < claim.walletMax, "Maximum tokens already minted for this wallet");
      }

      // Check totalMax
      if (claim.totalMax != 0) {
        require(claim.total < claim.totalMax, "Maximum tokens already minted for this claim");
      }

      // Verify merkle proof
      if (claim.merkleRoot != "") {
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, minterValue));
        require(MerkleProof.verify(merkleProof, claim.merkleRoot, leaf), "Could not verify merkle proof");

        // Check minterValue against minter's wallet
        if (minterValue != 0) {
          uint allocationMinted = mintsPerWallet[creatorContractAddress][index][msg.sender];
          require(allocationMinted < minterValue, "Maximum tokens already minted for this wallet per allocation");
        }
      }

      // Do mint
      uint newTokenId = IERC721CreatorCore(creatorContractAddress).mintExtension(msg.sender);

      // Insert the new tokenId into tokenClaims for the current claim address & index
      _updateIndexRanges(creatorContractAddress, index, newTokenId);

      // Increment the wallet mints & total mints - already checked for safety
      unchecked{ mintsPerWallet[creatorContractAddress][index][msg.sender]++; }
      unchecked{ claim.total++; }

      emit Mint(creatorContractAddress, index, newTokenId, msg.sender);
  }

  function tokenURI(address creatorContractAddress, uint tokenId) external view returns(string memory) {
    // First, find the claim corresponding to this token id
    uint claimIndex = _getTokenClaim(creatorContractAddress, tokenId);

    // Depending on params, we may want to append a suffix to location
    string memory suffix = "";
    if (!claims[creatorContractAddress][claimIndex].identical) {
      suffix = string(abi.encodePacked("/", tokenId));

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
