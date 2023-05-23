// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "./ERC1155SingleCreatorExtensionBase.sol";

/**
 * @dev Extension that only uses a single creator contract instance
 */
abstract contract ERC1155SingleCreatorExtension is ERC1155SingleCreatorExtensionBase {

    constructor(address creator) {
        _setCreator(creator);
    }
}