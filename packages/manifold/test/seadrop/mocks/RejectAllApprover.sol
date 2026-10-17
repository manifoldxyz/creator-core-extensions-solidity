// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC1155CreatorExtensionApproveTransfer} from "@manifoldxyz/creator-core-solidity/contracts/extensions/ERC1155/IERC1155CreatorExtensionApproveTransfer.sol";

/**
 * @notice Contract-wide transfer approver (`creator.setApproveTransfer`)
 *         that rejects every transfer. Used to prove which approver Creator
 *         Core consults for the shim's token.
 */
contract RejectAllApprover is IERC1155CreatorExtensionApproveTransfer {
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return
            interfaceId == type(IERC1155CreatorExtensionApproveTransfer).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }

    function setApproveTransfer(address, bool) external pure override {}

    function approveTransfer(address, address, address, uint256[] calldata, uint256[] calldata)
        external
        pure
        override
        returns (bool)
    {
        return false;
    }
}
