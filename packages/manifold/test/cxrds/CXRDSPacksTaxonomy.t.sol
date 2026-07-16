// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {CXRDSTestBase} from "./CXRDSTestBase.t.sol";
import {ICXRDSPacks} from "../../contracts/cxrds/ICXRDSPacks.sol";

/**
 * @title  CXRDSPacksTaxonomy
 * @notice US-007 — Error-taxonomy unit tests (AC-5, AC-10): exactly one revert
 *         test per pinned error row.
 *
 *         PINNED taxonomy (binding gotcha e):
 *           - OnlySigner            : caller != configured signer.
 *           - RipNotStarted         : (covered in US-006).
 *           - PermitExpired         : block.timestamp > deadline.
 *           - InvalidSignature      : ONLY ecrecover -> address(0) (malformed
 *                                     v/r/s). Constructed here with v = 0.
 *           - PermitSignerNotOwner  : every well-formed-but-wrong-signer case —
 *                                     forged-nonzero, non-owner, and
 *                                     stale-after-transfer ALL assert this one
 *                                     mechanical error.
 *           - InvalidCardIds        : a card id outside
 *                                     [start, start+NUM_CARD_DESIGNS). Range
 *                                     only — card COUNT is uint256[4] compile-
 *                                     time enforced, so NO test attempts a
 *                                     3/5-id order (uncompilable by design).
 *           - CardsAlreadyInitialized : a second initializeCards() call.
 *
 *         v1 NON-GOAL (critic r2 A-1, accepted): EIP-1271 / Safe-held packs
 *         cannot rip because verification is ecrecover-only. No test here
 *         attempts to fix that.
 */
