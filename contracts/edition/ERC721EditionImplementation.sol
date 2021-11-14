// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/libraries-solidity/contracts/access/AdminControlUpgradeable.sol";

import "./IERC721Edition.sol";
import "./ERC721EditionBase.sol";

/**
 * ERC721 Edition Contract Implementation
 */
contract ERC721EditionImplementation is ERC721EditionBase, AdminControlUpgradeable, IERC721Edition {

    function initialize(address creator, string[] memory uriParts) public initializer {
        __Ownable_init();
        _initialize(creator, uriParts);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(AdminControlUpgradeable, ERC721EditionBase) returns (bool) {
        return interfaceId == type(IERC721Edition).interfaceId || AdminControlUpgradeable.supportsInterface(interfaceId) || ERC721EditionBase.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IERC721Edition-activate}.
     */
    function activate(uint256 total) external override adminRequired {
        _activate(total);
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
    function mint(address recipient, uint256 count) external override adminRequired {
        _mint(recipient, count);
    }

    /**
     * @dev See {IERC721Edition-mint}.
     */
    function mint(address[] calldata recipients) external override adminRequired {
        _mint(recipients);
    }

}
