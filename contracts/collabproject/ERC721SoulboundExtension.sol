// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC721CreatorCore.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/ERC721/IERC721CreatorExtensionApproveTransfer.sol";

import "./SoulboundBase.sol";


contract ERC721SoulboundExtension is SoulboundBase, IERC165, IERC721CreatorExtensionApproveTransfer {

    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165) returns (bool) {
        return interfaceId == type(IERC721CreatorExtensionApproveTransfer).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }

    /**
     * @notice Set whether or not the Creator Contract will use this extension to determine token transfer approval. Enabled by default on extension registration.
     * @dev This function is restricted to the creator admin.
     */
    function setApproveTransfer(address creatorContractAddress, bool enabled) external creatorAdminRequired(creatorContractAddress) {
        IERC721CreatorCore(creatorContractAddress).setApproveTransferExtension(enabled);
    }

    /**
     * @notice Can be called by the Creator Contract to approve a transfer.
     */
    function approveTransfer(address, address from, address to, uint256) external pure returns (bool) {
        return _approveTransfer(from, to);
    }

    /**
     * @notice Returns true only for transfer to and from the zero address (minting and burning).
     */
    function _approveTransfer(address from, address to) internal pure returns (bool) {
        return from == address(0) || to == address(0);
    }

    /**
     * @notice Mints a new Soulbound token to the recipient
     * @dev This function is restricted to the creator admin.
     */
    function mintToken(address creatorContractAddress, address recipient, string memory tokenURI) external creatorAdminRequired(creatorContractAddress) {
        require(recipient != address(0), "Invalid recipient address");
        uint256 tokenId = IERC721CreatorCore(creatorContractAddress).mintExtension(recipient, tokenURI);
        _tokenIdIsSoulbound[creatorContractAddress][tokenId] = true;
        if (!_isSoulboundOwner[creatorContractAddress][recipient]) {
            _soulboundOwners[creatorContractAddress].push(recipient);
            _isSoulboundOwner[creatorContractAddress][recipient] = true;
        }
    }

    /**
     * @notice Mints a new Soulbound token to multiple recipients, each token can have a different URI
     * @dev This function is restricted to the creator admin.
     */
    function mintTokens(address creatorContractAddress, address[] memory recipients, string[] memory uris) external creatorAdminRequired(creatorContractAddress) {
        require(recipients.length > 0 && recipients.length <= 10, "1-10 recipients allowed");
        require(recipients.length == uris.length, "Mismatched recipients and uris");
        for (uint i = 0; i < recipients.length; i++) {
            require(recipients[i] != address(0), "Invalid recipient address");
            uint256 tokenId = IERC721CreatorCore(creatorContractAddress).mintExtension(recipients[i], uris[i]);
            _tokenIdIsSoulbound[creatorContractAddress][tokenId] = true;
            if (!_isSoulboundOwner[creatorContractAddress][recipients[i]]) {
                _soulboundOwners[creatorContractAddress].push(recipients[i]);
                _isSoulboundOwner[creatorContractAddress][recipients[i]] = true;
            }
        }
    }

    /**
     * @notice Retrieves the list of Soulbound token owners for a given Creator Contract Address.
     * @dev This function is restricted to the creator admin.
     */
    function getSoulboundOwners(address creatorContractAddress) public view creatorAdminRequired(creatorContractAddress) returns (address[] memory) {
        require(ERC165Checker.supportsInterface(creatorContractAddress, type(IERC721CreatorCore).interfaceId), "Invalid address");
        return _soulboundOwners[creatorContractAddress];
    }

    /**
     * @notice Checks if a token is Soulbound within a given Creator Contract Address.
     */
    function isSoulboundToken(address creatorContractAddress, uint256 tokenId) public view returns (bool) {
        require(ERC165Checker.supportsInterface(creatorContractAddress, type(IERC721CreatorCore).interfaceId), "Invalid address");
        require(IERC721(creatorContractAddress).ownerOf(tokenId) != address(0), "Token does not exist");
        return _tokenIdIsSoulbound[creatorContractAddress][tokenId];
    }

}