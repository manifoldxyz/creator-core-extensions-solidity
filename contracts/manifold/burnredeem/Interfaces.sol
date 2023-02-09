// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface Burnable721 {
    function burn(uint256 tokenId) external;
}

interface OZBurnable1155 {
    function burn(address account, uint256 id, uint256 value) external;
}

interface Manifold1155 {
    function burn(address account, uint256[] memory tokenIds, uint256[] memory amounts) external;
}
