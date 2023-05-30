// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "@manifoldxyz/creator-core-solidity/contracts/core/IERC721CreatorCore.sol";

import "../../LegacyInterfaces.sol";
import "../SingleCreatorExtensionBase.sol";

/**
 * @dev Extension that only uses a single creator contract instance
 */
abstract contract ERC721SingleCreatorExtensionBase is SingleCreatorExtensionBase {

    function _setCreator(address creator) internal override {
        require(ERC165Checker.supportsInterface(creator, type(IERC721CreatorCore).interfaceId) ||
                ERC165Checker.supportsInterface(creator, LegacyInterfaces.IERC721CreatorCore_v1), 
                "Creator contract must implement IERC721CreatorCore");
        super._setCreator(creator);
    }
  
}