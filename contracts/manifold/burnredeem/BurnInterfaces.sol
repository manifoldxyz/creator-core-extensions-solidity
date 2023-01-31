// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ERC721 {
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;
}

interface ERC1155 {
    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata data) external;
}

interface Burnable721 {
    function burn(uint256 tokenId) external;
}

interface OZBurnable1155 {
    function burn(address account, uint256 id, uint256 value) external;
}

interface Manifold1155 {
    function burn(address account, uint256[] memory tokenIds, uint256[] memory amounts) external;
}
