// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

/**
 * Nifty Gateway ERC721 Numbered Edition interface
 */
interface INiftyGatewayERC721NumberedEdition {

    /**
     * @dev Activate for nifty
     */
    function activate(address[] calldata minters, address niftyOmnibusWallet) external;

    /**
     * @dev Mint NFTs to nifty gateway
     */
    function mintNifty(uint256 niftyType, uint16 count) external;

    /**
     * @dev Mint count (used by nifty gateway)
     */
    function _mintCount(uint256 niftyType) external view returns (uint256);
}
