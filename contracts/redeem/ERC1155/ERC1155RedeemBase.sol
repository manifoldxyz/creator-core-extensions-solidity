// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC1155CreatorCore.sol";
import "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";

import "../../libraries/single-creator/ERC1155/ERC1155SingleCreatorExtension.sol";

import "../RedeemBase.sol";
import "./IERC1155RedeemBase.sol";

/**
 * @dev Burn NFT's to receive another lazy minted NFT
 */
abstract contract ERC1155RedeemBase is ERC1155SingleCreatorExtension, RedeemBase, IERC1155RedeemBase {
    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(RedeemBase, IERC165) returns (bool) {
        return interfaceId == type(IERC1155RedeemBase).interfaceId || RedeemBase.supportsInterface(interfaceId);
    }


}