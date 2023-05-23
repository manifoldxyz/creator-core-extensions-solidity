// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "./ERC1155FrozenMetadata.sol";
import "../operatorfilterer/nofilterer/ERC1155NoFilterer.sol";

/**
 * Manifold ERC1155 Frozen Metadata Implementation with no filterers
 */
contract ERC1155FrozenMetadataNoFilterer is ERC1155FrozenMetadata, ERC1155NoFilterer {    
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1155FrozenMetadata, ERC1155NoFilterer) returns (bool) {
        return ERC1155NoFilterer.supportsInterface(interfaceId) || ERC1155FrozenMetadata.supportsInterface(interfaceId);
    }
}
