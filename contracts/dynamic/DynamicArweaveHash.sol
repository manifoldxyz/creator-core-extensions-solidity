// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC721CreatorCore.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/CreatorExtension.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/ICreatorExtensionTokenURI.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/ERC721/IERC721CreatorExtensionApproveTransfer.sol";

abstract contract DynamicArweaveHash is CreatorExtension, Ownable, ICreatorExtensionTokenURI, IERC721CreatorExtensionApproveTransfer {

    using Strings for uint256;

    address private immutable _creator;
    string[] public arweaveHashes;

    constructor(address creator) {
        _creator = creator;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(CreatorExtension, IERC165) returns (bool) {
        return interfaceId == type(ICreatorExtensionTokenURI).interfaceId 
        || interfaceId == type(IERC721CreatorExtensionApproveTransfer).interfaceId
        || super.supportsInterface(interfaceId);
    }

    function mint(address to) public virtual onlyOwner returns(uint256) {
        return IERC721CreatorCore(_creator).mintExtension(to);
    }

    function _getName() internal view virtual returns(string memory);

    function _getDescription() internal view virtual returns(string memory);

    function _getImageHash(uint256 tokenId) internal view virtual returns(string memory);

    function setArweaveHashes(string[] memory _arweaveHashes) external virtual;
}
