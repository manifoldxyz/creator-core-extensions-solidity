// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC721CreatorCore.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/ERC721/IERC721CreatorExtensionApproveTransfer.sol";
import "@manifoldxyz/libraries-solidity/contracts/access/IAdminControl.sol";

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

/**
 * @title Soulbound token
 * @author manifold.xyz
 * @notice Souldbound shared extension for Manifold Creator contracts.
 */
contract ERC721Soulbound is IERC165, IERC721CreatorExtensionApproveTransfer {

    bytes4 private constant IERC721CreatorExtensionApproveTransfer_v1 = 0x99cdaa22;
    mapping(address => mapping(uint256 => bool)) private _nonSoulbound;

    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165) returns (bool) {
        return interfaceId == type(IERC721CreatorExtensionApproveTransfer).interfaceId ||
            interfaceId == IERC721CreatorExtensionApproveTransfer_v1 ||
            interfaceId == type(IERC165).interfaceId;
    }

    /**
     * @notice This extension is shared, not single-creator. So we must ensure
     * that a burn redeems's initializer is an admin on the creator contract
     * @param creatorContractAddress    the address of the creator contract to check the admin against
     */
    modifier creatorAdminRequired(address creatorContractAddress) {
        require(IAdminControl(creatorContractAddress).isAdmin(msg.sender), "Wallet is not an admin");
        _;
    }

    /**
     * @dev Set whether or not the creator will check the extension for approval of token transfer
     */
    function setApproveTransfer(address creatorContractAddress, bool enabled) external creatorAdminRequired(creatorContractAddress) {
        require(ERC165Checker.supportsInterface(creatorContractAddress, type(IERC721CreatorCore).interfaceId), "creator must implement IERC721CreatorCore");
        IERC721CreatorCore(creatorContractAddress).setApproveTransferExtension(enabled);
    }

    /**
     * @dev Called by creator contract to approve a transfer
     */
    function approveTransfer(address, address from, address, uint256 tokenId) external view returns (bool) {
        return _approveTransfer(from, tokenId);
    }

    /**
     * @dev Called by creator contract to approve a transfer (v1)
     */
    function approveTransfer(address from, address, uint256 tokenId) external view returns (bool) {
        return _approveTransfer(from, tokenId);
    }

    function _approveTransfer(address from, uint256 tokenId) private view returns (bool) {
        if (from == address(0)) return true;
        return _nonSoulbound[msg.sender][tokenId];
    }

    /**
     * @dev Set whether or not a token is soulbound
     */
    function setSoulbound(address creatorContractAddress, uint256 tokenId, bool soulbound) external creatorAdminRequired(creatorContractAddress) {
        _nonSoulbound[creatorContractAddress][tokenId] = !soulbound;
    }

    /**
     * @dev Set whether or not a set of tokens are soulbound
     */
    function setSoulbound(address creatorContractAddress, uint256[] memory tokenIds, bool soulbound) external creatorAdminRequired(creatorContractAddress) {
        for (uint i; i < tokenIds.length;) {
            _nonSoulbound[creatorContractAddress][tokenIds[i]] = !soulbound;
            unchecked { ++i; }
        }
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
