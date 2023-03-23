// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import "@manifoldxyz/libraries-solidity/contracts/access/IAdminControl.sol";
import "@manifoldxyz/creator-core-solidity/contracts/core/IERC721CreatorCore.sol";


/**
 * @title Soulbound
 * @notice A base contract that implements Soulbound functionality for ERC721 tokens.
 * @dev This contract includes mappings and a modifier for managing Soulbound tokens in a Creator Contract.
 */
abstract contract SoulboundBase {

    // Mapping of whether an address owns a Soulbound token in a given Creator Contract Address (false by default)
    mapping(address => mapping(address => bool)) internal _isSoulboundOwner;
    
    // Mapping of whether a token is Soulbound for a given Creator Contract Address (false by default)
    mapping(address => mapping(uint256 => bool)) internal _tokenIdIsSoulbound;

    // Array of Soulbound token owner addresses
    mapping(address => address[]) internal _soulboundOwners;

    /**
     * @dev Requires an address to implement IERC721CreatorCore and for the msg.sender to be an admin of the Creator Contract.
     */
    modifier creatorAdminRequired(address creatorContractAddress) {
        require(ERC165Checker.supportsInterface(creatorContractAddress, type(IERC721CreatorCore).interfaceId), "Invalid address");
        require(IAdminControl(creatorContractAddress).isAdmin(msg.sender), "Must be owner or admin");
        _;
    }
}