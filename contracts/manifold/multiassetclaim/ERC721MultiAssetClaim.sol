// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "./IERC721MultiAssetClaim.sol";
import "./MultiAssetClaimCore.sol";

contract ERC721MultiAssetClaim is MultiAssetClaimCore, IERC721MultiAssetClaim {
  struct TokenClaim {
    uint256 instanceId;
    uint32 mintOrder;
  }
  // { contractAddress => { tokenId => TokenClaim }
  mapping(address => mapping(uint256 => TokenClaim)) internal _tokenIdToTokenClaimMap;
  // { contractAddress => { instanceId => { address => mintCount } }
  mapping(address => mapping(uint256 => mapping(address => uint16))) internal _addressMintCount;

  function supportsInterface(bytes4 interfaceId) public view virtual override(AdminControl, IERC165) returns (bool) {
    return (interfaceId == type(IERC721MultiAssetClaim).interfaceId ||
      interfaceId == type(ICreatorExtensionTokenURI).interfaceId ||
      interfaceId == type(IERC721CreatorExtensionApproveTransfer).interfaceId ||
      interfaceId == type(IAdminControl).interfaceId ||
      interfaceId == type(IERC165).interfaceId);
  }

  /**
   * @dev See {IERC721MultiAssetClaim-premint}.
   */
  function premint(
    address creatorContractAddress,
    uint256 instanceId,
    uint16 amount
  ) external override creatorAdminRequired(creatorContractAddress) {
    _mint(creatorContractAddress, instanceId, msg.sender, amount);
  }

  /**
   * @dev See {IERC721MultiAssetClaim-premint}.
   */
  function premint(
    address creatorContractAddress,
    uint256 instanceId,
    address[] calldata addresses
  ) external override creatorAdminRequired(creatorContractAddress) {
    MultiAssetClaimInstance storage instance = _getInstance(creatorContractAddress, instanceId);
    require(!instance.isActive, "Already active");

    for (uint256 i = 0; i < addresses.length; ) {
      _mint(creatorContractAddress, instanceId, addresses[i], 1);
      unchecked {
        i++;
      }
    }
  }

  /**
   * @dev See {IERC721MultiAssetClaim-setTokenURIPrefix}.
   */
  function setTokenURIPrefix(
    address creatorContractAddress,
    uint256 instanceId,
    string calldata prefix
  ) external override creatorAdminRequired(creatorContractAddress) {
    MultiAssetClaimInstance storage instance = _getInstance(creatorContractAddress, instanceId);
    instance.baseURI = prefix;
  }

  /**
   * @dev See {IERC721MultiAssetClaim-setTransferLocked}.
   */
  function setTransferLocked(
    address creatorContractAddress,
    uint256 instanceId,
    bool isLocked
  ) external override creatorAdminRequired(creatorContractAddress) {
    MultiAssetClaimInstance storage instance = _getInstance(creatorContractAddress, instanceId);
    instance.isTransferLocked = isLocked;
  }

  /**
   * @dev See {IERC721MultiAssetClaim-claim}.
   */
  function claim(
    address creatorContractAddress,
    uint256 instanceId,
    uint16 amount,
    bytes32 message,
    bytes calldata signature,
    bytes32 nonce
  ) external virtual override {
    _validateClaimRestrictions(creatorContractAddress, instanceId);
    _validateClaimRequest(creatorContractAddress, instanceId, message, signature, nonce, amount);
    _mint(creatorContractAddress, instanceId, msg.sender, amount);
    _addressMintCount[creatorContractAddress][instanceId][msg.sender] += amount;
  }

  /**
   * @dev See {IERC721Collection-purchase}.
   */
  function purchase(
    address creatorContractAddress,
    uint256 instanceId,
    uint16 amount,
    bytes32 message,
    bytes calldata signature,
    bytes32 nonce
  ) public payable virtual override {
    MultiAssetClaimInstance storage instance = _getInstance(creatorContractAddress, instanceId);
    _validatePurchaseRestrictions(creatorContractAddress, instanceId);

    bool isPresale = _isPresale(creatorContractAddress, instanceId);

    // Check purchase amounts
    require(
      amount <= purchaseRemaining(creatorContractAddress, instanceId) &&
        ((isPresale && instance.useDynamicPresalePurchaseLimit) ||
          instance.transactionLimit == 0 ||
          amount <= instance.transactionLimit),
      "Too many requested"
    );

    if (isPresale) {
      if (!instance.useDynamicPresalePurchaseLimit) {
        // Make sure we are not over presalePurchaseLimit
        if (instance.presalePurchaseLimit != 0) {
          uint16 mintCount = _addressMintCount[creatorContractAddress][instanceId][msg.sender];
          require(
            instance.presalePurchaseLimit > mintCount && amount <= (instance.presalePurchaseLimit - mintCount),
            "Too many requested"
          );
        }
        // Make sure we are not over purchaseLimit
        if (instance.purchaseLimit != 0) {
          uint16 mintCount = _addressMintCount[creatorContractAddress][instanceId][msg.sender];
          require(
            instance.purchaseLimit > mintCount && amount <= (instance.purchaseLimit - mintCount),
            "Too many requested"
          );
        }
      }
      _validatePresalePrice(amount, instance);
      // Only track mint count if needed
      if (!instance.useDynamicPresalePurchaseLimit && (instance.presalePurchaseLimit != 0 || instance.purchaseLimit != 0)) {
        _addressMintCount[creatorContractAddress][instanceId][msg.sender] += amount;
      }
    } else {
      // Make sure we are not over purchaseLimit
      if (instance.purchaseLimit != 0) {
        uint16 mintCount = _addressMintCount[creatorContractAddress][instanceId][msg.sender];
        require(instance.purchaseLimit > mintCount && amount <= (instance.purchaseLimit - mintCount), "Too many requested");
      }
      _validatePrice(amount, instance);
      if (instance.purchaseLimit != 0) {
        _addressMintCount[creatorContractAddress][instanceId][msg.sender] += amount;
      }
    }

    if (isPresale && instance.useDynamicPresalePurchaseLimit) {
      _validatePurchaseRequestWithAmount(creatorContractAddress, instanceId, message, signature, nonce, amount);
    } else {
      _validatePurchaseRequest(creatorContractAddress, instanceId, message, signature, nonce);
    }

    _mint(creatorContractAddress, instanceId, msg.sender, amount);
    _forwardValue(instance.paymentReceiver, msg.value);
  }

  /**
   * @dev returns the collection state
   */
  function state(address creatorContractAddress, uint256 instanceId) external view returns (MultiAssetClaimInstance memory) {
    return _getInstance(creatorContractAddress, instanceId);
  }

  /**
   * @dev See {IERC721MultiAssetClaim-purchaseRemaining}.
   */
  function purchaseRemaining(
    address creatorContractAddress,
    uint256 instanceId
  ) public view virtual override returns (uint16) {
    MultiAssetClaimInstance storage instance = _getInstance(creatorContractAddress, instanceId);
    return instance.purchaseMax - instance.purchaseCount;
  }

  /**
   * @dev See {ICreatorExtensionTokenURI-tokenURI}
   */
  function tokenURI(address creatorContractAddress, uint256 tokenId) external view override returns (string memory) {
    uint256 instanceId = _tokenIdToTokenClaimMap[creatorContractAddress][tokenId].instanceId;
    require(instanceId != 0, "Token not found");

    MultiAssetClaimInstance storage instance = _getInstance(creatorContractAddress, instanceId);
    require(bytes(instance.baseURI).length != 0, "No base uri prefix set");

    return string(abi.encodePacked(instance.baseURI, Strings.toString(tokenId)));
  }

  /**
   * @dev See {IERC721CreatorExtensionApproveTransfer-setApproveTransfer}
   */
  function setApproveTransfer(
    address creatorContractAddress,
    bool enabled
  ) external override creatorAdminRequired(creatorContractAddress) {
    require(
      ERC165Checker.supportsInterface(creatorContractAddress, type(IERC721CreatorCore).interfaceId),
      "creator must implement IERC721CreatorCore"
    );
    IERC721CreatorCore(creatorContractAddress).setApproveTransferExtension(enabled);
  }

  /**
   * @dev See {IERC721CreatorExtensionApproveTransfer-approveTransfer}.
   */
  function approveTransfer(address, address from, address, uint256 tokenId) external view override returns (bool) {
    uint256 instanceId = _tokenIdToTokenClaimMap[msg.sender][tokenId].instanceId;
    require(instanceId != 0, "Token not found");

    MultiAssetClaimInstance storage instance = _getInstance(msg.sender, instanceId);
    return _validateTokenTransferability(from, instance);
  }

  /**
   * @dev override if you want to perform different mint functionality
   */
  function _mint(address creatorContractAddress, uint256 instanceId, address to, uint16 amount) internal virtual {
    MultiAssetClaimInstance storage instance = _getInstance(creatorContractAddress, instanceId);

    if (amount == 1) {
      instance.purchaseCount++;

      // Mint token
      uint256 tokenId = IERC721CreatorCore(creatorContractAddress).mintExtension(to);
      _tokenIdToTokenClaimMap[creatorContractAddress][tokenId] = TokenClaim(instanceId, instance.purchaseCount);
      emit Unveil(creatorContractAddress, instanceId, instance.purchaseCount, tokenId);
    } else {
      uint32 tokenStart = instance.purchaseCount + 1;
      instance.purchaseCount += amount;

      // Mint token
      uint256[] memory tokenIds = IERC721CreatorCore(creatorContractAddress).mintExtensionBatch(to, amount);

      for (uint32 i = 0; i < tokenIds.length; ) {
        emit Unveil(creatorContractAddress, instanceId, tokenStart + i, tokenIds[i]);

        _tokenIdToTokenClaimMap[creatorContractAddress][tokenIds[i]] = TokenClaim(instanceId, tokenStart + i);
        unchecked {
          i++;
        }
      }
    }
  }

  /**
   * Returns whether or not token transfers are enabled.
   */
  function _validateTokenTransferability(
    address from,
    MultiAssetClaimInstance storage instance
  ) internal view returns (bool) {
    return from == address(0) || !instance.isTransferLocked;
  }

  /**
   * Validate price (override for custom pricing mechanics)
   */
  function _validatePrice(uint16 amount, MultiAssetClaimInstance storage instance) internal virtual {
    require(msg.value == amount * instance.purchasePrice, "Invalid purchase amount sent");
  }

  /**
   * Validate price (override for custom pricing mechanics)
   */
  function _validatePresalePrice(uint16 amount, MultiAssetClaimInstance storage instance) internal virtual {
    require(msg.value == amount * instance.presalePurchasePrice, "Invalid purchase amount sent");
  }
}
