// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./OperatorFilter.sol";
import "../creator/extensions/ERC721/ERC721CreatorExtensionApproveTransfer.sol";

contract ERC721OperatorFilter is ERC721CreatorExtensionApproveTransfer, OperatorFilter, ReentrancyGuard {
    constructor(address operatorFilterRegistry) OperatorFilter(operatorFilterRegistry) {}

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override (AdminControl, ERC721CreatorExtensionApproveTransfer)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function approveTransfer(address operator, address from, address, uint256)
        external
        view
        override
        onlyAllowedOperator(msg.sender, operator, from)
        returns (bool)
    {
        return true;
    }

    function mint(address creator, address recipient, string calldata tokenURI)
        external
        nonReentrant
        creatorAdminRequired(creator)
        returns (uint256)
    {
        return IERC721CreatorCore(creator).mintExtension(recipient, tokenURI);
    }

    //TODO: other 721 mint functions
}
