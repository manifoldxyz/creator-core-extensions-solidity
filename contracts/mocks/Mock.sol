// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/creator-core-solidity/contracts/ERC721Creator.sol";
import "@manifoldxyz/creator-core-solidity/contracts/mocks/MockERC721.sol";
import "@manifoldxyz/creator-core-solidity/contracts/mocks/MockERC1155.sol";

import "../enumerable/ERC721/ERC721OwnerEnumerableExtension.sol";

contract MockTestERC721Creator is ERC721Creator {
     constructor (string memory _name, string memory _symbol) ERC721Creator(_name, _symbol) {}
}

contract MockTestERC721 is MockERC721 {
     constructor (string memory _name, string memory _symbol) MockERC721(_name, _symbol) {}
}

contract MockTestERC1155 is MockERC1155 {
     constructor (string memory uri) MockERC1155(uri) {}
}


contract MockERC721OwnerEnumerableExtension is ERC721OwnerEnumerableExtension {
    function testMint(address creator, address to) public {
        ERC721Creator(creator).mintExtension(to);
    }
}