// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC721CreatorCore.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/ERC721/IERC721CreatorExtensionApproveTransfer.sol";
import "@manifoldxyz/libraries-solidity/contracts/access/IAdminControl.sol";

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import "./Soulbound.sol";

/**
 * @title Soulbound token
 * @author manifold.xyz
 * @notice Soulbound shared extension for Manifold Creator contracts.
 *         Default - Tokens are soulbound but burnable
 *         Tokens are burnable if they are burnable at the contract level OR the token level
 *         Tokens are soulbound if they are soulbound at the contract level OR the token level
 */
contract ERC721Soulbound is Soulbound, IERC165, IERC721CreatorExtensionApproveTransfer {

    bytes4 private constant IERC721CreatorExtensionApproveTransfer_v1 = 0x99cdaa22;

    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165) returns (bool) {
        return interfaceId == type(IERC721CreatorExtensionApproveTransfer).interfaceId ||
            interfaceId == IERC721CreatorExtensionApproveTransfer_v1 ||
            interfaceId == type(IERC165).interfaceId;
    }

    /**
     * @dev Set whether or not the creator will check the extension for approval of token transfer
     */
    function setApproveTransfer(address creatorContractAddress, bool enabled) external creatorAdminRequired(creatorContractAddress) {
        require(ERC165Checker.supportsInterface(creatorContractAddress, type(IERC721CreatorCore).interfaceId), "Invalid address");
        IERC721CreatorCore(creatorContractAddress).setApproveTransferExtension(enabled);
    }

    /**
     * @dev Called by creator contract to approve a transfer
     */
    function approveTransfer(address, address from, address to, uint256 tokenId) external view returns (bool) {
        return _approveTransfer(from, to, tokenId);
    }

    /**
     * @dev Called by creator contract to approve a transfer (v1)
     */
    function approveTransfer(address from, address to, uint256 tokenId) external view returns (bool) {
        return _approveTransfer(from, to, tokenId);
    }

    /**
     * @dev Determine whether or not a transfer of the given token is approved
     */
    function _approveTransfer(address from, address to, uint256 tokenId) private view returns (bool) {
        if (from == address(0)) return true;
        if (to == address(0)) return !(_tokenNonBurnable[msg.sender][tokenId] || _contractNonBurnable[msg.sender]);
        return _tokenNonSoulbound[msg.sender][tokenId] || _contractNonSoulbound[msg.sender];
    }


    /**
     * @dev Set whether or not all tokens of a contract are soulbound/burnable
     */
    function configureContract(address creatorContractAddress, bool soulbound, bool burnable, string memory tokenURIPrefix) external creatorAdminRequired(creatorContractAddress) {
        IERC721CreatorCore(creatorContractAddress).setTokenURIPrefixExtension(tokenURIPrefix);
        _configureContract(creatorContractAddress, soulbound, burnable);
    }

    /**
     * @dev Mint a new soulbound token
     */
    function mintToken(address creatorContractAddress, address recipient, string memory tokenURI) external creatorAdminRequired(creatorContractAddress) {
        IERC721CreatorCore(creatorContractAddress).mintExtension(recipient, tokenURI);
    }

    /**
     * @dev Set the token uri for one token
     */
    function setTokenURI(address creatorContractAddress, uint256 tokenId, string calldata uri) external creatorAdminRequired(creatorContractAddress) {
        IERC721CreatorCore(creatorContractAddress).setTokenURIExtension(tokenId, uri);
    }

    /**
     * @dev Set the token uri for multiple tokens
     */
    function setTokenURI(address creatorContractAddress, uint256[] memory tokenId, string[] calldata uri) external creatorAdminRequired(creatorContractAddress) {
        IERC721CreatorCore(creatorContractAddress).setTokenURIExtension(tokenId, uri);
    }

}
