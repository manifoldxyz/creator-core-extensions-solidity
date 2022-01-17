// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "./IERC721Edition.sol";

/**
 * ERC721 Prefix Edition interface
 */
interface IERC721PrefixEdition is IERC721Edition {

    /**
     * @dev Set the token uri prefix
     */
    function setTokenURIPrefix(string calldata prefix) external;

}
