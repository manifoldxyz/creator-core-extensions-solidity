// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

/**
 * ERC721 Lazy Mint with Whitelist interface
 */
interface IERC721LazyMintWhitelist {

    /**
     * @dev premints gifted nfts
     */
    function premint(address[] memory to) external;
    

    /**
     * @dev external mint function 
     */
    function mint(bytes32[] memory merkleProof) external payable;

    /**
     * @dev sets the allowList
     */
    function setAllowList(bytes32 _merkleRoot) external;

    /**
     * @dev Set the token uri prefix
     */
    function setTokenURIPrefix(string calldata prefix) external;

    /**
     * @dev Withdraw funds from the contract
     */
    function withdraw(address _to, uint amount) external;
}