contract CXRDSPacksTaxonomy is CXRDSTestBase {
    // An arbitrary key that is neither owner, collector, nor signer — used to
    // forge a well-formed signature that recovers to a wrong, nonzero address.
    uint256 internal constant FORGER_PK = 0xF0F0;

    // Helper: submit a single-order batch as the configured signer.
    function _deliver(ICXRDSPacks.RipOrder memory order) internal {
        ICXRDSPacks.RipOrder[] memory orders = new ICXRDSPacks.RipOrder[](1);
        orders[0] = order;
        vm.prank(signerAddr);
        cxrds.deliverBatch(orders);
    }

    // ------------------------------------------------------------------
    // OnlySigner: caller is not the configured signer.
    // ------------------------------------------------------------------

    function testOnlySigner() public {
        ICXRDSPacks.RipOrder[] memory orders = new ICXRDSPacks.RipOrder[](1);
        orders[0] = buildFixtureRipOrder(1);

        // Called by owner (not the signer) -> OnlySigner.
        vm.prank(owner);
        vm.expectRevert(ICXRDSPacks.OnlySigner.selector);
        cxrds.deliverBatch(orders);
    }

    // ------------------------------------------------------------------
    // PermitExpired: block.timestamp > deadline.
    // ------------------------------------------------------------------

    function testPermitExpired() public {
        // Owner signs, but with a deadline already in the past.
        uint256 pastDeadline = block.timestamp - 1;
        ICXRDSPacks.RipOrder memory order =
            buildRipOrder(OWNER_PK, 1, cardsForPack(1), pastDeadline);

        vm.prank(signerAddr);
        ICXRDSPacks.RipOrder[] memory orders = new ICXRDSPacks.RipOrder[](1);
        orders[0] = order;
        vm.expectRevert(ICXRDSPacks.PermitExpired.selector);
        cxrds.deliverBatch(orders);
    }

    // ------------------------------------------------------------------
    // InvalidSignature: ecrecover -> address(0) (malformed sig, v = 0).
    // ------------------------------------------------------------------

    function testInvalidSignatureMalformed() public {
        // Start from a valid owner permit, then corrupt v to 0 so ecrecover
        // returns address(0) — the ONLY case that hits InvalidSignature.
        ICXRDSPacks.RipOrder memory order =
            buildRipOrder(OWNER_PK, 1, cardsForPack(1), block.timestamp + 1 days);
        order.v = 0; // out-of-range recovery id -> ecrecover returns 0.

        ICXRDSPacks.RipOrder[] memory orders = new ICXRDSPacks.RipOrder[](1);
        orders[0] = order;
        vm.prank(signerAddr);
        vm.expectRevert(ICXRDSPacks.InvalidSignature.selector);
        cxrds.deliverBatch(orders);
    }

    // ------------------------------------------------------------------
    // PermitSignerNotOwner x3 sub-cases — all assert the SAME error.
    // ------------------------------------------------------------------

    /// @notice (1) Forged-but-well-formed signature that recovers to an
    ///         arbitrary nonzero address (the forger key) which is not the pack
    ///         owner.
    function testPermitSignerNotOwner_forgedWellFormed() public {
        ICXRDSPacks.RipOrder memory order =
            buildRipOrder(FORGER_PK, 1, cardsForPack(1), block.timestamp + 1 days);

        ICXRDSPacks.RipOrder[] memory orders = new ICXRDSPacks.RipOrder[](1);
        orders[0] = order;
        vm.prank(signerAddr);
        vm.expectRevert(ICXRDSPacks.PermitSignerNotOwner.selector);
        cxrds.deliverBatch(orders);
    }

    /// @notice (2) A permit signed by a known non-owner (collector) for a pack
    ///         owned by someone else.
    function testPermitSignerNotOwner_nonOwner() public {
        // Pack 1 is owned by owner; collector signs a permit for it.
        ICXRDSPacks.RipOrder memory order =
            buildRipOrder(COLLECTOR_PK, 1, cardsForPack(1), block.timestamp + 1 days);

        ICXRDSPacks.RipOrder[] memory orders = new ICXRDSPacks.RipOrder[](1);
        orders[0] = order;
        vm.prank(signerAddr);
        vm.expectRevert(ICXRDSPacks.PermitSignerNotOwner.selector);
        cxrds.deliverBatch(orders);
    }

    /// @notice (3) A stale permit: owner signs, then transfers the pack away.
    ///         The recovered signer (owner) is no longer the current owner.
    function testPermitSignerNotOwner_staleAfterTransfer() public {
        uint256 packId = 1;
        // Owner signs a valid permit while still holding the pack.
        ICXRDSPacks.RipOrder memory order =
            buildRipOrder(OWNER_PK, packId, cardsForPack(packId), block.timestamp + 1 days);

        // Then transfers the pack to collector, staling the signature.
        vm.prank(owner);
        cxrds.transferFrom(owner, collector, packId);

        ICXRDSPacks.RipOrder[] memory orders = new ICXRDSPacks.RipOrder[](1);
        orders[0] = order;
        vm.prank(signerAddr);
        vm.expectRevert(ICXRDSPacks.PermitSignerNotOwner.selector);
        cxrds.deliverBatch(orders);
    }

    // ------------------------------------------------------------------
    // InvalidCardIds: a card id out of the reserved variation range.
    //   Range-only — card COUNT is uint256[4] compile-time enforced, so there
    //   is NO 3/5-id order test (uncompilable by design).
    // ------------------------------------------------------------------

    function testInvalidCardIdsOutOfRange() public {
        uint256 packId = 1;
        // Well-formed owner permit (so verification passes to the card check),
        // but the first card id is >= start + NUM_CARD_DESIGNS (out of range).
        uint256[4] memory badCards = [
            startingCardTokenId,
            startingCardTokenId + 1,
            startingCardTokenId + 2,
            startingCardTokenId + cxrds.NUM_CARD_DESIGNS() // out of range
        ];
        ICXRDSPacks.RipOrder memory order =
            buildRipOrder(OWNER_PK, packId, badCards, block.timestamp + 1 days);

        ICXRDSPacks.RipOrder[] memory orders = new ICXRDSPacks.RipOrder[](1);
        orders[0] = order;
        vm.prank(signerAddr);
        vm.expectRevert(ICXRDSPacks.InvalidCardIds.selector);
        cxrds.deliverBatch(orders);
    }

    /// @notice A card id below the reserved range (e.g. 0, or start-1) also
    ///         reverts InvalidCardIds.
    function testInvalidCardIdsBelowRange() public {
        uint256 packId = 1;
        uint256[4] memory badCards = [
            uint256(0), // below start
            startingCardTokenId + 1,
            startingCardTokenId + 2,
            startingCardTokenId + 3
        ];
        ICXRDSPacks.RipOrder memory order =
            buildRipOrder(OWNER_PK, packId, badCards, block.timestamp + 1 days);

        ICXRDSPacks.RipOrder[] memory orders = new ICXRDSPacks.RipOrder[](1);
        orders[0] = order;
        vm.prank(signerAddr);
        vm.expectRevert(ICXRDSPacks.InvalidCardIds.selector);
        cxrds.deliverBatch(orders);
    }

    // ------------------------------------------------------------------
    // CardsAlreadyInitialized: a second initializeCards() call.
    // ------------------------------------------------------------------

    function testCardsAlreadyInitialized() public {
        vm.prank(owner);
        vm.expectRevert(ICXRDSPacks.CardsAlreadyInitialized.selector);
        cxrds.initializeCards();
    }

    // ------------------------------------------------------------------
    // AC-10: a compromised signer key ALONE (no valid owner permits) rips
    //        nothing — any order without a valid owner signature reverts.
    // ------------------------------------------------------------------

    function testCompromisedSignerAloneRipsNothing() public {
        uint256 packId = 1;
        // The (compromised) signer forges a permit with its OWN key. It is
        // well-formed but recovers to the signer, not the pack owner ->
        // PermitSignerNotOwner. The pack is NOT burned.
        ICXRDSPacks.RipOrder memory order =
            buildRipOrder(SIGNER_PK, packId, cardsForPack(packId), block.timestamp + 1 days);

        ICXRDSPacks.RipOrder[] memory orders = new ICXRDSPacks.RipOrder[](1);
        orders[0] = order;
        vm.prank(signerAddr);
        vm.expectRevert(ICXRDSPacks.PermitSignerNotOwner.selector);
        cxrds.deliverBatch(orders);

        // Pack still exists and is still owned by owner — nothing was ripped.
        assertEq(cxrds.ownerOf(packId), owner, "pack untouched by compromised signer");
    }
}
