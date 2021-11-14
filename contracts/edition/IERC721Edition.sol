// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

/**
 * ERC721 Edition interface
 */
interface IERC721Edition {
    /**
     * @dev Activate the edition for a set number of NFTs
     */
    function activate(uint256 total) external;

    /**
     * @dev Update the URI parts used to construct the metadata for the open edition
     */
    function updateURIParts(string[] calldata uriParts) external;

    /**
     * @dev Mint NFTs to a single recipient
     */
    function mint(address recipient, uint256 count) external;

    /**
     * @dev Mint NFTS to the recipients
     */
    function mint(address[] calldata recipients) external;
}
