// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC721CreatorCore.sol";
import "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";

import "../libraries/SingleCreatorExtension.sol";

contract ERC721Airdrop is ERC721SingleCreatorExtension, AdminControl {

    constructor(address creator) ERC721SingleCreatorExtension(creator) {}

    function airdrop(address[] calldata to) external adminRequired {
        for (uint i = 0; i < to.length; i++) {
            IERC721CreatorCore(_creator).mintExtension(to[i]);
        }
    }

    function airdrop(address[] calldata to, string[] calldata uris) external adminRequired {
        require(to.length == uris.length, "Invalid input");
        for (uint i = 0; i < to.length; i++) {
            IERC721CreatorCore(_creator).mintExtension(to[i], uris[i]);
        }
    }

    function setBaseTokenURI(string calldata uri) external adminRequired {
        IERC721CreatorCore(_creator).setBaseTokenURIExtension(uri);
    }

    function setBaseTokenURI(string calldata uri, bool identical) external adminRequired {
        IERC721CreatorCore(_creator).setBaseTokenURIExtension(uri, identical);
    }

    function setTokenURI(uint256 tokenId, string calldata uri) external adminRequired {
        IERC721CreatorCore(_creator).setTokenURIExtension(tokenId, uri);
    }

    function setTokenURI(uint256[] calldata tokenIds, string[] calldata uris) external adminRequired {
        IERC721CreatorCore(_creator).setTokenURIExtension(tokenIds, uris);
    }

    function setTokenURIPrefix(string calldata prefix) external adminRequired {
        IERC721CreatorCore(_creator).setTokenURIPrefixExtension(prefix);
    }
    
}
