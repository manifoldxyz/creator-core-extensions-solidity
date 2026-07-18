// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ManifoldPacksTestBase} from "./ManifoldPacksTestBase.t.sol";
import {IManifoldPacksSeaDropShim} from "../../contracts/manifoldpacks/IManifoldPacksSeaDropShim.sol";

/**
 * @title  ManifoldPacksPausable
 * @notice Coverage for the owner-controlled secondary-transfer pause (OpenSea
 *         ERC721SeaDropPausable mechanic, scoped so it never blocks mint or the
 *         rip burn).
 *
 *         Key divergences from upstream ERC721SeaDropPausable, all asserted here:
 *           - defaults UNPAUSED (upstream defaults paused);
 *           - the rip burn still succeeds while paused (upstream reverts on any
 *             `from != 0`, which would brick every rip);
 *           - mint still succeeds while paused.
 */
contract ManifoldPacksPausable is ManifoldPacksTestBase {
    /// @notice Mirror of IManifoldPacksSeaDropShim.TransfersPausedChanged for expectEmit.
    event TransfersPausedChanged(bool paused);

    // ---------------------------------------------------------------------
    // Defaults + setter.
    // ---------------------------------------------------------------------

    function test_defaultsUnpaused() public {
        assertEq(packs.transfersPaused(), false, "trading ON by default");
    }

    function test_updateTransfersPaused_onlyOwner() public {
        vm.prank(collector);
        vm.expectRevert();
        packs.updateTransfersPaused(true);
    }

    function test_updateTransfersPaused_emitsEvent() public {
        vm.expectEmit(false, false, false, true, address(packs));
        emit TransfersPausedChanged(true);
        vm.prank(owner);
        packs.updateTransfersPaused(true);
        assertEq(packs.transfersPaused(), true, "paused");

        vm.prank(owner);
        packs.updateTransfersPaused(false);
        assertEq(packs.transfersPaused(), false, "unpaused");
    }

    // ---------------------------------------------------------------------
    // Pause blocks SECONDARY transfers + approvals.
    // ---------------------------------------------------------------------

    function test_pausedBlocksSecondaryTransfer() public {
        vm.prank(owner);
        packs.updateTransfersPaused(true);

        vm.prank(owner);
        vm.expectRevert(IManifoldPacksSeaDropShim.TransfersPaused.selector);
        packs.transferFrom(owner, collector, 1);
    }

    function test_pausedBlocksApprove() public {
        vm.prank(owner);
        packs.updateTransfersPaused(true);

        vm.prank(owner);
        vm.expectRevert(IManifoldPacksSeaDropShim.TransfersPaused.selector);
        packs.approve(collector, 1);
    }

    function test_pausedBlocksSetApprovalForAll() public {
        vm.prank(owner);
        packs.updateTransfersPaused(true);

        vm.prank(owner);
        vm.expectRevert(IManifoldPacksSeaDropShim.TransfersPaused.selector);
        packs.setApprovalForAll(collector, true);
    }

    // ---------------------------------------------------------------------
    // Pause does NOT block mint or rip (the load-bearing carve-outs).
    // ---------------------------------------------------------------------

    function test_pausedDoesNotBlockMint() public {
        vm.prank(owner);
        packs.updateTransfersPaused(true);

        // A fresh SeaDrop mint (from == 0) must still succeed while paused.
        uint256 beforeSupply = packs.totalSupply();
        seaDropCaller.mint(address(packs), collector, 1);
        assertEq(packs.totalSupply(), beforeSupply + 1, "mint succeeds while paused");
    }

    function test_pausedDoesNotBlockRip() public {
        vm.prank(owner);
        packs.updateTransfersPaused(true);

        // Ripping pack 1 burns it (to == 0) and mints cards — must succeed while paused.
        IManifoldPacksSeaDropShim.RipOrder[] memory orders = new IManifoldPacksSeaDropShim.RipOrder[](1);
        orders[0] = buildFixtureRipOrder(1);

        vm.prank(signerAddr);
        packs.deliverBatch(orders);

        vm.expectRevert();
        packs.ownerOf(1); // burned
        for (uint256 i = 0; i < 4; i++) {
            assertEq(creator.balanceOf(owner, startingCardTokenId + i), 1, "rip cards minted while paused");
        }
    }

    // ---------------------------------------------------------------------
    // Unpause restores secondary transfers.
    // ---------------------------------------------------------------------

    function test_unpauseRestoresTransfer() public {
        vm.prank(owner);
        packs.updateTransfersPaused(true);
        vm.prank(owner);
        packs.updateTransfersPaused(false);

        vm.prank(owner);
        packs.transferFrom(owner, collector, 1);
        assertEq(packs.ownerOf(1), collector, "transfer works after unpause");
    }

    function test_unpausedTransferWorksByDefault() public {
        // No pause ever set — secondary transfer works out of the box.
        vm.prank(owner);
        packs.transferFrom(owner, collector, 2);
        assertEq(packs.ownerOf(2), collector, "default-unpaused transfer works");
    }
}
