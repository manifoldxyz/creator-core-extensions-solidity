// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC1155CreatorCore.sol";

import "./BurnRedeemCoreV2.sol";
import "./BurnRedeemLibV2.sol";
import "./IERC1155BurnRedeemV2.sol";

contract ERC1155BurnRedeemV2 is BurnRedeemCoreV2, IERC1155BurnRedeemV2 {
    using Strings for uint256;

    // { creatorContractAddress => { instanceId =>  tokenId } }
    mapping(address => mapping(uint256 => uint256)) private _redeemTokenIds;
    // { creatorContractAddress => { tokenId =>  instanceId } }
    mapping(address => mapping(uint256 => uint256)) private _redeemInstanceIds;

    constructor(address initialOwner) BurnRedeemCoreV2(initialOwner) {}

    function supportsInterface(bytes4 interfaceId) public view virtual override(BurnRedeemCoreV2, IERC165) returns (bool) {
        return interfaceId == type(IERC1155BurnRedeemV2).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * See {IERC1155BurnRedeemV2-initializeBurnRedeem}.
     */
    function initializeBurnRedeem(
        address creatorContractAddress,
        uint256 instanceId,
        BurnRedeemParameters calldata burnRedeemParameters
    ) external override {
        _validateAdmin(creatorContractAddress);
        _initialize(creatorContractAddress, 0, instanceId, burnRedeemParameters);

        // Mint a new token with amount '0' to the creator
        address[] memory receivers = new address[](1);
        receivers[0] = msg.sender;
        string[] memory uris = new string[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory newTokenIds = IERC1155CreatorCore(creatorContractAddress).mintExtensionNew(receivers, amounts, uris);
        _redeemTokenIds[creatorContractAddress][instanceId] = newTokenIds[0];
        _redeemInstanceIds[creatorContractAddress][newTokenIds[0]] = instanceId;
    }

    /**
     * See {IERC1155BurnRedeemV2-updateBurnRedeem}.
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
     * See {IERC1155BurnRedeemV2-updateURI}.
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
        emit BurnRedeemLibV2.BurnRedeemUpdated(creatorContractAddress, instanceId);
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

        emit BurnRedeemLibV2.BurnRedeemMint(creatorContractAddress, instanceId, tokenIds[0], uint32(values[0]), data);
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
     * See {IBurnRedeemCoreV2-getBurnRedeemForToken}.
     */
    function getBurnRedeemForToken(address creatorContractAddress, uint256 tokenId) external override view returns(uint256 instanceId, BurnRedeem memory burnRedeem) {
        instanceId = _getRedeemInstanceId(creatorContractAddress, tokenId);
        burnRedeem = _burnRedeems[creatorContractAddress][instanceId];
    }

    /**
     * See {IBurnRedeemCoreV2-getBurnRedeemToken}.
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
