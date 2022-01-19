// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/libraries-solidity/contracts/access/AdminControlUpgradeable.sol";

import "./ERC721NumberedEditionBase.sol";

/**
 * ERC721 Numbered Edition Contract Implementation
 */
contract ERC721NumberedEditionImplementation is ERC721NumberedEditionBase, AdminControlUpgradeable {

    function initialize(address creator, uint256 maxSupply_, string[] memory uriParts) public initializer {
        __Ownable_init();
        _initialize(creator, maxSupply_, uriParts);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721NumberedEditionBase, AdminControlUpgradeable) returns (bool) {
        return ERC721NumberedEditionBase.supportsInterface(interfaceId) || AdminControlUpgradeable.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IERC721Edition-updateURIParts}.
     */
    function updateURIParts(string[] calldata uriParts) external override adminRequired {
        _updateURIParts(uriParts);
    }

    /**
     * @dev See {IERC721Edition-mint}.
     */
    function mint(address recipient, uint16 count) external override adminRequired {
        _mint(recipient, count);
    }

    /**
     * @dev See {IERC721Edition-mint}.
     */
    function mint(address[] calldata recipients) external override adminRequired {
        _mint(recipients);
    }

}
