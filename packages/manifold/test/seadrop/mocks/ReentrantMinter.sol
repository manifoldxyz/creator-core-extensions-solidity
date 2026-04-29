// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

interface IShimMintTarget {
    function mintSeaDrop(address minter, uint256 quantity) external;
}

/**
 * @notice Malicious ERC1155 receiver that re-enters `mintSeaDrop` on the
 *         shim during the safe-transfer hook. Used to prove the shim's
 *         `nonReentrant` modifier blocks the attack.
 */
contract ReentrantMinter is IERC1155Receiver {
    IShimMintTarget public immutable shim;
    bool public attacked;

    constructor(address shim_) {
        shim = IShimMintTarget(shim_);
    }

    /// @dev On receiving ERC1155 tokens, re-enter mintSeaDrop. The shim's
    ///      nonReentrant modifier should revert this nested call.
    function onERC1155Received(
        address, // operator
        address, // from
        uint256, // id
        uint256, // value
        bytes calldata // data
    ) external override returns (bytes4) {
        if (!attacked) {
            attacked = true;
            // Re-enter — should revert with ReentrancyGuard's "REENTRANCY"
            shim.mintSeaDrop(address(this), 1);
        }
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId)
        external
        pure
        override
        returns (bool)
    {
        return
            interfaceId == type(IERC1155Receiver).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }
}
