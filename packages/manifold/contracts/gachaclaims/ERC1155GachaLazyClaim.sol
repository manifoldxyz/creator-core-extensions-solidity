// SPDX-License-Identifier: MIT
// solhint-disable reason-string
pragma solidity ^0.8.0;

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC1155CreatorCore.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/ICreatorExtensionTokenURI.sol";

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";


import "./GachaLazyClaim.sol";
import "./IERC1155GachaLazyClaim.sol";

/**
 * @title Gacha Lazy 1155 Payable Claim
 * @author manifold.xyz
 * @notice
 */
contract ERC1155GachaLazyClaim is IERC165, IERC1155GachaLazyClaim, ICreatorExtensionTokenURI, GachaLazyClaim {
  using Strings for uint256;

  // stores mapping from contractAddress/instanceId to the claim it represents
  // { contractAddress => { instanceId => Claim } }
  mapping(address => mapping(uint256 => Claim)) private _claims;

  // { contractAddress => { tokenId => { instanceId } }
  mapping(address => mapping(uint256 => uint256)) private _tokenInstances;

  function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, AdminControl) returns (bool) {
    return
      interfaceId == type(IERC1155GachaLazyClaim).interfaceId ||
      interfaceId == type(IGachaLazyClaim).interfaceId ||
      interfaceId == type(ICreatorExtensionTokenURI).interfaceId ||
      interfaceId == type(IAdminControl).interfaceId ||
      interfaceId == type(IERC165).interfaceId;
  }

  constructor(address initialOwner) GachaLazyClaim(initialOwner) {}

  /**
   * See {IERC1155GachaLazyClaim-initializeClaim}.
   */
  function initializeClaim(
    address creatorContractAddress,
    uint256 instanceId,
    ClaimParameters calldata claimParameters
  ) external payable override adminRequired {
    if (instanceId == 0 || instanceId > MAX_UINT_56) revert IGachaLazyClaim.InvalidInstance();

    // Checks
    if (claimParameters.storageProtocol == StorageProtocol.INVALID) revert IGachaLazyClaim.InvalidStorageProtocol();
    if (claimParameters.startDate >= claimParameters.endDate) revert IGachaLazyClaim.InvalidStartDate();
    
    address[] memory receivers = new address[](1);
    receivers[0] = msg.sender;
    uint256[] memory amounts = new uint256[](claimParameters.itemVariations);
    string[] memory uris = new string[](claimParameters.itemVariations);
    uint256[] memory newTokenIds = IERC1155CreatorCore(creatorContractAddress).mintExtensionNew(receivers, amounts, uris);

    require(newTokenIds[0] <= MAX_UINT_80, "Token ID exceeds uint80 range");

    // Create the claim
    _claims[creatorContractAddress][instanceId] = Claim({
      storageProtocol: claimParameters.storageProtocol,
      total: 0,
      totalMax: claimParameters.totalMax,
      startDate: claimParameters.startDate,
      endDate: claimParameters.endDate,
      startingTokenId: uint80(newTokenIds[0]),
      itemVariations: claimParameters.itemVariations,
      location: claimParameters.location,
      paymentReceiver: claimParameters.paymentReceiver,
      cost: claimParameters.cost,
      erc20: claimParameters.erc20
    });
    for (uint8 i; i < claimParameters.itemVariations; i++) {
      _tokenInstances[creatorContractAddress][newTokenIds[i]] = instanceId;
    }

    emit GachaClaimInitialized(creatorContractAddress, instanceId, msg.sender);
  }

  /**
   * See {IERC1155GachaLazyClaim-updateClaim}.
   */
  function updateClaim(
    address creatorContractAddress,
    uint256 instanceId,
    ClaimParameters memory claimParameters
  ) external override adminRequired {
    Claim memory claim = _getClaim(creatorContractAddress, instanceId);
    if (claimParameters.endDate != 0 && claimParameters.startDate >= claimParameters.endDate)
      revert IGachaLazyClaim.InvalidStartDate();
    if (claimParameters.totalMax != claim.totalMax) revert IGachaLazyClaim.CannotChangeTotalMax();
    if (claimParameters.startingTokenId != claim.startingTokenId) revert IGachaLazyClaim.CannotChangeStartingTokenId();
    if (claimParameters.itemVariations != claim.itemVariations) revert IGachaLazyClaim.CannotChangeItemVariations();
    if (claimParameters.storageProtocol == StorageProtocol.INVALID) revert IGachaLazyClaim.InvalidStorageProtocol();
    if (keccak256(abi.encodePacked(claimParameters.location)) != keccak256(abi.encodePacked(claim.location))) {
      revert IGachaLazyClaim.CannotChangeLocation();
    }
    if (claimParameters.paymentReceiver != claim.paymentReceiver) revert IGachaLazyClaim.CannotChangePaymentReceiver();
    if (claimParameters.erc20 != claim.erc20) revert IGachaLazyClaim.CannotChangePaymentToken();

    // Overwrite the existing values for startDate, endDate, and cost
    _claims[creatorContractAddress][instanceId] = Claim({
      storageProtocol: claim.storageProtocol,
      total: claim.total,
      totalMax: claim.totalMax,
      startDate: claimParameters.startDate,
      endDate: claimParameters.endDate,
      startingTokenId: claim.startingTokenId,
      itemVariations: claim.itemVariations,
      location: claim.location,
      paymentReceiver: claim.paymentReceiver,
      cost: claimParameters.cost,
      erc20: claim.erc20
    });
    emit GachaClaimUpdated(creatorContractAddress, instanceId);
  }

  /**
   * See {IERC1155GachaLazyClaim-getClaim}.
   */
  function getClaim(address creatorContractAddress, uint256 instanceId) public view override returns (Claim memory) {
    return _getClaim(creatorContractAddress, instanceId);
  }

  /**
   * See {IERC1155GachaLazyClaim-getClaimForToken}.
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
    if (claim.storageProtocol == StorageProtocol.INVALID) revert IGachaLazyClaim.ClaimNotInitialized();
  }

  /**
   * See {IGachaLazyClaim-mintReserve}.
   */
  function mintReserve(address creatorContractAddress, uint256 instanceId, uint32 mintCount) external payable override {
    require(!Address.isContract(msg.sender), "Only EOAs can reserve a mint.");
    _mintReserve(creatorContractAddress, instanceId, mintCount);
  }

  function _mintReserve(address creatorContractAddress, uint256 instanceId, uint32 mintCount) private {
    Claim storage claim = _getClaim(creatorContractAddress, instanceId);
    // Checks for reserving
    if (claim.startDate > block.timestamp) revert IGachaLazyClaim.ClaimInactive();
    if (claim.endDate > 0 && claim.endDate < block.timestamp) revert IGachaLazyClaim.ClaimInactive();
    require(msg.value == (claim.cost + MINT_FEE) * mintCount, "Incorrect payment amount");
    uint32 amountAvailable = claim.totalMax - claim.total;
    if (amountAvailable == 0 ) revert IGachaLazyClaim.ClaimSoldOut();

    // calculate the amount to reserve and update totals
    uint32 amountToReserve = uint32(Math.min(mintCount, amountAvailable));
    claim.total += amountToReserve;
    _reservedMintsPerWallet[creatorContractAddress][instanceId][msg.sender] += amountToReserve;

    // Refund any overpayment
    if (amountToReserve < mintCount) {
      uint256 refundAmount = (mintCount - amountToReserve) * (claim.cost + MINT_FEE);
      _sendFunds(payable(msg.sender), refundAmount);
    }
    emit GachaClaimMintReserved(creatorContractAddress, instanceId, msg.sender, amountToReserve);
  }

  /**
   * See {IGachaLazyClaim-deliverMints}.
   */
  function deliverMints(IGachaLazyClaim.Mint[] calldata mints) external override {
    _validateSigner();
    _mint(mints);
  }

  function _mint(Mint[] calldata mints) private {
    for (uint256 i; i < mints.length; ) {
      Mint calldata mintData = mints[i];
      _mintClaim(mintData);
      _deliveredMintsPerWallet[mintData.creatorContractAddress][mintData.instanceId][mintData.recipients[i].receiver]++;
      unchecked {
        ++i;
      }
    }
  }

  /**
   * Mint a claim
   * at this point we have already accepted payment and now it's time to deliver the token with be generated variation
   */
  function _mintClaim(Mint calldata mintData) private {
    Claim memory claim = _getClaim(mintData.creatorContractAddress, mintData.instanceId);
    uint256[] memory tokenIds = new uint256[](1);
    if (mintData.variationIndex > claim.itemVariations || mintData.variationIndex < 1)
      revert IGachaLazyClaim.InvalidVariationIndex();
    tokenIds[0] = claim.startingTokenId + mintData.variationIndex - 1;
    address[] memory receivers = new address[](mintData.recipients.length);
    uint256[] memory amounts = new uint256[](mintData.recipients.length);
    for (uint256 i; i < mintData.recipients.length; ) {
      if (
        _deliveredMintsPerWallet[mintData.creatorContractAddress][mintData.instanceId][mintData.recipients[i].receiver] +
          mintData.recipients[i].mintCount >
        _reservedMintsPerWallet[mintData.creatorContractAddress][mintData.instanceId][mintData.recipients[i].receiver]
      ) revert IGachaLazyClaim.CannotMintMoreThanReserved();
      receivers[i] = mintData.recipients[i].receiver;
      amounts[i] = mintData.recipients[i].mintCount;
      unchecked {
        ++i;
      }
    }
    IERC1155CreatorCore(mintData.creatorContractAddress).mintExtensionExisting(receivers, tokenIds, amounts);
  }

  /**
   * See {IGachaLazyClaim-getUserMints}.
   */
  function getUserMints(
    address minter,
    address creatorContractAddress,
    uint256 instanceId
  ) external view override returns (UserMint memory) {
    return _getUserMints(minter, creatorContractAddress, instanceId);
  }

  /**
   * See {ICreatorExtensionTokenURI-tokenURI}.
   */
  function tokenURI(address creatorContractAddress, uint256 tokenId) external view override returns (string memory uri) {
    uint256 instanceId = _tokenInstances[creatorContractAddress][tokenId];
    if (instanceId == 0) revert IGachaLazyClaim.TokenDNE();
    Claim memory claim = _getClaim(creatorContractAddress, instanceId);

    string memory prefix = "";
    if (claim.storageProtocol == StorageProtocol.ARWEAVE) {
      prefix = ARWEAVE_PREFIX;
    } else if (claim.storageProtocol == StorageProtocol.IPFS) {
      prefix = IPFS_PREFIX;
    }
    uri = string(abi.encodePacked(prefix, claim.location, "/", Strings.toString(tokenId - claim.startingTokenId + 1)));
  }
}
