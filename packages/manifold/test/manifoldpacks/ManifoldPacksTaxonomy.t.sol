// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ManifoldPacksTestBase} from "./ManifoldPacksTestBase.t.sol";
import {IManifoldPacksSeaDropShim} from "../../contracts/manifoldpacks/IManifoldPacksSeaDropShim.sol";

/**
 * @title  ManifoldPacksTaxonomy
 * @notice US-007 — Error-taxonomy unit tests (AC-5, AC-10): exactly one revert
 *         test per pinned error row.
 *
 *         PINNED taxonomy (binding gotcha e), post-SignatureChecker rework:
 *           - OnlySigner            : caller != configured signer.
 *           - RipNotStarted         : (covered in US-006).
 *           - PermitExpired         : block.timestamp > deadline.
 *           - InvalidPermit         : `SignatureChecker.isValidSignatureNow`
 *                                     rejects the permit against the current
 *                                     owner. This SINGLE error replaces the old
 *                                     `InvalidSignature` / `PermitSignerNotOwner`
 *                                     split — malformed, forged-nonzero,
 *                                     non-owner, and stale-after-transfer permits
 *                                     ALL collapse to this one error now.
 *           - InvalidCardAmounts    : mismatched/empty cardIds+amounts, or
 *                                     sum(amounts) != cardsPerPack (the real
 *                                     runtime "wrong count" guard).
 *           - InvalidCardIds        : a card id outside
 *                                     [start, start+NUM_CARD_DESIGNS).
 *           - CardsAlreadyInitialized : a second initializeCards() call.
 *
 *         SignatureChecker now supports EIP-1271 contract wallets — the old
 *         "Safe holders can't rip" v1 non-goal is REMOVED (see the dedicated
 *         EIP-1271 rip test in ManifoldPacksSignature.t.sol).
 */
