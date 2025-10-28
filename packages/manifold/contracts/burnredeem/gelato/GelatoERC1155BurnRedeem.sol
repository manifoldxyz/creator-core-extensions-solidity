// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC1155CreatorCore.sol";

import "../BurnRedeemLib.sol";
import "../IERC1155BurnRedeem.sol";
import "./GelatoBurnRedeemCore.sol";

/**
 * @title Gelato-Enabled ERC1155 Burn Redeem
 * @notice Allows users to batch NFT approval + burn in a single transaction via Gelato Relay
 * @dev Extends BurnRedeemCore with ERC-2771 support for gasless/relayed transactions
 *
 * Key features:
 * - Users sign messages off-chain (no gas for approval)
 * - Gelato relayer submits transaction
 * - User pays gas fees via callWithSyncFeeERC2771 (no sponsorship burden)
 * - Single transaction UX for approve + burn
 */
contract GelatoERC1155BurnRedeem is GelatoBurnRedeemCore, IERC1155BurnRedeem {
    using Strings for uint256;

    // { creatorContractAddress => { instanceId =>  tokenId } }
    mapping(address => mapping(uint256 => uint256)) private _redeemTokenIds;
    // { creatorContractAddress => { tokenId =>  instanceId } }
    mapping(address => mapping(uint256 => uint256)) private _redeemInstanceIds;

    constructor(address initialOwner) GelatoBurnRedeemCore(initialOwner) {}

    function supportsInterface(bytes4 interfaceId) public view virtual override(GelatoBurnRedeemCore, IERC165) returns (bool) {
        return interfaceId == type(IERC1155BurnRedeem).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * See {IERC1155BurnRedeem-initializeBurnRedeem}.
     * @dev IMPORTANT: Uses _msgSender() for actual caller (works with Gelato relay)
     */
    function initializeBurnRedeem(
        address creatorContractAddress,
        uint256 instanceId,
        BurnRedeemParameters calldata burnRedeemParameters
    ) external override {
        _validateAdmin(creatorContractAddress);
        _initialize(creatorContractAddress, 0, instanceId, burnRedeemParameters);

        // Mint a new token with amount '0' to the creator
        // IMPORTANT: Use _msgSender() to get actual caller
        address actualSender = _msgSender();
        address[] memory receivers = new address[](1);
        receivers[0] = actualSender;
        string[] memory uris = new string[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory newTokenIds = IERC1155CreatorCore(creatorContractAddress).mintExtensionNew(receivers, amounts, uris);
        _redeemTokenIds[creatorContractAddress][instanceId] = newTokenIds[0];
        _redeemInstanceIds[creatorContractAddress][newTokenIds[0]] = instanceId;
    }

    /**
     * See {IERC1155BurnRedeem-updateBurnRedeem}.
     */
    function updateBurnRedeem(
        address creatorContractAddress,
        uint256 instanceId,
        BurnRedeemParameters calldata burnRedeemParameters
    ) external override {
        _validateAdmin(creatorContractAddress);
        _update(creatorContractAddress, instanceId, burnRedeemParameters);
    }

    /**
     * See {IERC1155BurnRedeem-updateURI}.
     */
    function updateURI(
        address creatorContractAddress,
        uint256 instanceId,
        StorageProtocol storageProtocol,
        string calldata location
    ) external override {
        _validateAdmin(creatorContractAddress);
        BurnRedeem storage burnRedeemInstance = _getBurnRedeem(creatorContractAddress, instanceId);
        burnRedeemInstance.storageProtocol = storageProtocol;
        burnRedeemInstance.location = location;
        emit BurnRedeemLib.BurnRedeemUpdated(creatorContractAddress, instanceId);
    }

    /**
     * Helper to mint multiple redeem tokens
     */
    function _redeem(address creatorContractAddress, uint256 instanceId, BurnRedeem storage burnRedeemInstance, address to, uint32 count, bytes memory data) internal override {
        address[] memory addresses = new address[](1);
        addresses[0] = to;
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = _redeemTokenIds[creatorContractAddress][instanceId];
        uint256[] memory values = new uint256[](1);
        values[0] = burnRedeemInstance.redeemAmount * count;

        IERC1155CreatorCore(creatorContractAddress).mintExtensionExisting(addresses, tokenIds, values);
        burnRedeemInstance.redeemedCount += uint32(values[0]);

        emit BurnRedeemLib.BurnRedeemMint(creatorContractAddress, instanceId, tokenIds[0], uint32(values[0]), data);
    }

    /**
     * See {ICreatorExtensionTokenURI-tokenURI}.
     */
    function tokenURI(address creatorContractAddress, uint256 tokenId) external override view returns(string memory uri) {
        uint256 instanceId = _getRedeemInstanceId(creatorContractAddress, tokenId);
        BurnRedeem memory burnRedeem = _burnRedeems[creatorContractAddress][instanceId];

        string memory prefix = "";
        if (burnRedeem.storageProtocol == StorageProtocol.ARWEAVE) {
            prefix = ARWEAVE_PREFIX;
        } else if (burnRedeem.storageProtocol == StorageProtocol.IPFS) {
            prefix = IPFS_PREFIX;
        }
        uri = string(abi.encodePacked(prefix, burnRedeem.location));
    }

    /**
     * See {IBurnRedeemCore-getBurnRedeemForToken}.
     */
    function getBurnRedeemForToken(address creatorContractAddress, uint256 tokenId) external override view returns(uint256 instanceId, BurnRedeem memory burnRedeem) {
        instanceId = _getRedeemInstanceId(creatorContractAddress, tokenId);
        burnRedeem = _burnRedeems[creatorContractAddress][instanceId];
    }

    /**
     * See {IBurnRedeemCore-getBurnRedeemToken}.
     */
    function getBurnRedeemToken(address creatorContractAddress, uint256 instanceId) external override view returns(uint256 tokenId) {
        tokenId = _redeemTokenIds[creatorContractAddress][instanceId];
        if (tokenId == 0) {
            revert BurnRedeemDoesNotExist(instanceId);
        }
    }

    function _getRedeemInstanceId(address creatorContractAddress, uint256 tokenId) internal view returns(uint256 instanceId) {
        instanceId = _redeemInstanceIds[creatorContractAddress][tokenId];
        if (instanceId == 0) {
            revert InvalidToken(tokenId);
        }
    }
}
