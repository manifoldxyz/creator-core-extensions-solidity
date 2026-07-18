// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ManifoldPacksTestBase} from "./ManifoldPacksTestBase.t.sol";
import {IManifoldPacksSeaDropShim} from "../../contracts/manifoldpacks/IManifoldPacksSeaDropShim.sol";

/**
 * @title  ManifoldPacksRip
 * @notice US-006 — Permit + happy-path rip unit tests (AC-3, AC-4).
 *
 *         Proves the rip-phase gate (RipNotStarted before ripStart), the
 *         gasless happy path (owner-signed permit -> pack burned + exactly four
 *         cards minted to the owner on the 1155, Ripped emitted, collector ETH
 *         untouched), and the secondary-buyer path (pack transferred, NEW owner
 *         signs, rip succeeds to the new owner).
 */
contract ManifoldPacksRip is ManifoldPacksTestBase {
    // Re-declared here so vm.expectEmit can reference the event shape.
    event Ripped(
        uint256 indexed packId,
        address indexed owner,
        uint256[] cardIds,
        uint256[] amounts,
        bool signatureVerified
    );

    // ------------------------------------------------------------------
    // AC-3: rip-phase gate.
    // ------------------------------------------------------------------

    /// @notice Before ripStart, deliverBatch reverts RipNotStarted; after it,
    ///         the same order succeeds.
    function testRipBeforeStartReverts() public {
        // Close the rip phase: move ripStart into the future (via updateConfig).
        _setRipStart(block.timestamp + 1 days);

        // Deadline is comfortably beyond the ripStart warp below so the permit
        // stays valid once the phase opens.
        IManifoldPacksSeaDropShim.RipOrder[] memory orders = new IManifoldPacksSeaDropShim.RipOrder[](1);
        orders[0] = buildRipOrder(OWNER_PK, 1, cardsForPack(1), block.timestamp + 30 days);

        vm.prank(signerAddr);
        vm.expectRevert(IManifoldPacksSeaDropShim.RipNotStarted.selector);
        packs.deliverBatch(orders);

        // Warp past ripStart -> the same order now succeeds.
        vm.warp(block.timestamp + 2 days);
        vm.prank(signerAddr);
        packs.deliverBatch(orders);
        vm.expectRevert(); // pack burned
        packs.ownerOf(1);
    }

    // ------------------------------------------------------------------
    // AC-4: gasless happy-path rip.
    // ------------------------------------------------------------------

    /// @notice A valid owner-signed order submitted by the signer burns the
    ///         pack, mints exactly the four supplied cards to the owner on the
    ///         1155 (+1 each), emits Ripped, and leaves the collector's ETH
    ///         balance untouched (zero-gas path — the signer pays).
    function testHappyPathRip() public {
        uint256 packId = 1;
        uint256[4] memory cards = cardsForPack(packId);

        // Card balances start at zero.
        for (uint256 i = 0; i < 4; i++) {
            assertEq(creator.balanceOf(owner, cards[i]), 0, "card balance pre-rip");
        }

        // The pack owner spends no ETH (collector/owner here is the pack holder).
        uint256 ownerEthBefore = owner.balance;

        IManifoldPacksSeaDropShim.RipOrder[] memory orders = new IManifoldPacksSeaDropShim.RipOrder[](1);
        orders[0] = buildFixtureRipOrder(packId);

        (uint256[] memory ids, uint256[] memory amounts) = _fixtureArrays(cards);
        vm.expectEmit(true, true, false, true, address(packs));
        emit Ripped(packId, owner, ids, amounts, true);

        vm.prank(signerAddr);
        packs.deliverBatch(orders);

        // Pack burned: ownerOf reverts.
        vm.expectRevert();
        packs.ownerOf(packId);

        // Exactly four cards minted, +1 each, to the pack owner.
        for (uint256 i = 0; i < 4; i++) {
            assertEq(creator.balanceOf(owner, cards[i]), 1, "card minted +1");
        }

        // Owner (the collector in this path) spent no ETH.
        assertEq(owner.balance, ownerEthBefore, "pack owner ETH untouched");
    }

    /// @notice A distinct four-card assertion using a second fixture pack:
    ///         the four ids are all inside the reserved variation range.
    function testRipMintsFourInRangeCards() public {
        uint256 packId = 2;
        uint256[4] memory cards = cardsForPack(packId);

        IManifoldPacksSeaDropShim.RipOrder[] memory orders = new IManifoldPacksSeaDropShim.RipOrder[](1);
        orders[0] = buildFixtureRipOrder(packId);

        vm.prank(signerAddr);
        packs.deliverBatch(orders);

        for (uint256 i = 0; i < 4; i++) {
            assertGe(cards[i], startingCardTokenId, "card >= start");
            assertLt(cards[i], startingCardTokenId + NUM_CARD_DESIGNS, "card < start+251");
            assertEq(creator.balanceOf(owner, cards[i]), 1, "card minted");
        }
    }

    // ------------------------------------------------------------------
    // AC-4 secondary-buyer happy path.
    // ------------------------------------------------------------------

    /// @notice After a sealed transfer to a second wallet, the NEW owner's
    ///         signed permit rips the pack to the NEW owner (cards land with
    ///         the new owner, not the original minter).
    function testSecondaryOwnerRip() public {
        uint256 packId = 3;
        uint256[4] memory cards = cardsForPack(packId);

        // Sealed transfer: owner -> collector (collector is a keyed wallet so
        // it can sign its own permit). Trading is paused by default, so open it
        // first (this test exercises the rip flow, not the pause).
        vm.prank(owner);
        packs.updateTransfersPaused(false);
        vm.prank(owner);
        packs.transferFrom(owner, collector, packId);
        assertEq(packs.ownerOf(packId), collector, "pack transferred to collector");

        // New owner signs its own permit.
        IManifoldPacksSeaDropShim.RipOrder[] memory orders = new IManifoldPacksSeaDropShim.RipOrder[](1);
        orders[0] = buildRipOrder(COLLECTOR_PK, packId, cards, block.timestamp + 1 days);

        (uint256[] memory ids, uint256[] memory amounts) = _fixtureArrays(cards);
        vm.expectEmit(true, true, false, true, address(packs));
        emit Ripped(packId, collector, ids, amounts, true);

        vm.prank(signerAddr);
        packs.deliverBatch(orders);

        // Pack burned; cards land with the NEW owner, not the original minter.
        vm.expectRevert();
        packs.ownerOf(packId);
        for (uint256 i = 0; i < 4; i++) {
            assertEq(creator.balanceOf(collector, cards[i]), 1, "card -> new owner");
            assertEq(creator.balanceOf(owner, cards[i]), 0, "original minter got nothing");
        }
    }
}
