// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC721CreatorCore.sol";
import "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/ICreatorExtensionTokenURI.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/interfaces/IERC165.sol";
// import "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import "./IERC721LazyMint.sol";

/**
 * Lazy mint with whitelist ERC721 tokens
 */
contract ERC721LazyMint is IERC165, IERC721LazyMint, ICreatorExtensionTokenURI, ReentrancyGuard {
  mapping(address => uint) public listingCounts;
  mapping(address => mapping(uint => Listing)) public listings;
  mapping(address => mapping(uint => uint)) public mintsPerListing;
  mapping(address => mapping(uint => mapping(address => uint))) public mintsPerWallet;
  mapping(address => mapping(uint => uint)) public tokenListings;

  function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165) returns (bool) {
    return interfaceId == type(IERC721LazyMint).interfaceId ||
      interfaceId == type(ICreatorExtensionTokenURI).interfaceId ||
      interfaceId == type(IERC165).interfaceId;
  }

  modifier creatorAdminRequired(address creatorContractAddress) {
    // This is shared, not single-creator. So we must ensure that the initializer is an admin of the contract
    AdminControl creatorCoreContract = AdminControl(creatorContractAddress);
    require(creatorCoreContract.isAdmin(msg.sender), "Wallet is not an administrator for contract");
    _;
  }

  // Initialize
  function initializeListing(
    address creatorContractAddress,
    bytes32 merkleRoot,
    string calldata uri,
    uint totalMax,
    uint walletMax,
    uint startDate,
    uint endDate
  ) external creatorAdminRequired(creatorContractAddress) {
    // Get the index for the new listing
    uint newIndex = listingCounts[creatorContractAddress];
    listingCounts[creatorContractAddress] = newIndex + 1;

    // Create the listing
    listings[creatorContractAddress][newIndex] = Listing({
      merkleRoot: merkleRoot,
      uri: uri,
      totalMax: totalMax,
      walletMax: walletMax,
      startDate: startDate,
      endDate: endDate
    });
  }

  // Setters
  function setMerkleRoot(address creatorContractAddress, uint index, bytes32 merkleRoot) external {
    Listing memory listing = listings[creatorContractAddress][index];
    listing.merkleRoot = merkleRoot;
    listings[creatorContractAddress][index] = listing;
  }
  function setURI(address creatorContractAddress, uint index, string calldata uri) external {
    Listing memory listing = listings[creatorContractAddress][index];
    listing.uri = uri;
    listings[creatorContractAddress][index] = listing;
  }
  function setTotalMax(address creatorContractAddress, uint index, uint totalMax) external {
    Listing memory listing = listings[creatorContractAddress][index];
    listing.totalMax = totalMax;
    listings[creatorContractAddress][index] = listing;
  }
  function setWalletMax(address creatorContractAddress, uint index, uint walletMax) external {
    Listing memory listing = listings[creatorContractAddress][index];
    listing.walletMax = walletMax;
    listings[creatorContractAddress][index] = listing;
  }
  function setStartDate(address creatorContractAddress, uint index, uint startDate) external {
    Listing memory listing = listings[creatorContractAddress][index];
    listing.startDate = startDate;
    listings[creatorContractAddress][index] = listing;
  }
  function setEndDate(address creatorContractAddress, uint index, uint endDate) external {
    Listing memory listing = listings[creatorContractAddress][index];
    listing.endDate = endDate;
    listings[creatorContractAddress][index] = listing;
  }

  // Public getters
  function getListingCount(address creatorContractAddress) external view returns(uint) {
    return listingCounts[creatorContractAddress];
  }
  function getListing(address creatorContractAddress, uint index) external view returns(Listing memory) {
    return listings[creatorContractAddress][index];
  }

  // Public mint
  function mint(address creatorContractAddress, uint index, bytes32[] calldata merkleProof) external {
      // Verify merkle proof
      Listing memory listing = listings[creatorContractAddress][index];
      if (listing.merkleRoot != "") {
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        require(MerkleProof.verify(merkleProof, listing.merkleRoot, leaf), "Could not verify merkle proof");
      }

      // Check walletMax against minter's wallet
      uint walletMinted = mintsPerWallet[creatorContractAddress][index][msg.sender];
      if (listing.walletMax != 0) require(walletMinted < listing.walletMax, "Maximum tokens already minted for this wallet");
      mintsPerWallet[creatorContractAddress][index][msg.sender] = walletMinted + 1;

      // Check totalMax
      uint listingMinted = mintsPerListing[creatorContractAddress][index];
      if (listing.totalMax != 0) require(listingMinted < listing.totalMax, "Maximum tokens already minted for this listing");
      mintsPerListing[creatorContractAddress][index] = listingMinted + 1;

      // Check timestamps
      if (listing.startDate != 0) require(listing.startDate < block.timestamp, "Transaction before start date");
      if (listing.endDate != 0) require(listing.endDate >= block.timestamp, "Transaction after end date");

      // Do mint
      IERC721CreatorCore creatorCoreContract = IERC721CreatorCore(creatorContractAddress);
      uint newTokenId = creatorCoreContract.mintExtension(msg.sender);
      tokenListings[creatorContractAddress][newTokenId] = index;
  }

  function tokenURI(address creatorContractAddress, uint tokenId) external view returns(string memory) {
    uint listingIndex = tokenListings[creatorContractAddress][tokenId];
    Listing memory listing = listings[creatorContractAddress][listingIndex];
    return listing.uri;
  }
}