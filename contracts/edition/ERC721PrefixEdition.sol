// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";

import "./IERC721PrefixEdition.sol";
import "./ERC721PrefixEditionBase.sol";

/**
 * ERC721 Edition Contract
 */
contract ERC721PrefixEdition is ERC721PrefixEditionBase, AdminControl {

    constructor(address creator, uint256 maxSupply_, string memory prefix) {
        _initialize(creator, maxSupply_, prefix);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721PrefixEditionBase, AdminControl) returns (bool) {
        return ERC721PrefixEditionBase.supportsInterface(interfaceId) || AdminControl.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IERC721PrefixEdition-setTokenURIPrefix}.
     */
    function setTokenURIPrefix(string calldata prefix) external override adminRequired {
        _setTokenURIPrefix(prefix);
    }

    /**
     * @dev See {IERC721PrefixEdition-mint}.
     */
    function mint(address recipient, uint16 count) external override adminRequired {
        _mint(recipient, count);
    }

    /**
     * @dev See {IERC721PrefixEdition-mint}.
     */
    function mint(address[] calldata recipients) external override adminRequired {
        _mint(recipients);
    }
}
