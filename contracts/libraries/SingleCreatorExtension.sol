// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "@manifoldxyz/creator-core-solidity/contracts/core/IERC721CreatorCore.sol";
import "@manifoldxyz/creator-core-solidity/contracts/core/IERC1155CreatorCore.sol";

import "./LegacyInterfaces.sol";

abstract contract SingleCreatorBase {
    address internal _creator;
}

/**
 * @dev Extension that only uses a single creator contract instance
 */
abstract contract ERC721SingleCreatorExtension is SingleCreatorBase {

    constructor(address creator) {
        require(ERC165Checker.supportsInterface(creator, type(IERC721CreatorCore).interfaceId) ||
                ERC165Checker.supportsInterface(creator, LegacyInterfaces.IERC721CreatorCore_v1), 
                "Redeem: Minting reward contract must implement IERC721CreatorCore");
        _creator = creator;
    }

}

/**
 * @dev Extension that only uses a single creator contract instance
 */
abstract contract ERC1155SingleCreatorExtension is SingleCreatorBase {

    constructor(address creator) {
        require(ERC165Checker.supportsInterface(creator, type(IERC1155CreatorCore).interfaceId) ||
                ERC165Checker.supportsInterface(creator, type(IERC1155CreatorCore).interfaceId ^ type(ICreatorCore).interfaceId), 
                "Redeem: Minting reward contract must implement IERC1155CreatorCore");
        _creator = creator;
    }

}