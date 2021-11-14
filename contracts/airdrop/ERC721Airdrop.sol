// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";

import "./ERC721AirdropBase.sol";
import "./IERC721Airdrop.sol";

/**
 * Airdrop ERC721 tokens to a set of addresses
 */
contract ERC721Airdrop is ERC721AirdropBase, AdminControl, IERC721Airdrop {

    constructor(address creator, string memory prefix) {
        _initialize(creator, prefix);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(AdminControl, ERC721AirdropBase) returns (bool) {
        return interfaceId == type(IERC721Airdrop).interfaceId || AdminControl.supportsInterface(interfaceId) || ERC721AirdropBase.supportsInterface(interfaceId);
    }

    function airdrop(address[] calldata recipients) external override adminRequired {
        _airdrop(recipients);
    }

    function setTokenURIPrefix(string calldata prefix) external override adminRequired {
        _setTokenURIPrefix(prefix);
    }
    
}
