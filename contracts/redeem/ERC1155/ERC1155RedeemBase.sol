// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC1155CreatorCore.sol";
import "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";

import "../RedeemBase.sol";
import "./IERC1155RedeemBase.sol";

/**
 * @dev Burn NFT's to receive another lazy minted NFT
 */
abstract contract ERC1155RedeemBase is RedeemBase, IERC1155RedeemBase {

     // The creator mint contract
     address internal _creator;

    constructor(address creator) {
        require(ERC165Checker.supportsInterface(creator, type(IERC1155CreatorCore).interfaceId) ||
                ERC165Checker.supportsInterface(creator, type(IERC1155CreatorCore).interfaceId ^ type(ICreatorCore).interfaceId), 
                "Redeem: Minting reward contract must implement IERC1155CreatorCore");
        _creator = creator;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(RedeemBase, IERC165) returns (bool) {
        return interfaceId == type(IERC1155RedeemBase).interfaceId || RedeemBase.supportsInterface(interfaceId);
    }


}