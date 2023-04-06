// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "./IERC721Collectible.sol";
import "./CollectibleCore.sol";
import "../../libraries/IERC721CreatorCoreVersion.sol";

contract ERC721Collectible is CollectibleCore, IERC721Collectible {
    struct TokenClaim {
      uint224 instanceId;
      uint32 mintOrder;
    }

    // NOTE: Only used for creatorContract versions < 3
    // { contractAddress => { tokenId => TokenClaim }
    mapping(address => mapping(uint256 => TokenClaim)) internal _tokenIdToTokenClaimMap;

    // { contractAddress => { instanceId => { address => mintCount } }
    mapping(address => mapping(uint256 => mapping(address => uint256))) internal _addressMintCount;

    function supportsInterface(bytes4 interfaceId) public view virtual override(AdminControl, IERC165) returns (bool) {
        return (interfaceId == type(IERC721Collectible).interfaceId ||
            interfaceId == type(ICreatorExtensionTokenURI).interfaceId ||
            interfaceId == type(IERC721CreatorExtensionApproveTransfer).interfaceId ||
            interfaceId == type(IAdminControl).interfaceId ||
            interfaceId == type(IERC165).interfaceId);
    }

    /**
    * See {ICollectibleCore-initializeCollectible}.
    */
    function initializeCollectible(
        address creatorContractAddress,
        uint256 instanceId,
        InitializationParameters calldata initializationParameters
    ) external override creatorAdminRequired(creatorContractAddress) {
        uint8 creatorContractVersion;
        try IERC721CreatorCoreVersion(creatorContractAddress).VERSION() returns(uint256 version) {
            require(version <= 255, "Unsupported contract version");
            creatorContractVersion = uint8(version);
        } catch {}
        _initializeCollectible(creatorContractAddress, creatorContractVersion, instanceId, initializationParameters);
  }

    /**
    * @dev See {IERC721Collectible-premint}.
    */
    function premint(
        address creatorContractAddress,
        uint256 instanceId,
        uint16 amount
    ) external override creatorAdminRequired(creatorContractAddress) {
        CollectibleInstance storage instance = _getInstance(creatorContractAddress, instanceId);
        require(!instance.isActive, "Already active");

        _mint(creatorContractAddress, instanceId, msg.sender, amount);
    }

    /**
    * @dev See {IERC721Collectible-premint}.
    */
    function premint(
        address creatorContractAddress,
        uint256 instanceId,
        address[] calldata addresses
    ) external override creatorAdminRequired(creatorContractAddress) {
        CollectibleInstance storage instance = _getInstance(creatorContractAddress, instanceId);
        require(!instance.isActive, "Already active");

        for (uint256 i = 0; i < addresses.length; ) {
            _mint(creatorContractAddress, instanceId, addresses[i], 1);
            unchecked {
              i++;
            }
        }
    }

    /**
    * @dev See {IERC721Collectible-setTokenURIPrefix}.
    */
    function setTokenURIPrefix(
        address creatorContractAddress,
        uint256 instanceId,
        string calldata prefix
    ) external override creatorAdminRequired(creatorContractAddress) {
        CollectibleInstance storage instance = _getInstance(creatorContractAddress, instanceId);
        instance.baseURI = prefix;
    }

    /**
    * @dev See {IERC721Collectible-setTransferLocked}.
    */
    function setTransferLocked(
        address creatorContractAddress,
        uint256 instanceId,
        bool isLocked
    ) external override creatorAdminRequired(creatorContractAddress) {
        CollectibleInstance storage instance = _getInstance(creatorContractAddress, instanceId);
        instance.isTransferLocked = isLocked;
    }

    /**
    * @dev See {IERC721Collectible-claim}.
    */
    function claim(
        address creatorContractAddress,
        uint256 instanceId,
        uint16 amount,
        bytes32 message,
        bytes calldata signature,
        bytes32 nonce
    ) public payable virtual override {
        _validateClaimRestrictions(creatorContractAddress, instanceId);
        _validateClaimRequest(creatorContractAddress, instanceId, message, signature, nonce, amount);
        _addressMintCount[creatorContractAddress][instanceId][msg.sender] += amount;
        require(msg.value == _getManifoldFee(amount), "Invalid purchase amount");
        _mint(creatorContractAddress, instanceId, msg.sender, amount);
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
        CollectibleInstance storage instance = _getInstance(creatorContractAddress, instanceId);
        _validatePurchaseRestrictions(creatorContractAddress, instanceId);

        bool isPresale = _isPresale(creatorContractAddress, instanceId);
        uint256 priceWithoutFee;

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
                    uint256 mintCount = _addressMintCount[creatorContractAddress][instanceId][msg.sender];
                    require(
                        instance.presalePurchaseLimit > mintCount && amount <= (instance.presalePurchaseLimit - mintCount),
                        "Too many requested"
                    );
                }
                // Make sure we are not over purchaseLimit
                if (instance.purchaseLimit != 0) {
                    uint256 mintCount = _addressMintCount[creatorContractAddress][instanceId][msg.sender];
                    require(
                        instance.purchaseLimit > mintCount && amount <= (instance.purchaseLimit - mintCount),
                        "Too many requested"
                    );
                  }
              }
            priceWithoutFee = _validatePresalePrice(amount, instance);
            // Only track mint count if needed
            if (!instance.useDynamicPresalePurchaseLimit && (instance.presalePurchaseLimit != 0 || instance.purchaseLimit != 0)) {
                _addressMintCount[creatorContractAddress][instanceId][msg.sender] += amount;
            }
        } else {
            // Make sure we are not over purchaseLimit
            if (instance.purchaseLimit != 0) {
                uint256 mintCount = _addressMintCount[creatorContractAddress][instanceId][msg.sender];
                require(instance.purchaseLimit > mintCount && amount <= (instance.purchaseLimit - mintCount), "Too many requested");
            }
            priceWithoutFee = _validatePrice(amount, instance);

            if (instance.purchaseLimit != 0) {
                _addressMintCount[creatorContractAddress][instanceId][msg.sender] += amount;
            }
        }

        if (isPresale && instance.useDynamicPresalePurchaseLimit) {
           _validatePurchaseRequestWithAmount(creatorContractAddress, instanceId, message, signature, nonce, amount);
        } else {
            _validatePurchaseRequest(creatorContractAddress, instanceId, message, signature, nonce);
        }

        if (priceWithoutFee > 0) {
            _forwardValue(instance.paymentReceiver, priceWithoutFee);
        }

        _mint(creatorContractAddress, instanceId, msg.sender, amount);
    }

    /**
    * @dev returns the collection state
    */
    function state(address creatorContractAddress, uint256 instanceId) external view returns (CollectibleState memory) {
        CollectibleInstance storage instance = _getInstance(creatorContractAddress, instanceId);

        return CollectibleState(
            instance.isActive,
            instance.useDynamicPresalePurchaseLimit,
            instance.isTransferLocked,
            instance.transactionLimit,
            instance.purchaseMax,
            instance.purchaseLimit,
            instance.presalePurchaseLimit,
            instance.purchaseCount,
            instance.startTime,
            instance.endTime,
            instance.presaleInterval,
            instance.claimStartTime,
            instance.claimEndTime,
            instance.purchasePrice,
            instance.presalePurchasePrice,
            purchaseRemaining(creatorContractAddress, instanceId),
            instance.paymentReceiver
        );
    }

    /**
    * @dev See {IERC721Collectible-purchaseRemaining}.
    */
    function purchaseRemaining(
        address creatorContractAddress,
        uint256 instanceId
    ) public view virtual override returns (uint16) {
        CollectibleInstance storage instance = _getInstance(creatorContractAddress, instanceId);
        return instance.purchaseMax - instance.purchaseCount;
    }

    /**
    * @dev See {ICreatorExtensionTokenURI-tokenURI}
    */
    function tokenURI(address creatorContractAddress, uint256 tokenId) external view override returns (string memory) {
        TokenClaim memory tokenClaim = _tokenIdToTokenClaimMap[creatorContractAddress][tokenId];
        uint256 mintOrder;
        CollectibleInstance memory instance;
        if (tokenClaim.instanceId == 0) {
            // No claim, try to retrieve from tokenData
            uint80 tokenData = IERC721CreatorCore(creatorContractAddress).tokenData(tokenId);
            uint56 instanceId = uint56(tokenData >> 24);
            require(instanceId != 0, "Token not found");
            instance = _getInstance(creatorContractAddress, instanceId);
            mintOrder = uint24(tokenData & MAX_UINT_24);
        } else {
            mintOrder = tokenClaim.mintOrder;
            instance = _getInstance(creatorContractAddress, tokenClaim.instanceId);
        }

        require(bytes(instance.baseURI).length != 0, "No base uri prefix set");

        return string(abi.encodePacked(instance.baseURI, Strings.toString(mintOrder)));
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
        // always allow mints
        if (from == address(0)) {
            return true;
        }
        TokenClaim memory tokenClaim = _tokenIdToTokenClaimMap[msg.sender][tokenId];
        uint256 instanceId;
        if (tokenClaim.instanceId == 0) {
            // No claim, try to retrieve from tokenData
            uint80 tokenData = IERC721CreatorCore(msg.sender).tokenData(tokenId);
            instanceId = uint56(tokenData >> 24);
            require(instanceId != 0, "Token not found");
        } else {
            instanceId = tokenClaim.instanceId;
        }
        CollectibleInstance storage instance = _getInstance(msg.sender, instanceId);

        return !instance.isTransferLocked;
    }

    /**
    * @dev override if you want to perform different mint functionality
    */
    function _mint(address creatorContractAddress, uint256 instanceId, address to, uint16 amount) internal virtual {
        CollectibleInstance storage instance = _getInstance(creatorContractAddress, instanceId);

        if (amount == 1) {
            uint256 tokenId;
            if (instance.contractVersion >= 3) {
                uint80 tokenData = uint56(instanceId) << 24 | uint24(++instance.purchaseCount);
                tokenId = IERC721CreatorCore(creatorContractAddress).mintExtension(to, tokenData);
            } else {
                ++instance.purchaseCount;
                tokenId = IERC721CreatorCore(creatorContractAddress).mintExtension(to);
                _tokenIdToTokenClaimMap[creatorContractAddress][tokenId] = TokenClaim(uint224(instanceId), instance.purchaseCount);
            }
            emit Unveil(creatorContractAddress, instanceId, instance.purchaseCount, tokenId);
        } else {
            uint32 tokenStart = instance.purchaseCount + 1;
            instance.purchaseCount += amount;
            if (instance.contractVersion >= 3) {
                uint80[] memory tokenDatas = new uint80[](amount);
                for (uint256 i; i < amount;) {
                    tokenDatas[i] = uint56(instanceId) << 24 | uint24(tokenStart + i);
                    unchecked { ++i; }
                }
                uint256[] memory tokenIds = IERC721CreatorCore(creatorContractAddress).mintExtensionBatch(to, tokenDatas);
                for (uint32 i = 0; i < amount; ) {
                    emit Unveil(creatorContractAddress, instanceId, tokenStart + i, tokenIds[i]);
                    unchecked { ++i; }
                }
            } else {
                uint256[] memory tokenIds = IERC721CreatorCore(creatorContractAddress).mintExtensionBatch(to, amount);
                for (uint32 i = 0; i < amount; ) {
                    emit Unveil(creatorContractAddress, instanceId, tokenStart + i, tokenIds[i]);
                    _tokenIdToTokenClaimMap[creatorContractAddress][tokenIds[i]] = TokenClaim(uint224(instanceId), tokenStart + i);
                    unchecked { ++i; }
                }
            }
        }
    }

    /**
    * Validate price (override for custom pricing mechanics)
    */
    function _validatePrice(uint16 numTokens, CollectibleInstance storage instance) internal virtual returns (uint256) {
        uint256 priceWithoutFee = numTokens * instance.purchasePrice;
        uint256 price = priceWithoutFee + _getManifoldFee(numTokens);
        require(msg.value == price, "Invalid purchase amount sent");

        return priceWithoutFee;
    }

    /**
    * Validate price (override for custom pricing mechanics)
    */
    function _validatePresalePrice(uint16 numTokens, CollectibleInstance storage instance) internal virtual returns (uint256) {
        uint256 priceWithoutFee = numTokens * instance.presalePurchasePrice;
        uint256 price = priceWithoutFee + _getManifoldFee(numTokens);
        require(msg.value == price, "Invalid purchase amount sent");

        return priceWithoutFee;
    }
}
