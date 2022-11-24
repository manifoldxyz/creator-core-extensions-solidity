// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./CreatorOperatorFilterer.sol";
import "../creator/extensions/ERC721/ERC721CreatorExtensionApproveTransfer.sol";

contract ERC721OperatorFilterer is ERC721CreatorExtensionApproveTransfer, CreatorOperatorFilterer {
    constructor(address operatorFilterRegistry, address subscriptionOrRegistrantToCopy, bool subscribe)
        CreatorOperatorFilterer(operatorFilterRegistry, subscriptionOrRegistrantToCopy, subscribe)
    {}

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override (ERC721CreatorExtensionApproveTransfer, AdminControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function approveTransfer(address operator, address from, address, uint256)
        external
        view
        override
        onlyAllowedOperator(operator, from)
        returns (bool)
    {
        return true;
    }

    function mint(address creator, address recipient, string calldata tokenURI)
        external
        creatorAdminRequired(creator)
        returns (uint256)
    {
        return IERC721CreatorCore(creator).mintExtension(recipient, tokenURI);
    }

    //TODO: other 721 mint functions
}
