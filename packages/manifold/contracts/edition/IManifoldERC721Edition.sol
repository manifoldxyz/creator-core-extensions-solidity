// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

/**
 * Manifold ERC721 Edition Controller interface
 */
interface IManifoldERC721Edition {

    event SeriesCreated(address caller, address creatorCore, uint256 series, uint256 maxSupply);

    /**
     * @dev Create a new series.  Returns the series id.
     */
    function createSeries(address creatorCore, uint256 maxSupply, string calldata prefix, uint256 instanceId) external returns(uint256);

    /**
     * @dev Set the token uri prefix
     */
    function setTokenURIPrefix(address creatorCore, uint256 instanceId, string calldata prefix) external;
    
    /**
     * @dev Mint NFTs to a single recipient
     */
    function mint(address creatorCore, uint256 instanceId, address recipient, uint16 count) external;

    /**
     * @dev Mint NFTS to the recipients
     */
    function mint(address creatorCore, uint256 instanceId, address[] calldata recipients) external;

    /**
     * @dev Total supply of editions
     */
    function totalSupply(address creatorCore, uint256 instanceId) external view returns(uint256);

    /**
     * @dev Max supply of editions
     */
    function maxSupply(address creatorCore, uint256 instanceId) external view returns(uint256);
}
