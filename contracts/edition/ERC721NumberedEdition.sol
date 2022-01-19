// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";

import "./IERC721NumberedEdition.sol";
import "./ERC721NumberedEditionBase.sol";

/**
 * ERC721 Edition Contract
 */
contract ERC721NumberedEdition is ERC721NumberedEditionBase, AdminControl {

    constructor(address creator, uint256 maxSupply_, string[] memory uriParts) {
        _initialize(creator, maxSupply_, uriParts);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721NumberedEditionBase, AdminControl) returns (bool) {
        return ERC721NumberedEditionBase.supportsInterface(interfaceId) || AdminControl.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IERC721NumberedEdition-updateURIParts}.
     */
    function updateURIParts(string[] calldata uriParts) external override adminRequired {
        _updateURIParts(uriParts);
    }

    /**
     * @dev See {IERC721NumberedEdition-mint}.
     */
    function mint(address recipient, uint16 count) external override adminRequired {
        _mint(recipient, count);
    }

    /**
     * @dev See {IERC721NumberedEdition-mint}.
     */
    function mint(address[] calldata recipients) external override adminRequired {
        _mint(recipients);
    }
}
