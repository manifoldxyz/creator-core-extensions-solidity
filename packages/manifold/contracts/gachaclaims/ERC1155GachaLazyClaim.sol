// SPDX-License-Identifier: MIT
// solhint-disable reason-string
pragma solidity ^0.8.0;

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC1155CreatorCore.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/ICreatorExtensionTokenURI.sol";

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

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
  mapping(address => mapping(uint256 => uint256)) private _claimTokenIds;

  // Nonce usage tracking: mapping of fid to nonce to used status
  mapping(uint256 => mapping(uint256 => bool)) private _usedNonces;

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
    // Revert if claim at instanceId already exists
    if (_claims[creatorContractAddress][instanceId].storageProtocol == StorageProtocol.INVALID)
      revert IGachaLazyClaim.ClaimAlreadyInitialized();

    // Sanity checks
    if (claimParameters.storageProtocol != StorageProtocol.INVALID) revert IGachaLazyClaim.InvalidStorageProtocol();
    address[] memory receivers = new address[](1);
    receivers[0] = msg.sender;
    string[] memory uris = new string[](1);
    // TODO check on logic to reserve tokenIds for claim itemVariations
    uint256[] memory amounts = new uint256[](claimParameters.itemVariations);
    uint256[] memory newTokenIds = IERC1155CreatorCore(creatorContractAddress).mintExtensionNew(receivers, amounts, uris);

    require(newTokenIds[0] <= type(uint112).max, "Token ID exceeds uint112 range");


    // Create the claim
    _claims[creatorContractAddress][instanceId] = Claim({
      storageProtocol: claimParameters.storageProtocol,
      total: 0,
      totalMax: claimParameters.totalMax,
      startDate: claimParameters.startDate,
      endDate: claimParameters.endDate,
      startingTokenId: uint112(newTokenIds[0]),
      itemVariations: claimParameters.itemVariations,
      location: claimParameters.location,
      paymentReceiver: claimParameters.paymentReceiver,
      erc20: claimParameters.erc20,
      cost: claimParameters.cost
    });
    for (uint8 i; i < claimParameters.itemVariations; i++) {
      _claimTokenIds[creatorContractAddress][newTokenIds[i]] = instanceId;
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
      erc20: claim.erc20,
      cost: claimParameters.cost
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
    instanceId = _claimTokenIds[creatorContractAddress][tokenId];
    claim = _getClaim(creatorContractAddress, instanceId);
  }

  function _getClaim(address creatorContractAddress, uint256 instanceId) private view returns (Claim storage claim) {
    claim = _claims[creatorContractAddress][instanceId];
    if (claim.storageProtocol == StorageProtocol.INVALID) revert IGachaLazyClaim.ClaimNotInitialized();
  }

  /**
   * See {IGachaLazyClaim-mintReserve}.
   */
  function mintReserve(MintReservation calldata mintReservation) external payable override {
    _validateSigner();
    _mintReserve(mintReservation);
  }

  function _mintReserve(MintReservation calldata mintReservation) private {
    _validateMintReserve(mintReservation);
    // Checks for reserving

    // Updating the total reserved and mapping
    // uint256 paymentReceived = msg.value;
  }

  function _validateMintReserve(MintReservation calldata mintReservation) private {
    if (block.timestamp > mintReservation.expiration) revert ExpiredSignature();
    // Verify valid message based on input variables
    bytes32 expectedMessage = keccak256(
      abi.encodePacked(
        abi.encode(mintReservation.mints, mintReservation.fid, mintReservation.expiration, mintReservation.nonce, msg.value)
      )
    );
        // address signer = mintReservation.message.recover(mintReservation.signature);
    if (mintReservation.message != expectedMessage || msg.sender != _signer) revert InvalidSignature();
    if (_usedNonces[mintReservation.fid][mintReservation.nonce]) revert InvalidNonce();
    _usedNonces[mintReservation.fid][mintReservation.nonce] = true;
  }

  function _mint(Mint[] calldata mints) private {
    for (uint256 i; i < mints.length; ) {
      Mint calldata mintData = mints[i];
      _mintClaim(mintData);
      emit GachaClaimMintDelivered(mintData.creatorContractAddress, mintData.instanceId, mintData.recipients[i].receiver);
      unchecked {
        ++i;
      }
    }
  }

  /**
   * See {IGachaLazyClaim-deliver}.
   */
  function deliverMints(IGachaLazyClaim.Mint[] calldata mints) external override {
    if (msg.sender != _signer) revert InvalidSignature();
    _mint(mints);
  }

  /**
   * Mint a claim
   */
  function _mintClaim(Mint calldata mintData) private {
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = mintData.tokenId;
    address[] memory receivers = new address[](mintData.recipients.length);
    uint256[] memory amounts = new uint256[](mintData.recipients.length);
    for (uint256 i; i < mintData.recipients.length; ) {
      receivers[i] = mintData.recipients[i].receiver;
      amounts[i] = mintData.recipients[i].mintCount;
      unchecked {
        ++i;
      }
    }
    IERC1155CreatorCore(mintData.creatorContractAddress).mintExtensionExisting(receivers, tokenIds, amounts);
  }

  // airdrop?

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
    uint224 tokenClaim = uint224(_claimTokenIds[creatorContractAddress][tokenId]);
    if (tokenClaim == 0) revert IGachaLazyClaim.TokenDNE();
    Claim memory claim = _claims[creatorContractAddress][tokenClaim];

    string memory prefix = "";
    if (claim.storageProtocol == StorageProtocol.ARWEAVE) {
      prefix = ARWEAVE_PREFIX;
    } else if (claim.storageProtocol == StorageProtocol.IPFS) {
      prefix = IPFS_PREFIX;
    }
    uri = string(abi.encodePacked(prefix, claim.location));
  }
}
