// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz
import "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "./IMultiAssetClaimCore.sol";

/**
 * Collection Drop Contract (Base)
 */
abstract contract MultiAssetClaimCore is IMultiAssetClaimCore, AdminControl {
  using ECDSA for bytes32;

  address public manifoldMembershipContract;

  // { creatorContractAddress => { index => nonce => t/f  } }
  mapping(address => mapping(uint256 => mapping(bytes32 => bool))) internal _usedNonces;
  // { creatorContractAddress => { index => address  } }
  mapping(address => mapping(uint256 => address)) private _signingAddresses;
  // { creatorContractAddress => { index => MultiAssetClaimInstance } }
  mapping(address => mapping(uint256 => MultiAssetClaimInstance)) internal _instances;

  /**
   * @notice This extension is shared, not single-creator. So we must ensure
   * that a claim's initializer is an admin on the creator contract
   * @param creatorContractAddress    the address of the creator contract to check the admin against
   */
  modifier creatorAdminRequired(address creatorContractAddress) {
    AdminControl creatorCoreContract = AdminControl(creatorContractAddress);
    require(creatorCoreContract.isAdmin(msg.sender), "Wallet is not an administrator for contract");
    _;
  }

  /**
   * See {IMultiAssetClaimCore-initializeMultiAssetClaim}.
   */
  function initializeMultiAssetClaim(
    address creatorContractAddress,
    uint256 instanceId,
    InitializationParameters calldata initializationParameters
  ) external override creatorAdminRequired(creatorContractAddress) {
    address signingAddress = _signingAddresses[creatorContractAddress][instanceId];
    MultiAssetClaimInstance storage instance = _getInstance(creatorContractAddress, instanceId);

    // Revert if claim at instanceId already exists
    require(instance.purchaseMax == 0 && signingAddress == address(0), "Claim already initialized");

    instance.paymentReceiver = initializationParameters.paymentReceiver;
    _signingAddresses[creatorContractAddress][instanceId] = initializationParameters.signingAddress;
    instance.purchaseMax = initializationParameters.purchaseMax;
    instance.purchasePrice = initializationParameters.purchasePrice;
    instance.purchaseLimit = initializationParameters.purchaseLimit;
    instance.transactionLimit = initializationParameters.transactionLimit;
    instance.presalePurchasePrice = initializationParameters.presalePurchasePrice;
    instance.presalePurchaseLimit = initializationParameters.presalePurchaseLimit;
    instance.useDynamicPresalePurchaseLimit = initializationParameters.useDynamicPresalePurchaseLimit;
    instance.paymentReceiver = initializationParameters.paymentReceiver;

    emit MultiAssetClaimInitialized(creatorContractAddress, instanceId, msg.sender);
  }

  /**
   * See {IMultiAssetClaimCore-withdraw}.
   */
  function withdraw(address payable receiver, uint256 amount) external override adminRequired {
    (bool sent, ) = receiver.call{ value: amount }("");
    require(sent, "Failed to transfer to receiver");
  }

  /**
   * See {IMultiAssetClaimCore-activate}.
   */
  function activate(
    address creatorContractAddress,
    uint256 instanceId,
    ActivationParameters calldata activationParameters
  ) external override creatorAdminRequired(creatorContractAddress) {
    MultiAssetClaimInstance storage instance = _getInstance(creatorContractAddress, instanceId);
    require(!instance.isActive, "Already active");
    require(activationParameters.startTime > block.timestamp, "Cannot activate in the past");
    require(
      activationParameters.presaleInterval <= activationParameters.duration,
      "Presale Interval cannot be longer than the sale"
    );
    require(
      activationParameters.claimStartTime <= activationParameters.claimEndTime &&
        activationParameters.claimEndTime <= activationParameters.startTime,
      "Invalid claim times"
    );
    instance.startTime = activationParameters.startTime;
    instance.endTime = activationParameters.startTime + activationParameters.duration;
    instance.presaleInterval = activationParameters.presaleInterval;
    instance.claimStartTime = activationParameters.claimStartTime;
    instance.claimEndTime = activationParameters.claimEndTime;
    instance.isActive = true;

    emit MultiAssetClaimActivated(
      creatorContractAddress,
      instanceId,
      instance.startTime,
      instance.endTime,
      instance.presaleInterval,
      instance.claimStartTime,
      instance.claimEndTime
    );
  }

  /**
   * See {IMultiAssetClaimCore-deactivate}.
   */
  function deactivate(
    address creatorContractAddress,
    uint256 instanceId
  ) external override creatorAdminRequired(creatorContractAddress) {
    MultiAssetClaimInstance storage instance = _getInstance(creatorContractAddress, instanceId);

    instance.startTime = 0;
    instance.endTime = 0;
    instance.isActive = false;
    instance.claimStartTime = 0;
    instance.claimEndTime = 0;

    emit MultiAssetClaimDeactivated(creatorContractAddress, instanceId);
  }

  /**
   * @dev See {IMultiAssetClaimCore-getMultiAssetClaim}.
   */
  function getMultiAssetClaim(
    address creatorContractAddress,
    uint256 index
  ) external view override returns (MultiAssetClaimInstance memory) {
    return _getMultiAssetClaim(creatorContractAddress, index);
  }

  /**
   * @dev See {IERC721MultiAssetClaim-setManifoldMembership}.
   */
  function setMembershipAddress(address addr) external override adminRequired {
    manifoldMembershipContract = addr;
  }

  /**
   * @dev See {IERC721MultiAssetClaim-modifyInitializationParameters}.
   */
  function modifyInitializationParameters(
    address creatorContractAddress,
    uint256 instanceId,
    InitializationParameters calldata initializationParameters
  ) external override creatorAdminRequired(creatorContractAddress) {
    MultiAssetClaimInstance storage instance = _getInstance(creatorContractAddress, instanceId);

    require(!instance.isActive, "Already active");
    instance.purchasePrice = initializationParameters.purchasePrice;
    instance.purchaseLimit = initializationParameters.purchaseLimit;
    instance.transactionLimit = initializationParameters.transactionLimit;
    instance.presalePurchasePrice = initializationParameters.presalePurchasePrice;
    instance.presalePurchaseLimit = initializationParameters.presalePurchaseLimit;
    instance.useDynamicPresalePurchaseLimit = initializationParameters.useDynamicPresalePurchaseLimit;
  }

  /**
   * Validate claim signature
   */
  function _getMultiAssetClaim(
    address creatorContractAddress,
    uint256 instanceId
  ) internal view returns (MultiAssetClaimInstance storage) {
    return _instances[creatorContractAddress][instanceId];
  }

  /**
   * Validate claim signature
   */
  function _validateClaimRequest(
    address creatorContractAddress,
    uint256 instanceId,
    bytes32 message,
    bytes calldata signature,
    bytes32 nonce,
    uint16 amount
  ) internal virtual {
    _validatePurchaseRequestWithAmount(creatorContractAddress, instanceId, message, signature, nonce, amount);
  }

  /**
   * Validate claim restrictions
   */
  function _validateClaimRestrictions(address creatorContractAddress, uint256 instanceId) internal virtual {
    MultiAssetClaimInstance storage instance = _getInstance(creatorContractAddress, instanceId);
    require(instance.isActive, "Inactive");
    require(block.timestamp >= instance.claimStartTime && block.timestamp <= instance.claimEndTime, "Outside claim period.");
  }

  /**
   * Validate purchase signature
   */
  function _validatePurchaseRequest(
    address creatorContractAddress,
    uint256 instanceId,
    bytes32 message,
    bytes calldata signature,
    bytes32 nonce
  ) internal virtual {
    // Verify nonce usage/re-use
    require(!_usedNonces[creatorContractAddress][instanceId][nonce], "Cannot replay transaction");
    // Verify valid message based on input variables
    bytes32 expectedMessage = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n52", msg.sender, nonce));
    require(message == expectedMessage, "Malformed message");
    // Verify signature was performed by the expected signing address
    address signer = message.recover(signature);
    address signingAddress = _signingAddresses[creatorContractAddress][instanceId];
    require(signer == signingAddress, "Invalid signature");

    _usedNonces[creatorContractAddress][instanceId][nonce] = true;
  }

  /**
   * Validate purchase signature with amount
   */
  function _validatePurchaseRequestWithAmount(
    address creatorContractAddress,
    uint256 instanceId,
    bytes32 message,
    bytes calldata signature,
    bytes32 nonce,
    uint16 amount
  ) internal virtual {
    // Verify nonce usage/re-use
    require(!_usedNonces[creatorContractAddress][instanceId][nonce], "Cannot replay transaction");
    // Verify valid message based on input variables
    bytes32 expectedMessage = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n54", msg.sender, nonce, amount));
    require(message == expectedMessage, "Malformed message");
    // Verify signature was performed by the expected signing address
    address signer = message.recover(signature);
    address signingAddress = _signingAddresses[creatorContractAddress][instanceId];
    require(signer == signingAddress, "Invalid signature");

    _usedNonces[creatorContractAddress][instanceId][nonce] = true;
  }

  /**
   * Perform purchase restriction checks. Override if more logic is needed
   */
  function _validatePurchaseRestrictions(address creatorContractAddress, uint256 instanceId) internal virtual {
    MultiAssetClaimInstance storage instance = _getInstance(creatorContractAddress, instanceId);

    require(instance.isActive, "Inactive");
    require(block.timestamp >= instance.startTime, "Purchasing not active");
  }

  /**
   * @dev See {IMultiAssetClaimCore-nonceUsed}.
   */
  function nonceUsed(
    address creatorContractAddress,
    uint256 instanceId,
    bytes32 nonce
  ) external view override returns (bool) {
    return _usedNonces[creatorContractAddress][instanceId][nonce];
  }

  /**
   * @dev Check if currently in presale
   */
  function _isPresale(address creatorContractAddress, uint256 instanceId) internal view returns (bool) {
    MultiAssetClaimInstance storage instance = _getInstance(creatorContractAddress, instanceId);

    return (block.timestamp > instance.startTime && block.timestamp - instance.startTime < instance.presaleInterval);
  }

  function _getInstance(
    address creatorContractAddress,
    uint256 instanceId
  ) internal view returns (MultiAssetClaimInstance storage instance) {
    instance = _instances[creatorContractAddress][instanceId];
    require(instance.purchaseMax != 0, "Claim not initialized");
  }

  /**
   * Send funds to receiver
   */
  function _forwardValue(address payable receiver, uint256 amount) internal {
    (bool sent, ) = receiver.call{ value: amount }("");
    require(sent, "Failed to transfer to recipient");
  }
}
