// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";

import "./ERC721LazyMintWhitelistBase.sol";
import "./IERC721LazyMintWhitelist.sol";

/**
 * Lazy Mint with Whitelist for ERC721 tokens
 */
contract ERC721LazyMintWhitelist is ERC721LazyMintWhitelistBase, AdminControl, IERC721LazyMintWhitelist {

    constructor(address creator, string memory prefix) {
        _initialize(creator, prefix);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(AdminControl, ERC721LazyMintWhitelistBase) returns (bool) {
        return interfaceId == type(IERC721LazyMintWhitelist).interfaceId || AdminControl.supportsInterface(interfaceId) || ERC721LazyMintWhitelistBase.supportsInterface(interfaceId);
    }

    function premint(address[] memory to) external override adminRequired {
        _premint(to);
    }

    function mint(bytes32[] memory merkleProof) external override payable {
        _mint(merkleProof);
    }

    function setAllowList(bytes32 _merkleRoot) external override adminRequired {
        _setAllowList(_merkleRoot);
    }

    function setTokenURIPrefix(string calldata prefix) external override adminRequired {
        _setTokenURIPrefix(prefix);
    }

    function withdraw(address _to, uint amount) external override adminRequired {
        _withdraw(_to, amount);
    }
    
}
