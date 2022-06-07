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
  mapping(address => uint) public claimCounts;
  mapping(address => mapping(uint => Claim)) public claims;
  mapping(address => mapping(uint => mapping(address => uint32))) public mintsPerWallet;
  mapping(address => mapping(uint => uint)) public tokenClaims;

  function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165) returns (bool) {
    return interfaceId == type(IERC721LazyClaim).interfaceId ||
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
  function initializeClaim(
    address creatorContractAddress,
    bytes32 merkleRoot,
    string calldata uri,
    uint32 totalMax,
    uint32 walletMax,
    uint48 startDate,
    uint48 endDate,
    StorageProtocol storageProtocol,
    bool identical
  ) external creatorAdminRequired(creatorContractAddress) {
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
      uri: uri
    });
  }

  // Update
  function overwriteClaim(
    address creatorContractAddress,
    uint index,
    bytes32 merkleRoot,
    string calldata uri,
    uint32 totalMax,
    uint32 walletMax,
    uint48 startDate,
    uint48 endDate,
    StorageProtocol storageProtocol,
    bool identical
  ) external creatorAdminRequired(creatorContractAddress) {
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
      uri: uri
    });
  }

  // Public getters
  function getClaimCount(address creatorContractAddress) external view returns(uint) {
    return claimCounts[creatorContractAddress];
  }
  function getClaim(address creatorContractAddress, uint index) external view returns(Claim memory) {
    return claims[creatorContractAddress][index];
  }
  function getWalletMinted(address creatorContractAddress, uint index) external view returns(uint32) {
    return mintsPerWallet[creatorContractAddress][index][msg.sender];
  }

  // Public mint
  function mint(address creatorContractAddress, uint index, bytes32[] calldata merkleProof, uint32 minterValue) external {
      // Verify merkle proof
      Claim storage claim = claims[creatorContractAddress][index];
      if (claim.merkleRoot != "") {
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, minterValue));
        require(MerkleProof.verify(merkleProof, claim.merkleRoot, leaf), "Could not verify merkle proof");

        if (minterValue != 0) {
          uint allocationMinted = mintsPerWallet[creatorContractAddress][index][msg.sender];
          require(allocationMinted < minterValue, "Maximum tokens already minted for this wallet per allocation");
        }
      }

      // Check walletMax against minter's wallet
      if (claim.walletMax != 0) {
        require(mintsPerWallet[creatorContractAddress][index][msg.sender] < claim.walletMax, "Maximum tokens already minted for this wallet");
      }

      // Check totalMax
      if (claim.totalMax != 0) {
        require(claim.total < claim.totalMax, "Maximum tokens already minted for this claim");
      }

      // Check timestamps
      if (claim.startDate != 0) require(claim.startDate < block.timestamp, "Transaction before start date");
      if (claim.endDate != 0) require(claim.endDate >= block.timestamp, "Transaction after end date");

      // Do mint
      IERC721CreatorCore creatorCoreContract = IERC721CreatorCore(creatorContractAddress);
      uint newTokenId = creatorCoreContract.mintExtension(msg.sender);
      tokenClaims[creatorContractAddress][newTokenId] = index;

      unchecked{ mintsPerWallet[creatorContractAddress][index][msg.sender]++; }
      unchecked{ claim.total++; }
  }

  function tokenURI(address creatorContractAddress, uint tokenId) external view returns(string memory) {
    uint claimIndex = tokenClaims[creatorContractAddress][tokenId];
    return claims[creatorContractAddress][claimIndex].uri;
  }
}
