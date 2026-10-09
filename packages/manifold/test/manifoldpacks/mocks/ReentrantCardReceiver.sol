// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IManifoldPacksSeaDropShim} from "../../../contracts/manifoldpacks/IManifoldPacksSeaDropShim.sol";
import {ManifoldPacksSeaDropShim} from "../../../contracts/manifoldpacks/ManifoldPacksSeaDropShim.sol";

/**
 * @title  ReentrantCardReceiver
 * @notice A malicious ERC1155 card recipient that attempts to re-enter the pack
 *         contract's `deliverBatch` from inside the `onERC1155BatchReceived`
 *         hook (fired when rip cards are delivered via `_mintBatch`). Used to
 *         prove `deliverBatch`'s `nonReentrant` guard holds: the re-entrant call
 *         must revert, and because a rip batch is atomic, the whole outer rip
 *         reverts too.
 *
 *         This contract must be the pack owner for the pack it rips (cards are
 *         delivered to `ownerOf(packId)`), so tests transfer a pack to it first.
 */
contract ReentrantCardReceiver {
    ManifoldPacksSeaDropShim public immutable packs;
    IManifoldPacksSeaDropShim.RipOrder internal _reentryOrder;
    bool public armed;
    bool public reentered;

    constructor(address packs_) {
        packs = ManifoldPacksSeaDropShim(packs_);
    }

    /// @notice Store the order the hook will try to replay, and arm the attack.
    function arm(IManifoldPacksSeaDropShim.RipOrder calldata order) external {
        _reentryOrder = order;
        armed = true;
    }

    function _tryReenter() internal {
        if (!armed) return;
        armed = false; // one-shot
        reentered = true;
        IManifoldPacksSeaDropShim.RipOrder[] memory orders =
            new IManifoldPacksSeaDropShim.RipOrder[](1);
        orders[0] = _reentryOrder;
        // This call re-enters deliverBatch; the nonReentrant guard must revert it.
        packs.deliverBatch(orders);
    }

    // ERC1155 receiver hooks — rip delivers 4 cards via _mintBatch.
    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        returns (bytes4)
    {
        _tryReenter();
        return this.onERC1155BatchReceived.selector;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        external
        returns (bytes4)
    {
        _tryReenter();
        return this.onERC1155Received.selector;
    }

    // ERC721 receiver so a pack can be transferred to this contract.
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function supportsInterface(bytes4) external pure returns (bool) {
        return true;
    }
}
