// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC721CreatorCore.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/CreatorExtension.sol";
import "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./IManifoldAirdrop.sol";

/**
 * Manifold airdrop extension. Add this extension to your creator contract in order to do airdrops.
 */
contract ManifoldAirdrop is AdminControl, CreatorExtension, ReentrancyGuard, IManifoldAirdrop {

    bool public enabled;

    constructor() AdminControl() {
        enabled = true;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(AdminControl, CreatorExtension) returns (bool) {
        return type(IManifoldAirdrop).interfaceId == interfaceId || AdminControl.supportsInterface(interfaceId) || CreatorExtension.supportsInterface(interfaceId);
    }
    
    /**
     * @dev See {IManifoldAirdrop-setEnabled}.
     */
    function setEnabled(bool enabled_) external override adminRequired {
        enabled = enabled_;
    }

    /**
     * @dev See {IManifoldAirdrop-isRegistered}.
     */ 
   function isRegistered(address tokenAddress) public view override returns (bool) {
        address[] memory registeredExtensions = IERC721CreatorCore(tokenAddress).getExtensions();
        for (uint i = 0; i < registeredExtensions.length; i++) {
            if (registeredExtensions[i] == address(this)) return true;
        }
        return false;
    }

    /**
     * @dev See {IManifoldAirdrop-airdrop}.
     */
    function airdrop(address tokenAddress, address[] calldata recipients, string memory tokenURI) external override nonReentrant {
        require(enabled, "Airdrops have been disabled");
        require(AdminControl(tokenAddress).isAdmin(msg.sender), "Must be admin of the token contract to mint");
        for (uint i = 0; i < recipients.length; i++) {
            IERC721CreatorCore(tokenAddress).mintExtension(recipients[i], tokenURI);
        }
    }

    /**
     * @dev See {IManifoldAirdrop-airdrop}.
     */
    function airdrop(address tokenAddress, address[] calldata recipients, string[] memory tokenURIs) external override nonReentrant {
        require(enabled, "Airdrops have been disabled");
        require(recipients.length == tokenURIs.length, "Invalid input");
        require(AdminControl(tokenAddress).isAdmin(msg.sender), "Must be admin of the token contract to mint");
        for (uint i = 0; i < recipients.length; i++) {
            IERC721CreatorCore(tokenAddress).mintExtension(recipients[i], tokenURIs[i]);
        }
    }
}