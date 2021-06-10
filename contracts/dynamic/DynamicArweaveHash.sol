// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "manifoldxyz-creator-core-solidity/contracts/core/IERC721CreatorCore.sol";
import "manifoldxyz-creator-core-solidity/contracts/extensions/CreatorExtension.sol";
import "manifoldxyz-creator-core-solidity/contracts/extensions/ICreatorExtensionTokenURI.sol";
import "manifoldxyz-creator-core-solidity/contracts/extensions/ERC721/IERC721CreatorExtensionApproveTransfer.sol";
import "../libraries/ABDKMath64x64.sol";
import "../utils/JakeMeltTokenHashes.sol";

contract DynamicArweaveHash is CreatorExtension, Ownable, ICreatorExtensionTokenURI, IERC721CreatorExtensionApproveTransfer {

    using Strings for uint256;
    using ABDKMath64x64 for int128;

    address private immutable _creator;
    uint256 private _creationTimestamp;

    constructor(address creator) {
        _creationTimestamp = block.timestamp;
        _creator = creator;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(CreatorExtension, IERC165) returns (bool) {
        return interfaceId == type(ICreatorExtensionTokenURI).interfaceId 
        || interfaceId == type(IERC721CreatorExtensionApproveTransfer).interfaceId
        || super.supportsInterface(interfaceId);
    }

    function mint(address to) external onlyOwner {
        IERC721CreatorCore(_creator).mintExtension(to);
    }

    function tokenURI(address creator, uint256 tokenId) external view override returns (string memory) {
        require(creator == _creator, "Invalid token");

        // TODO: get base JSON from Jake
        return string(abi.encodePacked('data:application/json;utf8,{"name":"Melt", "description":"Days passed: ',((block.timestamp-_creationTimestamp)/86400).toString(),'", "image":"https://https://arweave.net/',
            _getImageHash(),
            '"}'));
    }

    // TODO: switch to once per day instead of once per block 
    function _getImageHash() private view returns (string memory imageHash) {
        // uint256 daysPassed = (block.timestamp-_creationTimestamp)/86400;
        // For testing purposes, switch every block
        uint256 daysPassed = block.number % 2;
        return JakeMeltTokenHashes.getHash(daysPassed);
    }
    
    function setApproveTransfer(address creator, bool enabled) public override onlyOwner {
        IERC721CreatorCore(creator).setApproveTransferExtension(enabled);
    }

    function approveTransfer(address, address, uint256) public view override returns (bool) {
        require(msg.sender == _creator, "Invalid requester");      
        return true;
    }
    
}
