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
    if (_claims[creatorContractAddress][instanceId].storageProtocol != StorageProtocol.INVALID)
      revert IGachaLazyClaim.ClaimAlreadyInitialized();
    // Checks
    if (claimParameters.storageProtocol == StorageProtocol.INVALID) revert IGachaLazyClaim.InvalidStorageProtocol();
    if (claimParameters.endDate != 0 && claimParameters.startDate >= claimParameters.endDate)
      revert IGachaLazyClaim.InvalidDate();

    address[] memory receivers = new address[](1);
    receivers[0] = msg.sender;
    uint256[] memory amounts = new uint256[](claimParameters.tokenVariations);
    string[] memory uris = new string[](claimParameters.tokenVariations);
    uint256[] memory newTokenIds = IERC1155CreatorCore(creatorContractAddress).mintExtensionNew(receivers, amounts, uris);

    if (newTokenIds[0] > MAX_UINT_80) revert IGachaLazyClaim.InvalidStartingTokenId();

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
      erc20: claimParameters.erc20
    });
    for (uint256 i; i < claimParameters.tokenVariations; ) {
      _tokenInstances[creatorContractAddress][newTokenIds[i]] = instanceId;
      unchecked {
        ++i;
      }
    }

    emit GachaClaimInitialized(creatorContractAddress, instanceId, msg.sender);
  }

  /**
   * See {IERC1155GachaLazyClaim-updateClaim}.
   */
  function updateClaim(
    address creatorContractAddress,
    uint256 instanceId,
    UpdateClaimParameters memory updateClaimParameters
  ) external override adminRequired {
    Claim memory claim = _getClaim(creatorContractAddress, instanceId);
    if (updateClaimParameters.endDate != 0 && updateClaimParameters.startDate >= updateClaimParameters.endDate)
      revert IGachaLazyClaim.InvalidDate();
    if (updateClaimParameters.totalMax < claim.total) revert IGachaLazyClaim.CannotLowerTotalMaxBeyondTotal();
    if (updateClaimParameters.storageProtocol == StorageProtocol.INVALID) revert IGachaLazyClaim.InvalidStorageProtocol();

    // Overwrite the existing values
    _claims[creatorContractAddress][instanceId] = Claim({
      storageProtocol: claim.storageProtocol,
      total: claim.total,
      totalMax: updateClaimParameters.totalMax,
      startDate: updateClaimParameters.startDate,
      endDate: updateClaimParameters.endDate,
      startingTokenId: claim.startingTokenId,
      tokenVariations: claim.tokenVariations,
      location: updateClaimParameters.location,
      paymentReceiver: updateClaimParameters.paymentReceiver,
      cost: updateClaimParameters.cost,
      erc20: claim.erc20
    });

    // logic for updating tokenIds
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
    if (Address.isContract(msg.sender)) revert IGachaLazyClaim.CannotMintFromContract();
    Claim storage claim = _getClaim(creatorContractAddress, instanceId);
    // Checks for reserving
    if (claim.startDate > block.timestamp) revert IGachaLazyClaim.ClaimInactive();
    if (claim.endDate > 0 && claim.endDate <= block.timestamp) revert IGachaLazyClaim.ClaimInactive();
    if (msg.value != (claim.cost + MINT_FEE) * mintCount) revert IGachaLazyClaim.InvalidPayment();
    uint32 amountAvailable = claim.totalMax - claim.total;
    if (amountAvailable == 0) revert IGachaLazyClaim.ClaimSoldOut();

    // calculate the amount to reserve and update totals
    uint32 amountToReserve = uint32(Math.min(mintCount, amountAvailable));
    claim.total += amountToReserve;
    _mintDetailsPerWallet[creatorContractAddress][instanceId][msg.sender].reservedCount += amountToReserve;
    if (amountToReserve > 0 && claim.cost > 0) {
      _sendFunds(claim.paymentReceiver, claim.cost * amountToReserve);
    }
    // Refund any overpayment
    if (amountToReserve != mintCount) {
      uint256 refundAmount = msg.value - (claim.cost + MINT_FEE) * amountToReserve;
      _sendFunds(payable(msg.sender), refundAmount);
    }
    emit GachaClaimMintReserved(creatorContractAddress, instanceId, msg.sender, amountToReserve);
  }

  /**
   * See {IGachaLazyClaim-deliverMints}.
   */
  function deliverMints(IGachaLazyClaim.Mint[] calldata mints) external override {
    _validateSigner();
    for (uint256 i; i < mints.length; ) {
      Mint calldata mintData = mints[i];
      Claim memory claim = _getClaim(mintData.creatorContractAddress, mintData.instanceId);
      if (mintData.variationIndex > claim.tokenVariations || mintData.variationIndex < 1)
        revert IGachaLazyClaim.InvalidVariationIndex();

      // mint parameters
      uint256[] memory tokenIds = new uint256[](1);
      tokenIds[0] = claim.startingTokenId + mintData.variationIndex - 1;
      address[] memory receivers = new address[](mintData.recipients.length);
      uint256[] memory amounts = new uint256[](mintData.recipients.length);
      for (uint256 j; j < mintData.recipients.length; ) {
        address receiver = mintData.recipients[j].receiver;
        uint256 mintCount = mintData.recipients[j].mintCount;
        UserMint storage userDetails = _mintDetailsPerWallet[mintData.creatorContractAddress][mintData.instanceId][receiver];

        if (userDetails.deliveredCount + mintCount > userDetails.reservedCount)
          revert IGachaLazyClaim.CannotMintMoreThanReserved();
        receivers[j] = receiver;
        amounts[j] = mintCount;
        _mintDetailsPerWallet[mintData.creatorContractAddress][mintData.instanceId][receiver].deliveredCount+= uint32(mintCount);
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

  /**
   * See {IERC1155GachaLazyClaim-updateTokenURIParams}.
   */
  function updateTokenURIParams(
    address creatorContractAddress,
    uint256 instanceId,
    StorageProtocol storageProtocol,
    string calldata location
  ) external override adminRequired {
    Claim storage claim = _getClaim(creatorContractAddress, instanceId);
    if (storageProtocol == StorageProtocol.INVALID) revert IGachaLazyClaim.InvalidStorageProtocol();
    claim.storageProtocol = storageProtocol;
    claim.location = location;
    emit GachaClaimUpdated(creatorContractAddress, instanceId);
  }
}
