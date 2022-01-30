// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

/**
 * ERC721 Edition interface
 */
interface IERC721Edition {

    /**
     * @dev Mint NFTs to a single recipient
     */
    function mint(address recipient, uint16 count) external;

    /**
     * @dev Mint NFTS to the recipients
     */
    function mint(address[] calldata recipients) external;

    /**
     * @dev Total supply of editions
     */
    function totalSupply() external view returns(uint256);

    /**
     * @dev Max supply of editions
     */
    function maxSupply() external view returns(uint256);
}
