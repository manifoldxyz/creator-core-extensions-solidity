// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

/**
 * Manifold ERC721 Edition Controller interface
 */
interface IManifoldERC721Edition {

    event SeriesCreated(address caller, address creator, uint256 series, uint256 maxSupply);

    /**
     * @dev Create a new series.  Returns the series id.
     */
    function createSeries(address creator, uint256 maxSupply, string calldata prefix) external returns(uint256);

    /**
     * @dev Get the latest series created.
     */
    function latestSeries(address creator) external view returns(uint256);

    /**
     * @dev Set the token uri prefix
     */
    function setTokenURIPrefix(address creator, uint256 series, string calldata prefix) external;
    
    /**
     * @dev Mint NFTs to a single recipient
     */
    function mint(address creator, uint256 series, address recipient, uint16 count) external;

    /**
     * @dev Mint NFTS to the recipients
     */
    function mint(address creator, uint256 series, address[] calldata recipients) external;

    /**
     * @dev Total supply of editions
     */
    function totalSupply(address creator, uint256 series) external view returns(uint256);

    /**
     * @dev Max supply of editions
     */
    function maxSupply(address creator, uint256 series) external view returns(uint256);
}
