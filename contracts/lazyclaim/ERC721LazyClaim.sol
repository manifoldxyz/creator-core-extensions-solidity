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
  mapping(address => mapping(uint => uint)) public mintsPerClaim;
  mapping(address => mapping(uint => mapping(address => uint))) public mintsPerWallet;
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
    uint totalMax,
    uint walletMax,
    uint startDate,
    uint endDate
  ) external creatorAdminRequired(creatorContractAddress) {
    // Get the index for the new claim
    uint newIndex = claimCounts[creatorContractAddress];
    claimCounts[creatorContractAddress] = newIndex + 1;

    // Create the claim
    claims[creatorContractAddress][newIndex] = Claim({
      merkleRoot: merkleRoot,
      uri: uri,
      totalMax: totalMax,
      walletMax: walletMax,
      startDate: startDate,
      endDate: endDate
    });
  }

  // Update & Setters
  function overwriteClaim(
    address creatorContractAddress,
    uint index,
    bytes32 merkleRoot,
    string calldata uri,
    uint totalMax,
    uint walletMax,
    uint startDate,
    uint endDate
  ) external creatorAdminRequired(creatorContractAddress) {
    // Overwrite the existing claim
    claims[creatorContractAddress][index] = Claim({
      merkleRoot: merkleRoot,
      uri: uri,
      totalMax: totalMax,
      walletMax: walletMax,
      startDate: startDate,
      endDate: endDate
    });
  }
  function setMerkleRoot(address creatorContractAddress, uint index, bytes32 merkleRoot) external {
    Claim memory claim = claims[creatorContractAddress][index];
    claim.merkleRoot = merkleRoot;
    claims[creatorContractAddress][index] = claim;
  }
  function setURI(address creatorContractAddress, uint index, string calldata uri) external {
    Claim memory claim = claims[creatorContractAddress][index];
    claim.uri = uri;
    claims[creatorContractAddress][index] = claim;
  }
  function setTotalMax(address creatorContractAddress, uint index, uint totalMax) external {
    Claim memory claim = claims[creatorContractAddress][index];
    claim.totalMax = totalMax;
    claims[creatorContractAddress][index] = claim;
  }
  function setWalletMax(address creatorContractAddress, uint index, uint walletMax) external {
    Claim memory claim = claims[creatorContractAddress][index];
    claim.walletMax = walletMax;
    claims[creatorContractAddress][index] = claim;
  }
  function setStartDate(address creatorContractAddress, uint index, uint startDate) external {
    Claim memory claim = claims[creatorContractAddress][index];
    claim.startDate = startDate;
    claims[creatorContractAddress][index] = claim;
  }
  function setEndDate(address creatorContractAddress, uint index, uint endDate) external {
    Claim memory claim = claims[creatorContractAddress][index];
    claim.endDate = endDate;
    claims[creatorContractAddress][index] = claim;
  }

  // Public getters
  function getClaimCount(address creatorContractAddress) external view returns(uint) {
    return claimCounts[creatorContractAddress];
  }
  function getClaim(address creatorContractAddress, uint index) external view returns(Claim memory) {
    return claims[creatorContractAddress][index];
  }

  // Public mint
  function mint(address creatorContractAddress, uint index, bytes32[] calldata merkleProof, uint minterValue) external {
      // Verify merkle proof
      Claim memory claim = claims[creatorContractAddress][index];
      if (claim.merkleRoot != "") {
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, minterValue));
        require(MerkleProof.verify(merkleProof, claim.merkleRoot, leaf), "Could not verify merkle proof");

        if (minterValue != 0) {
          uint allocationMinted = mintsPerWallet[creatorContractAddress][index][msg.sender];
          require(allocationMinted < minterValue, "Maximum tokens already minted for this wallet per allocation");
        }
      }

      // Check walletMax against minter's wallet
      uint walletMinted = mintsPerWallet[creatorContractAddress][index][msg.sender];
      if (claim.walletMax != 0) require(walletMinted < claim.walletMax, "Maximum tokens already minted for this wallet");

      // Check totalMax
      uint claimMinted = mintsPerClaim[creatorContractAddress][index];
      if (claim.totalMax != 0) require(claimMinted < claim.totalMax, "Maximum tokens already minted for this claim");

      mintsPerWallet[creatorContractAddress][index][msg.sender] = walletMinted + 1;
      mintsPerClaim[creatorContractAddress][index] = claimMinted + 1;

      // Check timestamps
      if (claim.startDate != 0) require(claim.startDate < block.timestamp, "Transaction before start date");
      if (claim.endDate != 0) require(claim.endDate >= block.timestamp, "Transaction after end date");

      // Do mint
      IERC721CreatorCore creatorCoreContract = IERC721CreatorCore(creatorContractAddress);
      uint newTokenId = creatorCoreContract.mintExtension(msg.sender);
      tokenClaims[creatorContractAddress][newTokenId] = index;
  }

  function tokenURI(address creatorContractAddress, uint tokenId) external view returns(string memory) {
    uint claimIndex = tokenClaims[creatorContractAddress][tokenId];
    Claim memory claim = claims[creatorContractAddress][claimIndex];
    return claim.uri;
  }
}
