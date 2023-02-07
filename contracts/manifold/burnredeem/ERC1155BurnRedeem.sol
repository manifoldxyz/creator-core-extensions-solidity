// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC1155CreatorCore.sol";

import "./BurnRedeemCore.sol";
import "./IERC1155BurnRedeem.sol";

contract ERC1155BurnRedeem is BurnRedeemCore, IERC1155BurnRedeem {
    using Strings for uint256;

    // { creatorContractAddress => { index =>  ExtendedConfig } }
    mapping(address => mapping(uint256 => ExtendedConfig)) private _configs;

    function supportsInterface(bytes4 interfaceId) public view virtual override(BurnRedeemCore, IERC165) returns (bool) {
        return interfaceId == type(IERC1155BurnRedeem).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * See {IERC1155BurnRedeem-initializeBurnRedeem}.
     */
    function initializeBurnRedeem(
        address creatorContractAddress,
        uint256 index,
        BurnRedeemParameters calldata burnRedeemParameters,
        ExtendedConfig calldata config
    ) external override creatorAdminRequired(creatorContractAddress) {
        require(burnRedeemParameters.totalSupply % config.redeemAmount == 0, "Remainder left from totalSupply");
        _initialize(creatorContractAddress, index, burnRedeemParameters);
        _setConfig(creatorContractAddress, index, config);

        // Mint a new token with amount '0' to the creator
        address[] memory receivers = new address[](1);
        receivers[0] = msg.sender;
        string[] memory uris = new string[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory newTokenIds = IERC1155CreatorCore(creatorContractAddress).mintExtensionNew(receivers, amounts, uris);
        _redeemTokens[creatorContractAddress][newTokenIds[0]] = RedeemToken(uint224(index), 0);
        _configs[creatorContractAddress][index].redeemTokenId = newTokenIds[0];
    }

    /**
     * See {IERC1155BurnRedeem-updateBurnRedeem}.
     */
    function updateBurnRedeem(
        address creatorContractAddress,
        uint256 index,
        BurnRedeemParameters calldata burnRedeemParameters,
        ExtendedConfig calldata config
    ) external override creatorAdminRequired(creatorContractAddress) {
        require(burnRedeemParameters.totalSupply % config.redeemAmount == 0, "Remainder left from totalSupply");
        _update(creatorContractAddress, index, burnRedeemParameters);
        _setConfig(creatorContractAddress, index, config);
    }

    /**
     * Helper to set extended config for 1155 redeems
     */
    function _setConfig(address creatorContractAddress, uint256 index, ExtendedConfig calldata config) internal {
        ExtendedConfig storage _config = _configs[creatorContractAddress][index];
        _config.redeemAmount = config.redeemAmount;
    }

    /**
     * Helper to check the remaining number of redemptions available
     */
    function _redemptionsRemaining(address creatorContractAddress, uint256 index, BurnRedeem storage _burnRedeem) internal override view returns(uint256) {
        if (_burnRedeem.totalSupply == 0) {
            return MAX_UINT_256;
        }
        ExtendedConfig storage config = _configs[creatorContractAddress][index];
        return (_burnRedeem.totalSupply - _burnRedeem.redeemedCount) / config.redeemAmount;
    }

    /**
     * Helper to mint redeem token
     */
    function _redeem(address creatorContractAddress, uint256 index, BurnRedeem storage _burnRedeem, address to) internal override {
        _redeem(creatorContractAddress, index, _burnRedeem, to, /* count = */ 1);
    }

    /**
     * Helper to mint multiple redeem tokens
     */
    function _redeem(address creatorContractAddress, uint256 index, BurnRedeem storage _burnRedeem, address to, uint32 count) internal override {
        ExtendedConfig storage config = _configs[creatorContractAddress][index];
        
        address[] memory addresses = new address[](1);
        addresses[0] = to;
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = config.redeemTokenId;
        uint256[] memory values = new uint256[](1);
        values[0] = config.redeemAmount * count;
        
        IERC1155CreatorCore(creatorContractAddress).mintExtensionExisting(addresses, tokenIds, values);
        _burnRedeem.redeemedCount += uint32(values[0]);

        emit BurnRedeemMint(creatorContractAddress, index, config.redeemTokenId);
    }

    /**
     * See {ICreatorExtensionTokenURI-tokenURI}.
     */
    function tokenURI(address creatorContractAddress, uint256 tokenId) external override view returns(string memory uri) {
        uint256 index = _redeemTokens[creatorContractAddress][tokenId].burnRedeemIndex;
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
