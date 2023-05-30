// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./DynamicArweaveHash.sol";

/**
 * A token that changes with time
 */
contract TimeToken is DynamicArweaveHash {

    // The image cycle cadence
    uint256 private _cadence;
    // The token name
    string private _name;
    // The token description
    string private _description;
    // Token creation timestamp (used to calculate cycle)
    uint256 private _creationTimestamp;
    // Minted token id
    uint256 private _tokenId;

    constructor(address creator, string memory name, string memory description, uint256 cadence) ERC721SingleCreatorExtension(creator) {
        _creationTimestamp = block.timestamp;
        _cadence = cadence;
        _name = name;
        _description = description;
    }

    function mint(address to) public virtual onlyOwner returns(uint256) {
        require(_tokenId == 0, "Already minted");
        _tokenId = _mint(to);
        return _tokenId;
    }

    function _getName() internal view virtual override returns(string memory) {
        return _name;
    }

    function _getDescription() internal view virtual override returns(string memory) {
        return _description;
    }

    function _getImageHash(uint256) internal view override returns(string memory) {
        return imageArweaveHashes[(block.timestamp - _creationTimestamp)/_cadence % imageArweaveHashes.length];
    }

    function _getAnimationHash(uint256) internal view override returns(string memory) {
        return animationArweaveHashes[(block.timestamp - _creationTimestamp)/_cadence % animationArweaveHashes.length];
    }

}