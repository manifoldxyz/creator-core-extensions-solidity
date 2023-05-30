// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/libraries-solidity/contracts/access/AdminControlUpgradeable.sol";

import "./ERC721PrefixEditionBase.sol";

/**
 * ERC721 Prefix Edition Contract Implementation
 */
contract ERC721PrefixEditionImplementation is ERC721PrefixEditionBase, AdminControlUpgradeable {

    function initialize(address creator, uint256 maxSupply_, string memory prefix) public initializer {
        __Ownable_init();
        _initialize(creator, maxSupply_, prefix);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721PrefixEditionBase, AdminControlUpgradeable) returns (bool) {
        return ERC721PrefixEditionBase.supportsInterface(interfaceId) || AdminControlUpgradeable.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IERC721PrefixEdition-setTokenURIPrefix}.
     */
    function setTokenURIPrefix(string calldata prefix) external override adminRequired {
        _setTokenURIPrefix(prefix);
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
