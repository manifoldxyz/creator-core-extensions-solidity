// SPDX-License-Identifier: MIT
// solhint-disable reason-string
pragma solidity ^0.8.0;

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC1155CreatorCore.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/ICreatorExtensionTokenURI.sol";

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "./Deck.sol";
import "./IERC1155Deck.sol";

/**
 * @title Deck Lazy Payable Claim - ERC-1155
 * @author manifold.xyz
 * @notice
 */
contract ERC1155Deck is IERC165, IERC1155Deck, ICreatorExtensionTokenURI, Deck {
  using Strings for uint256;

  // stores mapping from contractAddress/instanceId to the claim it represents
  // { contractAddress => { instanceId => Claim } }
  mapping(address => mapping(uint256 => Claim)) private _claims;

  // { contractAddress => { tokenId => { instanceId } }
  mapping(address => mapping(uint256 => uint256)) private _tokenInstances;

  function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, AdminControl) returns (bool) {
    return
      interfaceId == type(IERC1155Deck).interfaceId ||
      interfaceId == type(IDeck).interfaceId ||
      interfaceId == type(ICreatorExtensionTokenURI).interfaceId ||
      interfaceId == type(IAdminControl).interfaceId ||
      interfaceId == type(IERC165).interfaceId;
  }

  constructor(address initialOwner) Deck(initialOwner) {}

  /**
   * See {IERC1155Deck-initializeClaim}.
   */
  function initializeClaim(
    address creatorContractAddress,
    uint256 instanceId,
    ClaimParameters calldata claimParameters
  ) external payable override creatorAdminRequired(creatorContractAddress) {
    if (deprecated) {
      revert ContractDeprecated();
    }
    if (instanceId == 0 || instanceId > MAX_UINT_56) revert IDeck.InvalidInstance();
    if (_claims[creatorContractAddress][instanceId].storageProtocol != StorageProtocol.INVALID)
      revert IDeck.ClaimAlreadyInitialized();
    if (claimParameters.storageProtocol == StorageProtocol.INVALID) revert IDeck.InvalidStorageProtocol();
    if (claimParameters.tokenVariations > MAX_UINT_8) revert IDeck.InvalidInput();

    address[] memory receivers = new address[](1);
    receivers[0] = msg.sender;
    uint256[] memory amounts = new uint256[](claimParameters.tokenVariations);
    string[] memory uris = new string[](claimParameters.tokenVariations);
    uint256[] memory newTokenIds = IERC1155CreatorCore(creatorContractAddress).mintExtensionNew(receivers, amounts, uris);

    if (newTokenIds[0] > MAX_UINT_80) revert IDeck.InvalidStartingTokenId();

    // Create the claim
    _claims[creatorContractAddress][instanceId] = Claim({
      storageProtocol: claimParameters.storageProtocol,
      total: 0,
      startingTokenId: uint80(newTokenIds[0]),
      tokenVariations: claimParameters.tokenVariations,
      location: claimParameters.location
    });
    for (uint256 i; i < claimParameters.tokenVariations; ) {
      _tokenInstances[creatorContractAddress][newTokenIds[i]] = instanceId;
      unchecked {
        ++i;
      }
    }

    emit DeckClaimInitialized(creatorContractAddress, instanceId, msg.sender);
  }

  /**
   * See {IERC1155Deck-updateClaim}.
   */
  function updateClaim(
    address creatorContractAddress,
    uint256 instanceId,
    UpdateClaimParameters calldata updateClaimParameters
  ) external override creatorAdminRequired(creatorContractAddress) {
    if (deprecated) {
      revert ContractDeprecated();
    }
    Claim memory claim = _getClaim(creatorContractAddress, instanceId);
    if (instanceId == 0 || instanceId > MAX_UINT_56) revert IDeck.InvalidInstance();
    if (updateClaimParameters.storageProtocol == StorageProtocol.INVALID) revert IDeck.InvalidStorageProtocol();

    // Overwrite the existing values
    _claims[creatorContractAddress][instanceId] = Claim({
      storageProtocol: updateClaimParameters.storageProtocol,
      total: claim.total,
      startingTokenId: claim.startingTokenId,
      tokenVariations: claim.tokenVariations,
      location: updateClaimParameters.location
    });
    emit DeckClaimUpdated(creatorContractAddress, instanceId);
  }

  /**
   * See {IERC1155Deck-getClaim}.
   */
  function getClaim(address creatorContractAddress, uint256 instanceId) public view override returns (Claim memory) {
    return _getClaim(creatorContractAddress, instanceId);
  }

  /**
   * See {IERC1155Deck-getClaimForToken}.
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
    if (claim.storageProtocol == StorageProtocol.INVALID) revert IDeck.ClaimNotInitialized();
  }

  /**
   * See {IDeck-deliverMints}.
   */
  function deliverMints(IDeck.ClaimMint[] calldata mints) external override {
    _validateSigner();
    for (uint256 i; i < mints.length; ) {
      ClaimMint calldata mintData = mints[i];
       Claim memory claim = _getClaim(mintData.creatorContractAddress, mintData.instanceId);
      address[] memory receivers = new address[](mintData.variationMints.length);
      uint256[] memory amounts = new uint256[](mintData.variationMints.length);
      uint256[] memory tokenIds = new uint256[](mintData.variationMints.length);
      uint32 totalMinted;

      for (uint256 j; j < mintData.variationMints.length; ) {
        VariationMint calldata variationMint = mintData.variationMints[j];
        if (variationMint.variationIndex > MAX_UINT_8) revert IDeck.InvalidVariationIndex();
        uint8 variationIndex = variationMint.variationIndex;
        if (variationIndex > claim.tokenVariations || variationIndex < 1) revert IDeck.InvalidVariationIndex();
        address recipient = variationMint.recipient;
        if (variationMint.amount > MAX_UINT_32) revert IDeck.TooManyRequested();
        uint32 amount = variationMint.amount;
        if (claim.startingTokenId > MAX_UINT_80) revert IDeck.InvalidStartingTokenId();

        tokenIds[j] = claim.startingTokenId + variationIndex - 1;
        amounts[j] = amount;
        receivers[j] = recipient;
        totalMinted += variationMint.amount;
        unchecked {
          ++j;
        }
      }

      claim.total += totalMinted;
      IERC1155CreatorCore(mintData.creatorContractAddress).mintExtensionExisting(receivers, tokenIds, amounts);
      unchecked {
        ++i;
      }
    }
  }

  /**
   * See {ICreatorExtensionTokenURI-tokenURI}.
   */
  function tokenURI(address creatorContractAddress, uint256 tokenId) external view override returns (string memory uri) {
    uint256 instanceId = _tokenInstances[creatorContractAddress][tokenId];
    if (instanceId == 0) revert IDeck.TokenDNE();
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
   * See {IERC1155Deck-updateTokenURIParams}.
   */
  function updateTokenURIParams(
    address creatorContractAddress,
    uint256 instanceId,
    StorageProtocol storageProtocol,
    string calldata location
  ) external override creatorAdminRequired(creatorContractAddress) {
    Claim storage claim = _getClaim(creatorContractAddress, instanceId);
    if (storageProtocol == StorageProtocol.INVALID) revert IDeck.InvalidStorageProtocol();
    claim.storageProtocol = storageProtocol;
    claim.location = location;
    emit DeckClaimUpdated(creatorContractAddress, instanceId);
  }
}
