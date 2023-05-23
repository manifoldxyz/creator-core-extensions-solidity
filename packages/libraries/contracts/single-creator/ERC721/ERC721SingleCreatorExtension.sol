// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "./ERC721SingleCreatorExtensionBase.sol";

/**
 * @dev Extension that only uses a single creator contract instance
 */
abstract contract ERC721SingleCreatorExtension is ERC721SingleCreatorExtensionBase {

    constructor(address creator) {
        _setCreator(creator);
    }
}