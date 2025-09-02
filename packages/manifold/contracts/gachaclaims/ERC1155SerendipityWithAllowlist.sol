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

import "./Serendipity.sol";
import "./IERC1155SerendipityWithAllowlist.sol";

/**
 * @title Serendipity Lazy Payable Claim with Allowlist - ERC-1155
 * @author manifold.xyz
 * @notice ERC1155 Serendipity with merkle tree allowlist support
 */
contract ERC1155SerendipityWithAllowlist is IERC165, IERC1155SerendipityWithAllowlist, ICreatorExtensionTokenURI, Serendipity {
  using Strings for uint256;

  uint256 internal constant MINT_INDEX_BITMASK = 0xFF;

  // stores mapping from contractAddress/instanceId to the claim it represents
  // { contractAddress => { instanceId => Claim } }
  mapping(address => mapping(uint256 => Claim)) private _claims;

  // { contractAddress => { tokenId => { instanceId } }
  mapping(address => mapping(uint256 => uint256)) private _tokenInstances;

  // ONLY USED FOR MERKLE MINTS: stores mapping from claim to indices minted
  // { contractAddress => {instanceId => { instanceIdOffset => index } } }
  mapping(address => mapping(uint256 => mapping(uint256 => uint256))) private _claimMintIndices;

  // ONLY USED FOR NON-MERKLE MINTS: stores the number of tokens minted per wallet per claim, in order to limit maximum
  // { contractAddress => { instanceId => { walletAddress => walletMints } } }
  mapping(address => mapping(uint256 => mapping(address => uint256))) private _mintsPerWallet;

  function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, AdminControl) returns (bool) {
    return
      interfaceId == type(IERC1155SerendipityWithAllowlist).interfaceId ||
      interfaceId == type(ISerendipity).interfaceId ||
      interfaceId == type(ICreatorExtensionTokenURI).interfaceId ||
      interfaceId == type(IAdminControl).interfaceId ||
      interfaceId == type(IERC165).interfaceId;
  }

  constructor(address initialOwner) Serendipity(initialOwner) {}

  /**
   * See {IERC1155SerendipityWithAllowlist-initializeClaim}.
   */
  function initializeClaim(
    address creatorContractAddress,
    uint256 instanceId,
    ClaimParameters calldata claimParameters
  ) external payable override creatorAdminRequired(creatorContractAddress) {
    if (deprecated) {
      revert ContractDeprecated();
    }
    if (instanceId == 0 || instanceId > MAX_UINT_56) revert ISerendipity.InvalidInstance();
    if (_claims[creatorContractAddress][instanceId].storageProtocol != StorageProtocol.INVALID)
      revert ISerendipity.ClaimAlreadyInitialized();
    // Checks
    if (claimParameters.storageProtocol == StorageProtocol.INVALID) revert ISerendipity.InvalidStorageProtocol();
    if (claimParameters.endDate != 0 && claimParameters.startDate >= claimParameters.endDate)
      revert ISerendipity.InvalidDate();
    if (claimParameters.totalMax > MAX_UINT_32) revert ISerendipity.InvalidInput();
    if (claimParameters.tokenVariations > MAX_UINT_8) revert ISerendipity.InvalidInput();
    if (claimParameters.cost > MAX_UINT_96) revert ISerendipity.InvalidInput();

    address[] memory receivers = new address[](1);
    receivers[0] = msg.sender;
    uint256[] memory amounts = new uint256[](claimParameters.tokenVariations);
    string[] memory uris = new string[](claimParameters.tokenVariations);
    uint256[] memory newTokenIds = IERC1155CreatorCore(creatorContractAddress).mintExtensionNew(receivers, amounts, uris);

    if (newTokenIds[0] > MAX_UINT_80) revert ISerendipity.InvalidStartingTokenId();

    // Create the claim
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
   * See {IERC1155SerendipityWithAllowlist-updateClaim}.
   */
  function updateClaim(
    address creatorContractAddress,
    uint256 instanceId,
    UpdateClaimParameters memory updateClaimParameters
  ) external override creatorAdminRequired(creatorContractAddress) {
    if (deprecated) {
      revert ContractDeprecated();
    }
    Claim memory claim = _getClaim(creatorContractAddress, instanceId);
    if (instanceId == 0 || instanceId > MAX_UINT_56) revert ISerendipity.InvalidInstance();
    if (updateClaimParameters.endDate != 0 && updateClaimParameters.startDate >= updateClaimParameters.endDate)
      revert ISerendipity.InvalidDate();
    if (updateClaimParameters.totalMax != 0 && updateClaimParameters.totalMax < claim.total) revert ISerendipity.CannotLowerTotalMaxBeyondTotal();
    if (updateClaimParameters.totalMax > MAX_UINT_32) revert ISerendipity.InvalidInput();
    if (updateClaimParameters.storageProtocol == StorageProtocol.INVALID) revert ISerendipity.InvalidStorageProtocol();
    if (updateClaimParameters.cost > MAX_UINT_96) revert ISerendipity.InvalidInput();

    // Overwrite the existing values
    _claims[creatorContractAddress][instanceId] = Claim({
      storageProtocol: updateClaimParameters.storageProtocol,
      total: claim.total,
      totalMax: updateClaimParameters.totalMax,
      startDate: updateClaimParameters.startDate,
      endDate: updateClaimParameters.endDate,
      startingTokenId: claim.startingTokenId,
      tokenVariations: claim.tokenVariations,
      location: updateClaimParameters.location,
      paymentReceiver: updateClaimParameters.paymentReceiver,
      cost: updateClaimParameters.cost,
      erc20: claim.erc20,
      merkleRoot: updateClaimParameters.merkleRoot,
      walletMax: updateClaimParameters.walletMax
    });
    emit SerendipityClaimUpdated(creatorContractAddress, instanceId);
  }

  /**
   * See {IERC1155SerendipityWithAllowlist-getClaim}.
   */
  function getClaim(address creatorContractAddress, uint256 instanceId) public view override returns (Claim memory) {
    return _getClaim(creatorContractAddress, instanceId);
  }

  /**
   * See {IERC1155SerendipityWithAllowlist-getClaimForToken}.
   */
  function getClaimForToken(
    address creatorContractAddress,
    uint256 tokenId
  ) external view override returns (uint256 instanceId, Claim memory claim) {
    instanceId = _tokenInstances[creatorContractAddress][tokenId];
    claim = _getClaim(creatorContractAddress, instanceId);
  }

  function _getClaim(address creatorContractAddress, uint256 instanceId) private view returns (Claim storage claim) {
    claim = _claims[creatorContractAddress][instanceId];
    if (claim.storageProtocol == StorageProtocol.INVALID) revert ISerendipity.ClaimNotInitialized();
  }

  /**
   * See {ISerendipity-mintReserve}. (Legacy function for non-merkle claims)
   */
  function mintReserve(address creatorContractAddress, uint256 instanceId, uint32 mintCount) external payable override {
    if (Address.isContract(msg.sender)) revert ISerendipity.CannotMintFromContract();
    Claim storage claim = _getClaim(creatorContractAddress, instanceId);
    
    // This function is only for non-merkle claims
    if (claim.merkleRoot != bytes32(0)) revert ISerendipity.InvalidInput();
    
    // Checks for reserving
    if (mintCount == 0 || mintCount >= MAX_UINT_32) revert ISerendipity.InvalidMintCount();
    if (claim.startDate > block.timestamp || (claim.endDate > 0 && claim.endDate < block.timestamp))
      revert ISerendipity.ClaimInactive();
    if (claim.totalMax != 0 && claim.total == claim.totalMax) revert ISerendipity.ClaimSoldOut();
    if (claim.total == MAX_UINT_32) revert ISerendipity.TooManyRequested();
    if (msg.value != (claim.cost + MINT_FEE) * mintCount) revert ISerendipity.InvalidPayment();
    
    // Check wallet max for non-merkle claims
    if (claim.walletMax != 0) {
      uint256 currentMints = _mintsPerWallet[creatorContractAddress][instanceId][msg.sender];
      if (currentMints + mintCount > claim.walletMax) revert ISerendipity.TooManyRequested();
      _mintsPerWallet[creatorContractAddress][instanceId][msg.sender] = currentMints + mintCount;
    }
    
    // calculate the amount to reserve and update totals
    uint32 amountToReserve = mintCount;
    if (claim.totalMax != 0) {
      amountToReserve = uint32(Math.min(mintCount, claim.totalMax - claim.total));
    }
    claim.total += amountToReserve;
    _mintDetailsPerWallet[creatorContractAddress][instanceId][msg.sender].reservedCount += amountToReserve;
    if (claim.cost > 0) {
      _sendFunds(claim.paymentReceiver, claim.cost * amountToReserve);
    }
    // Refund any overpayment
    if (amountToReserve != mintCount) {
      uint256 refundAmount = msg.value - (claim.cost + MINT_FEE) * amountToReserve;
      _sendFunds(payable(msg.sender), refundAmount);
    }
    emit SerendipityMintReserved(creatorContractAddress, instanceId, msg.sender, amountToReserve);
  }

  /**
   * See {ISerendipity-deliverMints}.
   */
  function deliverMints(ISerendipity.ClaimMint[] calldata mints) external override {
    _validateSigner();
    for (uint256 i; i < mints.length; ) {
      ClaimMint calldata mintData = mints[i];
      Claim memory claim = _getClaim(mintData.creatorContractAddress, mintData.instanceId);
      address[] memory receivers = new address[](mintData.variationMints.length);
      uint256[] memory amounts = new uint256[](mintData.variationMints.length);
      uint256[] memory tokenIds = new uint256[](mintData.variationMints.length);

      for (uint256 j; j < mintData.variationMints.length; ) {
        VariationMint calldata variationMint = mintData.variationMints[j];
        if (variationMint.variationIndex > MAX_UINT_8) revert ISerendipity.InvalidVariationIndex();
        uint8 variationIndex = variationMint.variationIndex;
        if (variationIndex > claim.tokenVariations || variationIndex < 1) revert ISerendipity.InvalidVariationIndex();
        address recipient = variationMint.recipient;
        if (variationMint.amount > MAX_UINT_32) revert ISerendipity.TooManyRequested();
        uint32 amount = variationMint.amount;
        UserMintDetails storage userMintDetails = _mintDetailsPerWallet[mintData.creatorContractAddress][
          mintData.instanceId
        ][recipient];

        if (userMintDetails.deliveredCount + amount > userMintDetails.reservedCount)
          revert ISerendipity.CannotMintMoreThanReserved();
        if (claim.startingTokenId > MAX_UINT_80) revert ISerendipity.InvalidStartingTokenId();
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
   * See {ISerendipity-getUserMints}.
   */
  function getUserMints(
    address minter,
    address creatorContractAddress,
    uint256 instanceId
  ) external view override returns (UserMintDetails memory) {
    return _getUserMints(minter, creatorContractAddress, instanceId);
  }

  /**
   * See {IERC1155SerendipityWithAllowlist-mintReserve} - Single merkle proof version.
   */
  function mintReserve(
    address creatorContractAddress,
    uint256 instanceId,
    uint32 mintIndex,
    bytes32[] calldata merkleProof,
    uint32 mintCount
  ) external payable override {
    if (Address.isContract(msg.sender)) revert ISerendipity.CannotMintFromContract();
    Claim storage claim = _getClaim(creatorContractAddress, instanceId);
    
    // This function is only for merkle claims
    if (claim.merkleRoot == bytes32(0)) revert ISerendipity.InvalidInput();
    
    // Basic validation
    if (mintCount == 0 || mintCount >= MAX_UINT_32) revert ISerendipity.InvalidMintCount();
    if (claim.startDate > block.timestamp || (claim.endDate > 0 && claim.endDate < block.timestamp))
      revert ISerendipity.ClaimInactive();
    if (claim.totalMax != 0 && claim.total == claim.totalMax) revert ISerendipity.ClaimSoldOut();
    if (claim.total == MAX_UINT_32) revert ISerendipity.TooManyRequested();
    if (msg.value != (claim.cost + MINT_FEE) * mintCount) revert ISerendipity.InvalidPayment();
    
    // Merkle validation
    _checkMerkleAndUpdate(creatorContractAddress, instanceId, claim.merkleRoot, mintIndex, merkleProof, msg.sender);
    
    // calculate the amount to reserve and update totals
    uint32 amountToReserve = mintCount;
    if (claim.totalMax != 0) {
      amountToReserve = uint32(Math.min(mintCount, claim.totalMax - claim.total));
    }
    claim.total += amountToReserve;
    _mintDetailsPerWallet[creatorContractAddress][instanceId][msg.sender].reservedCount += amountToReserve;
    if (claim.cost > 0) {
      _sendFunds(claim.paymentReceiver, claim.cost * amountToReserve);
    }
    // Refund any overpayment
    if (amountToReserve != mintCount) {
      uint256 refundAmount = msg.value - (claim.cost + MINT_FEE) * amountToReserve;
      _sendFunds(payable(msg.sender), refundAmount);
    }
    emit SerendipityMintReserved(creatorContractAddress, instanceId, msg.sender, amountToReserve);
  }

  /**
   * See {IERC1155SerendipityWithAllowlist-mintReserve} - Multiple merkle proofs version.
   */
  function mintReserve(
    address creatorContractAddress,
    uint256 instanceId,
    uint32[] calldata mintIndices,
    bytes32[][] calldata merkleProofs,
    uint32[] calldata mintCounts
  ) external payable override {
    if (Address.isContract(msg.sender)) revert ISerendipity.CannotMintFromContract();
    Claim storage claim = _getClaim(creatorContractAddress, instanceId);
    
    // This function is only for merkle claims
    if (claim.merkleRoot == bytes32(0)) revert ISerendipity.InvalidInput();
    
    // Array length validation
    if (mintIndices.length != merkleProofs.length || mintIndices.length != mintCounts.length) 
      revert ISerendipity.InvalidInput();
    if (mintIndices.length == 0) revert ISerendipity.InvalidInput();
    
    // Basic validation
    if (claim.startDate > block.timestamp || (claim.endDate > 0 && claim.endDate < block.timestamp))
      revert ISerendipity.ClaimInactive();
    if (claim.totalMax != 0 && claim.total == claim.totalMax) revert ISerendipity.ClaimSoldOut();
    if (claim.total == MAX_UINT_32) revert ISerendipity.TooManyRequested();
    
    uint32 totalMintCount = 0;
    for (uint256 i = 0; i < mintCounts.length; i++) {
      if (mintCounts[i] == 0 || mintCounts[i] >= MAX_UINT_32) revert ISerendipity.InvalidMintCount();
      totalMintCount += mintCounts[i];
      // Validate each merkle proof
      _checkMerkleAndUpdate(creatorContractAddress, instanceId, claim.merkleRoot, mintIndices[i], merkleProofs[i], msg.sender);
    }
    
    if (msg.value != (claim.cost + MINT_FEE) * totalMintCount) revert ISerendipity.InvalidPayment();
    
    // calculate the amount to reserve and update totals
    uint32 amountToReserve = totalMintCount;
    if (claim.totalMax != 0) {
      amountToReserve = uint32(Math.min(totalMintCount, claim.totalMax - claim.total));
    }
    claim.total += amountToReserve;
    _mintDetailsPerWallet[creatorContractAddress][instanceId][msg.sender].reservedCount += amountToReserve;
    if (claim.cost > 0) {
      _sendFunds(claim.paymentReceiver, claim.cost * amountToReserve);
    }
    // Refund any overpayment
    if (amountToReserve != totalMintCount) {
      uint256 refundAmount = msg.value - (claim.cost + MINT_FEE) * amountToReserve;
      _sendFunds(payable(msg.sender), refundAmount);
    }
    emit SerendipityMintReserved(creatorContractAddress, instanceId, msg.sender, amountToReserve);
  }

  /**
   * See {ICreatorExtensionTokenURI-tokenURI}.
   */
  function tokenURI(address creatorContractAddress, uint256 tokenId) external view override returns (string memory uri) {
    uint256 instanceId = _tokenInstances[creatorContractAddress][tokenId];
    if (instanceId == 0) revert ISerendipity.TokenDNE();
    Claim memory claim = _getClaim(creatorContractAddress, instanceId);

    string memory prefix = "";
    if (claim.storageProtocol == StorageProtocol.ARWEAVE) {
      prefix = ARWEAVE_PREFIX;
    } else if (claim.storageProtocol == StorageProtocol.IPFS) {
      prefix = IPFS_PREFIX;
    }
    uri = string(abi.encodePacked(prefix, claim.location, "/", Strings.toString(tokenId - claim.startingTokenId + 1)));
  }

  /**
   * See {IERC1155SerendipityWithAllowlist-checkMintIndex}.
   */
  function checkMintIndex(address creatorContractAddress, uint256 instanceId, uint32 mintIndex) external view override returns (bool) {
    Claim memory claim = _getClaim(creatorContractAddress, instanceId);
    if (claim.merkleRoot == bytes32(0)) revert ISerendipity.InvalidInput();
    return _checkMintIndex(creatorContractAddress, instanceId, claim.merkleRoot, mintIndex);
  }

  /**
   * See {IERC1155SerendipityWithAllowlist-checkMintIndices}.
   */
  function checkMintIndices(address creatorContractAddress, uint256 instanceId, uint32[] calldata mintIndices) external view override returns (bool[] memory) {
    Claim memory claim = _getClaim(creatorContractAddress, instanceId);
    if (claim.merkleRoot == bytes32(0)) revert ISerendipity.InvalidInput();
    
    bool[] memory results = new bool[](mintIndices.length);
    for (uint256 i = 0; i < mintIndices.length; i++) {
      results[i] = _checkMintIndex(creatorContractAddress, instanceId, claim.merkleRoot, mintIndices[i]);
    }
    return results;
  }

  /**
   * See {IERC1155SerendipityWithAllowlist-getTotalMints}.
   */
  function getTotalMints(address creatorContractAddress, uint256 instanceId, address minter) external view override returns (uint32) {
    Claim memory claim = _getClaim(creatorContractAddress, instanceId);
    if (claim.merkleRoot != bytes32(0)) revert ISerendipity.InvalidInput();
    if (claim.walletMax == 0) revert ISerendipity.InvalidInput();
    return uint32(_mintsPerWallet[creatorContractAddress][instanceId][minter]);
  }

  /**
   * See {IERC1155SerendipityWithAllowlist-updateTokenURIParams}.
   */
  function updateTokenURIParams(
    address creatorContractAddress,
    uint256 instanceId,
    StorageProtocol storageProtocol,
    string calldata location
  ) external override creatorAdminRequired(creatorContractAddress) {
    Claim storage claim = _getClaim(creatorContractAddress, instanceId);
    if (storageProtocol == StorageProtocol.INVALID) revert ISerendipity.InvalidStorageProtocol();
    claim.storageProtocol = storageProtocol;
    claim.location = location;
    emit SerendipityClaimUpdated(creatorContractAddress, instanceId);
  }

  // Private helper functions
  function _checkMintIndex(address creatorContractAddress, uint256 instanceId, bytes32 merkleRoot, uint32 mintIndex)
    private
    view
    returns (bool)
  {
    uint256 claimMintIndex = mintIndex >> 8;
    require(merkleRoot != bytes32(0), "Can only check merkle claims");
    uint256 claimMintTracking = _claimMintIndices[creatorContractAddress][instanceId][claimMintIndex];
    uint256 mintBitmask = 1 << (mintIndex & MINT_INDEX_BITMASK);
    return mintBitmask & claimMintTracking != 0;
  }

  function _checkMerkleAndUpdate(
    address creatorContractAddress,
    uint256 instanceId,
    bytes32 merkleRoot,
    uint32 mintIndex,
    bytes32[] memory merkleProof,
    address mintFor
  ) private {
    // Merkle mint - create the leaf
    bytes32 leaf = keccak256(abi.encodePacked(mintFor, mintIndex));
    require(MerkleProof.verify(merkleProof, merkleRoot, leaf), "Could not verify merkle proof");

    // Check if mintIndex has been minted
    uint256 claimMintIndex = mintIndex >> 8;
    uint256 claimMintTracking = _claimMintIndices[creatorContractAddress][instanceId][claimMintIndex];
    uint256 mintBitmask = 1 << (mintIndex & MINT_INDEX_BITMASK);
    require(mintBitmask & claimMintTracking == 0, "Already minted");
    _claimMintIndices[creatorContractAddress][instanceId][claimMintIndex] = claimMintTracking | mintBitmask;
  }
}
