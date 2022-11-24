// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./OperatorFilter.sol";
import "../creator/extensions/ERC1155/ERC1155CreatorExtensionApproveTransfer.sol";

contract ERC1155OperatorFilter is ERC1155CreatorExtensionApproveTransfer, OperatorFilter, ReentrancyGuard {
    constructor(address operatorFilterRegistry) OperatorFilter(operatorFilterRegistry) {}

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override (AdminControl, ERC1155CreatorExtensionApproveTransfer)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function approveTransfer(address operator, address from, address, uint256[] calldata, uint256[] calldata)
        external
        view
        override
        onlyAllowedOperator(msg.sender, operator, from)
        returns (bool)
    {
        return true;
    }

    function mintNew(address creator, address[] calldata to, uint256[] calldata amounts, string[] calldata uris)
        external
        creatorAdminRequired(creator)
        returns (uint256[] memory)
    {
        return IERC1155CreatorCore(creator).mintExtensionNew(to, amounts, uris);
    }

    //TODO: other 1155 mint functions
}