contract ManifoldPacksTaxonomy is ManifoldPacksTestBase {
    // An arbitrary key that is neither owner, collector, nor signer — used to
    // forge a well-formed signature that recovers to a wrong, nonzero address.
    uint256 internal constant FORGER_PK = 0xF0F0;

    // Helper: submit a single-order batch as the configured signer.
    function _deliver(IManifoldPacksSeaDropShim.RipOrder memory order) internal {
        IManifoldPacksSeaDropShim.RipOrder[] memory orders = new IManifoldPacksSeaDropShim.RipOrder[](1);
        orders[0] = order;
        vm.prank(signerAddr);
        packs.deliverBatch(orders);
    }

    // ------------------------------------------------------------------
    // OnlySigner: caller is not the configured signer.
    // ------------------------------------------------------------------

    function testOnlySigner() public {
        IManifoldPacksSeaDropShim.RipOrder[] memory orders = new IManifoldPacksSeaDropShim.RipOrder[](1);
        orders[0] = buildFixtureRipOrder(1);

        // Called by owner (not the signer) -> OnlySigner.
        vm.prank(owner);
        vm.expectRevert(IManifoldPacksSeaDropShim.OnlySigner.selector);
        packs.deliverBatch(orders);
    }

    // ------------------------------------------------------------------
    // PermitExpired: block.timestamp > deadline.
    // ------------------------------------------------------------------

    function testPermitExpired() public {
        // Owner signs, but with a deadline already in the past.
        uint256 pastDeadline = block.timestamp - 1;
        IManifoldPacksSeaDropShim.RipOrder memory order =
            buildRipOrder(OWNER_PK, 1, cardsForPack(1), pastDeadline);

        vm.prank(signerAddr);
        IManifoldPacksSeaDropShim.RipOrder[] memory orders = new IManifoldPacksSeaDropShim.RipOrder[](1);
        orders[0] = order;
        vm.expectRevert(IManifoldPacksSeaDropShim.PermitExpired.selector);
        packs.deliverBatch(orders);
    }

    // ------------------------------------------------------------------
    // InvalidPermit x4 sub-cases — all assert the SAME error now, because
    // SignatureChecker.isValidSignatureNow returns ONE bool.
    // ------------------------------------------------------------------

    /// @notice (1) A structurally-malformed signature (garbage bytes) that
    ///         ECDSA cannot recover -> isValidSignatureNow false -> InvalidPermit.
    function testInvalidPermitMalformed() public {
        // Start from a valid owner permit, then replace the signature with a
        // 65-byte garbage blob (v out of range) that recovers to nothing.
        IManifoldPacksSeaDropShim.RipOrder memory order =
            buildRipOrder(OWNER_PK, 1, cardsForPack(1), block.timestamp + 1 days);
        order.signature = new bytes(65); // all-zero -> ECDSA InvalidSignature/no recovery.

        IManifoldPacksSeaDropShim.RipOrder[] memory orders = new IManifoldPacksSeaDropShim.RipOrder[](1);
        orders[0] = order;
        vm.prank(signerAddr);
        vm.expectRevert(IManifoldPacksSeaDropShim.InvalidPermit.selector);
        packs.deliverBatch(orders);
    }

    /// @notice (2) Forged-but-well-formed signature that recovers to an
    ///         arbitrary nonzero address (the forger key) which is not the pack
    ///         owner.
    function testInvalidPermit_forgedWellFormed() public {
        IManifoldPacksSeaDropShim.RipOrder memory order =
            buildRipOrder(FORGER_PK, 1, cardsForPack(1), block.timestamp + 1 days);

        IManifoldPacksSeaDropShim.RipOrder[] memory orders = new IManifoldPacksSeaDropShim.RipOrder[](1);
        orders[0] = order;
        vm.prank(signerAddr);
        vm.expectRevert(IManifoldPacksSeaDropShim.InvalidPermit.selector);
        packs.deliverBatch(orders);
    }

    /// @notice (3) A permit signed by a known non-owner (collector) for a pack
    ///         owned by someone else.
    function testInvalidPermit_nonOwner() public {
        // Pack 1 is owned by owner; collector signs a permit for it.
        IManifoldPacksSeaDropShim.RipOrder memory order =
            buildRipOrder(COLLECTOR_PK, 1, cardsForPack(1), block.timestamp + 1 days);

        IManifoldPacksSeaDropShim.RipOrder[] memory orders = new IManifoldPacksSeaDropShim.RipOrder[](1);
        orders[0] = order;
        vm.prank(signerAddr);
        vm.expectRevert(IManifoldPacksSeaDropShim.InvalidPermit.selector);
        packs.deliverBatch(orders);
    }

    /// @notice (4) A stale permit: owner signs, then transfers the pack away.
    ///         The recovered signer (owner) is no longer the current owner.
    function testInvalidPermit_staleAfterTransfer() public {
        uint256 packId = 1;
        // Owner signs a valid permit while still holding the pack.
        IManifoldPacksSeaDropShim.RipOrder memory order =
            buildRipOrder(OWNER_PK, packId, cardsForPack(packId), block.timestamp + 1 days);

        // Then transfers the pack to collector, staling the signature.
        vm.prank(owner);
        packs.transferFrom(owner, collector, packId);

        IManifoldPacksSeaDropShim.RipOrder[] memory orders = new IManifoldPacksSeaDropShim.RipOrder[](1);
        orders[0] = order;
        vm.prank(signerAddr);
        vm.expectRevert(IManifoldPacksSeaDropShim.InvalidPermit.selector);
        packs.deliverBatch(orders);
    }

    // ------------------------------------------------------------------
    // InvalidCardAmounts: sum(amounts) != cardsPerPack (the real "wrong count"
    // guard the old fixed uint256[4] array made impossible), and mismatched /
    // empty lengths.
    // ------------------------------------------------------------------

    function testInvalidCardAmountsWrongSum() public {
        uint256 packId = 1;
        // Well-formed owner permit, in-range ids, but amounts sum to 3 != 4.
        uint256[] memory ids = new uint256[](4);
        uint256[] memory amounts = new uint256[](4);
        for (uint256 i = 0; i < 4; i++) {
            ids[i] = startingCardTokenId + i;
            amounts[i] = 1;
        }
        amounts[3] = 0; // sum == 3, not cardsPerPack (4).

        IManifoldPacksSeaDropShim.RipOrder memory order =
            buildRipOrderDyn(OWNER_PK, packId, ids, amounts, block.timestamp + 1 days);

        IManifoldPacksSeaDropShim.RipOrder[] memory orders = new IManifoldPacksSeaDropShim.RipOrder[](1);
        orders[0] = order;
        vm.prank(signerAddr);
        vm.expectRevert(IManifoldPacksSeaDropShim.InvalidCardAmounts.selector);
        packs.deliverBatch(orders);
    }

    function testInvalidCardAmountsMismatchedLengths() public {
        uint256 packId = 1;
        // cardIds length 4, amounts length 3 -> mismatched.
        uint256[] memory ids = new uint256[](4);
        uint256[] memory amounts = new uint256[](3);
        for (uint256 i = 0; i < 4; i++) {
            ids[i] = startingCardTokenId + i;
        }
        for (uint256 i = 0; i < 3; i++) {
            amounts[i] = 1;
        }

        IManifoldPacksSeaDropShim.RipOrder memory order =
            buildRipOrderDyn(OWNER_PK, packId, ids, amounts, block.timestamp + 1 days);

        IManifoldPacksSeaDropShim.RipOrder[] memory orders = new IManifoldPacksSeaDropShim.RipOrder[](1);
        orders[0] = order;
        vm.prank(signerAddr);
        vm.expectRevert(IManifoldPacksSeaDropShim.InvalidCardAmounts.selector);
        packs.deliverBatch(orders);
    }

    function testInvalidCardAmountsEmpty() public {
        uint256 packId = 1;
        // Empty cardIds/amounts -> length 0 -> InvalidCardAmounts.
        uint256[] memory ids = new uint256[](0);
        uint256[] memory amounts = new uint256[](0);

        IManifoldPacksSeaDropShim.RipOrder memory order =
            buildRipOrderDyn(OWNER_PK, packId, ids, amounts, block.timestamp + 1 days);

        IManifoldPacksSeaDropShim.RipOrder[] memory orders = new IManifoldPacksSeaDropShim.RipOrder[](1);
        orders[0] = order;
        vm.prank(signerAddr);
        vm.expectRevert(IManifoldPacksSeaDropShim.InvalidCardAmounts.selector);
        packs.deliverBatch(orders);
    }

    // ------------------------------------------------------------------
    // InvalidCardIds: a card id out of the reserved variation range.
    // ------------------------------------------------------------------

    function testInvalidCardIdsOutOfRange() public {
        uint256 packId = 1;
        // Well-formed owner permit (so verification passes to the card check),
        // but the first card id is >= start + NUM_CARD_DESIGNS (out of range).
        uint256[4] memory badCards = [
            startingCardTokenId,
            startingCardTokenId + 1,
            startingCardTokenId + 2,
            startingCardTokenId + NUM_CARD_DESIGNS // out of range
        ];
        IManifoldPacksSeaDropShim.RipOrder memory order =
            buildRipOrder(OWNER_PK, packId, badCards, block.timestamp + 1 days);

        IManifoldPacksSeaDropShim.RipOrder[] memory orders = new IManifoldPacksSeaDropShim.RipOrder[](1);
        orders[0] = order;
        vm.prank(signerAddr);
        vm.expectRevert(IManifoldPacksSeaDropShim.InvalidCardIds.selector);
        packs.deliverBatch(orders);
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
        IManifoldPacksSeaDropShim.RipOrder memory order =
            buildRipOrder(OWNER_PK, packId, badCards, block.timestamp + 1 days);

        IManifoldPacksSeaDropShim.RipOrder[] memory orders = new IManifoldPacksSeaDropShim.RipOrder[](1);
        orders[0] = order;
        vm.prank(signerAddr);
        vm.expectRevert(IManifoldPacksSeaDropShim.InvalidCardIds.selector);
        packs.deliverBatch(orders);
    }

    // ------------------------------------------------------------------
    // CardsAlreadyInitialized: a second initializeCards() call.
    // ------------------------------------------------------------------

    function testCardsAlreadyInitialized() public {
        vm.prank(owner);
        vm.expectRevert(IManifoldPacksSeaDropShim.CardsAlreadyInitialized.selector);
        packs.initializeCards(address(creator), defaultConfig());
    }

    // ------------------------------------------------------------------
    // AC-10: a compromised signer key ALONE (no valid owner permits) rips
    //        nothing while signatures are required — any order without a valid
    //        owner signature reverts InvalidPermit.
    // ------------------------------------------------------------------

    function testCompromisedSignerAloneRipsNothing() public {
        uint256 packId = 1;
        // The (compromised) signer forges a permit with its OWN key. It is
        // well-formed but recovers to the signer, not the pack owner ->
        // InvalidPermit. The pack is NOT burned.
        IManifoldPacksSeaDropShim.RipOrder memory order =
            buildRipOrder(SIGNER_PK, packId, cardsForPack(packId), block.timestamp + 1 days);

        IManifoldPacksSeaDropShim.RipOrder[] memory orders = new IManifoldPacksSeaDropShim.RipOrder[](1);
        orders[0] = order;
        vm.prank(signerAddr);
        vm.expectRevert(IManifoldPacksSeaDropShim.InvalidPermit.selector);
        packs.deliverBatch(orders);

        // Pack still exists and is still owned by owner — nothing was ripped.
        assertEq(packs.ownerOf(packId), owner, "pack untouched by compromised signer");
    }
}
