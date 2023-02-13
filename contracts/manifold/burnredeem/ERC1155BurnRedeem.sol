// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC1155CreatorCore.sol";

import "./BurnRedeemCore.sol";
import "./IERC1155BurnRedeem.sol";

contract ERC1155BurnRedeem is BurnRedeemCore, IERC1155BurnRedeem {
    using Strings for uint256;

    // { creatorContractAddress => { index =>  tokenId } }
    mapping(address => mapping(uint256 => uint256)) private _redeemTokenIds;
    // { creatorContractAddress => { tokenId =>  index } }
    mapping(address => mapping(uint256 => uint256)) private _redeemIndexes;

    function supportsInterface(bytes4 interfaceId) public view virtual override(BurnRedeemCore, IERC165) returns (bool) {
        return interfaceId == type(IERC1155BurnRedeem).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * See {IERC1155BurnRedeem-initializeBurnRedeem}.
     */
    function initializeBurnRedeem(
        address creatorContractAddress,
        uint256 index,
        BurnRedeemParameters calldata burnRedeemParameters
    ) external override creatorAdminRequired(creatorContractAddress) {
        _initialize(creatorContractAddress, index, burnRedeemParameters);

        // Mint a new token with amount '0' to the creator
        address[] memory receivers = new address[](1);
        receivers[0] = msg.sender;
        string[] memory uris = new string[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory newTokenIds = IERC1155CreatorCore(creatorContractAddress).mintExtensionNew(receivers, amounts, uris);
        _redeemTokenIds[creatorContractAddress][index] = newTokenIds[0];
        _redeemIndexes[creatorContractAddress][newTokenIds[0]] = index;
    }

    /**
     * See {IERC1155BurnRedeem-updateBurnRedeem}.
     */
    function updateBurnRedeem(
        address creatorContractAddress,
        uint256 index,
        BurnRedeemParameters calldata burnRedeemParameters
    ) external override creatorAdminRequired(creatorContractAddress) {
        _update(creatorContractAddress, index, burnRedeemParameters);
    }

    /**
     * See {IERC1155BurnRedeem-updateURI}.
     */
    function updateURI(
        address creatorContractAddress,
        uint256 index, StorageProtocol storageProtocol,
        string calldata location
    ) external override creatorAdminRequired(creatorContractAddress) {
        BurnRedeem storage burnRedeemInstance = _getBurnRedeem(creatorContractAddress, index);
        burnRedeemInstance.storageProtocol = storageProtocol;
        burnRedeemInstance.location = location;
    }

    /**
     * Helper to mint multiple redeem tokens
     */
    function _redeem(address creatorContractAddress, uint256 index, BurnRedeem storage burnRedeemInstance, address to, uint32 count) internal override {
        address[] memory addresses = new address[](1);
        addresses[0] = to;
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = _redeemTokenIds[creatorContractAddress][index];
        uint256[] memory values = new uint256[](1);
        values[0] = burnRedeemInstance.redeemAmount * count;
        
        IERC1155CreatorCore(creatorContractAddress).mintExtensionExisting(addresses, tokenIds, values);
        burnRedeemInstance.redeemedCount += uint32(values[0]);

        emit BurnRedeemMint(creatorContractAddress, index, tokenIds[0]);
    }

    /**
     * See {ICreatorExtensionTokenURI-tokenURI}.
     */
    function tokenURI(address creatorContractAddress, uint256 tokenId) external override view returns(string memory uri) {
        uint256 index = _redeemIndexes[creatorContractAddress][tokenId];
        require(index > 0, "Token does not exist");
        BurnRedeem memory burnRedeem = _burnRedeems[creatorContractAddress][index];

        string memory prefix = "";
        if (burnRedeem.storageProtocol == StorageProtocol.ARWEAVE) {
            prefix = ARWEAVE_PREFIX;
        } else if (burnRedeem.storageProtocol == StorageProtocol.IPFS) {
            prefix = IPFS_PREFIX;
        }
        uri = string(abi.encodePacked(prefix, burnRedeem.location));
    }
}
