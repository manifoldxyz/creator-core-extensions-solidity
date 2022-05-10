// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC721CreatorCore.sol";
import "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";

import "../libraries/ABDKMath64x64.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import "./IERC721LazyMint.sol";

/**
 * Lazy mint with whitelist ERC721 tokens
 */
contract ERC721LazyMint is IERC721LazyMint, ReentrancyGuard {
  using Strings for uint256;
  using ABDKMath64x64 for uint;

  mapping(address => Listing) public listings;
  mapping(address => mapping(address => uint256)) private listingTokenEditions;

  function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
    return interfaceId == type(IERC721LazyMint).interfaceId;
  }

  modifier creatorAdminRequired(address creatorContractAddress) {
    // This is not a single-creator extension, so we must ensure that the initializer is an admin of the contract
    AdminControl creatorCoreContract = AdminControl(creatorContractAddress);
    require(creatorCoreContract.isAdmin(msg.sender), "Wallet is not an administrator for contract");
    _;
  }

  function initializeListing(
    address creatorContractAddress,
    bytes32 merkleRoot,
    string calldata uri
  ) external creatorAdminRequired(creatorContractAddress) {
    // Ensure initialization is only possible once
    require(!(listings[creatorContractAddress].initialized), "Already initialized");

    // Create the listing!
    Listing memory listing = Listing({
      merkleRoot: merkleRoot,
      uri: uri,
      initialized: true
    });

    listings[creatorContractAddress] = listing;
  }

  function getListing(address creatorContractAddress) external view returns(Listing memory) {
    return listings[creatorContractAddress];
  }

  function mint(address creatorContractAddress, bytes32[] calldata merkleProof) external {
      // Verify merkle proof
      Listing memory listing = listings[creatorContractAddress];
      bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
      require(MerkleProof.verify(merkleProof, listing.merkleRoot, leaf), "Could not verify merkle proof");

      // Check for previous mints
      require(listingTokenEditions[creatorContractAddress][msg.sender] == 0, "Wallet already minted for this contract");

      // Update listing
      listingTokenEditions[creatorContractAddress][msg.sender] = 1;

      // Do mint
      IERC721CreatorCore creatorCoreContract = IERC721CreatorCore(creatorContractAddress);
      creatorCoreContract.mintExtension(msg.sender, listing.uri);
  }
}
