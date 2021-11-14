// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

/**
 * Nifty Gateway ERC721 Edition interface
 */
interface INiftyGatewayERC721Edition {
    /**
     * @dev Activate the edition for a set number of NFTs
     */
    function activate(uint256 total, address[] calldata minters, address niftyOmnibusWallet) external;

    /**
     * @dev Update the URI parts used to construct the metadata for the open edition
     */
    function updateURIParts(string[] calldata uriParts) external;

    /**
     * @dev Mint NFTs to nifty gateway
     */
    function mintNifty(uint256 niftyType, uint256 count) external;

    /**
     * @dev Mint count (used by nifty gateway)
     */
    function _mintCount(uint256 niftyType) external view returns (uint256);
}
