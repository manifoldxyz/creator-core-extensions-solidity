// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "./IERC721Edition.sol";

/**
 * ERC721 Numbered Edition interface
 */
interface IERC721NumberedEdition is IERC721Edition {

    /**
     * @dev Update the URI parts used to construct the metadata for the open edition
     */
    function updateURIParts(string[] calldata uriParts) external;

}
