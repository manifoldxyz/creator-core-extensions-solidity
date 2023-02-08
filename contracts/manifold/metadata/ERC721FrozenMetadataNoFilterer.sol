// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "./ERC721FrozenMetadata.sol";
import "../operatorfilterer/nofilterer/ERC721NoFilterer.sol";

/**
 * Manifold ERC721 Frozen Metadata Implementation with no filterers
 */
contract ERC721FrozenMetadataNoFilterer is ERC721FrozenMetadata, ERC721NoFilterer {    
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721FrozenMetadata, ERC721NoFilterer) returns (bool) {
        return ERC721NoFilterer.supportsInterface(interfaceId) || ERC721FrozenMetadata.supportsInterface(interfaceId);
    }
}
