// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ManifoldPacksTestBase} from "./ManifoldPacksTestBase.t.sol";
import {IManifoldPacks} from "../../contracts/manifoldpacks/IManifoldPacks.sol";

import {IERC721A} from "ERC721A/IERC721A.sol";

/**
 * @title  ManifoldPacksReplay
 * @notice US-008 — Replay / already-ripped / in-batch-duplicate tests (AC-6).
 *
 *         Replay is structurally impossible (nonce-less design): once a pack is
 *         ripped it is burned, so any second attempt hits `ownerOf(packId)`,
 *         which reverts ERC721A's OWN `OwnerQueryForNonexistentToken`. There is
 *         NO bespoke replay error and NO nonce ledger — the burned-pack state IS
 *         the replay lock. deliverBatch is atomic, so an in-batch duplicate
 *         rolls the whole batch back.
 */
contract ManifoldPacksReplay is ManifoldPacksTestBase {
    // ------------------------------------------------------------------
    // AC-6: a used permit cannot be replayed across transactions.
    // ------------------------------------------------------------------

    /// @notice After a successful rip, resubmitting the exact same permit
    ///         reverts OwnerQueryForNonexistentToken (the pack is burned, so
    ///         ownerOf reverts — ERC721A's own error, no nonces).
    function testReplayAfterRipReverts() public {
        uint256 packId = 1;
        IManifoldPacks.RipOrder memory order = buildFixtureRipOrder(packId);

        IManifoldPacks.RipOrder[] memory orders = new IManifoldPacks.RipOrder[](1);
        orders[0] = order;

        // First submission succeeds and burns the pack.
        vm.prank(signerAddr);
        packs.deliverBatch(orders);
        vm.expectRevert(); // confirm burned
        packs.ownerOf(packId);

        // Second submission of the SAME permit -> ownerOf reverts
        // OwnerQueryForNonexistentToken (ERC721A's own error).
        vm.prank(signerAddr);
        vm.expectRevert(IERC721A.OwnerQueryForNonexistentToken.selector);
        packs.deliverBatch(orders);
    }

    // ------------------------------------------------------------------
    // AC-6: the same permit twice within ONE batch also reverts.
    // ------------------------------------------------------------------

    /// @notice A single batch containing the same packId twice reverts
    ///         OwnerQueryForNonexistentToken: the first order burns the pack,
    ///         the second order's ownerOf reverts, and the whole atomic batch
    ///         rolls back (nothing minted).
    function testInBatchDuplicateReverts() public {
        uint256 packId = 1;
        uint256[4] memory cards = cardsForPack(packId);

        // Two orders sharing the same packId (identical permits).
        IManifoldPacks.RipOrder[] memory orders = new IManifoldPacks.RipOrder[](2);
        orders[0] = buildFixtureRipOrder(packId);
        orders[1] = buildFixtureRipOrder(packId);

        vm.prank(signerAddr);
        vm.expectRevert(IERC721A.OwnerQueryForNonexistentToken.selector);
        packs.deliverBatch(orders);

        // Atomic rollback: the pack still exists and no cards were minted.
        assertEq(packs.ownerOf(packId), owner, "pack survives rolled-back batch");
        for (uint256 i = 0; i < 4; i++) {
            assertEq(creator.balanceOf(owner, cards[i]), 0, "no cards minted on rollback");
        }
    }

    /// @notice Two DISTINCT packs rip fine in one batch — proving the revert
    ///         above is specifically the duplicate/burned-pack lock, not a
    ///         general multi-order failure.
    function testDistinctPacksInOneBatchSucceed() public {
        IManifoldPacks.RipOrder[] memory orders = new IManifoldPacks.RipOrder[](2);
        orders[0] = buildFixtureRipOrder(1);
        orders[1] = buildFixtureRipOrder(2);

        vm.prank(signerAddr);
        packs.deliverBatch(orders);

        vm.expectRevert();
        packs.ownerOf(1);
        vm.expectRevert();
        packs.ownerOf(2);
    }

    /// @notice Ripping a never-minted (nonexistent) pack reverts the same
    ///         ERC721A error — the same lock covers already-ripped and
    ///         never-existed packs uniformly.
    function testNonexistentPackReverts() public {
        // FIXTURE_PACK_COUNT packs exist (ids 1..10); id 9999 never minted.
        uint256 ghostPack = 9_999;
        uint256[4] memory cards = cardsForPack(1); // any in-range card ids

        IManifoldPacks.RipOrder memory order =
            buildRipOrder(OWNER_PK, ghostPack, cards, block.timestamp + 1 days);
        IManifoldPacks.RipOrder[] memory orders = new IManifoldPacks.RipOrder[](1);
        orders[0] = order;

        vm.prank(signerAddr);
        vm.expectRevert(IERC721A.OwnerQueryForNonexistentToken.selector);
        packs.deliverBatch(orders);
    }
}
