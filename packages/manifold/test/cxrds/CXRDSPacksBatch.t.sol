// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ERC1155Creator} from "@manifoldxyz/creator-core-solidity/contracts/ERC1155Creator.sol";

import {CXRDSPacks} from "../../contracts/cxrds/CXRDSPacks.sol";
import {ICXRDSPacks} from "../../contracts/cxrds/ICXRDSPacks.sol";

import {CXRDSTestBase} from "./CXRDSTestBase.t.sol";

/**
 * @title  CXRDSPacksBatch
 * @notice US-009 — Batch semantics + poisoned-batch integration tests run against
 *         the REAL stock ERC1155Creator provided by CXRDSTestBase (AC-7).
 *
 *         Covers:
 *           - N valid orders settle atomically in ONE deliverBatch tx: all packs
 *             burned, all 4N card balances land on the 1155, N Ripped events emit.
 *           - A poisoned batch (one bad order among many) reverts the WHOLE batch:
 *             after the revert NO pack is burned and NO card is minted (full
 *             rollback verified on the real creator core).
 *           - initializeCards without a prior registerExtension reverts (the cards
 *             core gates mintExtensionNew on registration).
 */
contract CXRDSPacksBatch is CXRDSTestBase {
    uint256 internal constant BATCH_N = 5;

    /// @dev Local mirror of ICXRDSPacks.Ripped for vm.expectEmit matching.
    event Ripped(uint256 indexed packId, address indexed owner, uint256[4] cardIds);

    // ---------------------------------------------------------------------
    // AC-7: N valid orders settle atomically in one tx.
    // ---------------------------------------------------------------------

    function test_batchAtomicSettlesAllOrders() public {
        // Sanity: before the batch, packs exist and no cards are minted.
        for (uint256 packId = 1; packId <= BATCH_N; packId++) {
            assertEq(cxrds.ownerOf(packId), owner, "pack owned pre-batch");
        }
        for (uint256 k = 0; k < 4; k++) {
            assertEq(
                creator.balanceOf(owner, startingCardTokenId + k),
                0,
                "card zero pre-batch"
            );
        }

        // Build N valid orders for fixture packs 1..N.
        ICXRDSPacks.RipOrder[] memory orders = new ICXRDSPacks.RipOrder[](BATCH_N);
        for (uint256 i = 0; i < BATCH_N; i++) {
            uint256 packId = i + 1;
            orders[i] = buildFixtureRipOrder(packId);
        }

        // Expect one Ripped event per order, in order.
        for (uint256 i = 0; i < BATCH_N; i++) {
            uint256 packId = i + 1;
            vm.expectEmit(true, true, false, true, address(cxrds));
            emit Ripped(packId, owner, cardsForPack(packId));
        }

        vm.prank(signerAddr);
        cxrds.deliverBatch(orders);

        // All N packs are burned -> ownerOf reverts (ERC721A replay lock).
        for (uint256 packId = 1; packId <= BATCH_N; packId++) {
            vm.expectRevert();
            cxrds.ownerOf(packId);
        }

        // All 4N card balances landed on the 1155. Every fixture pack mints
        // one of each of the four contiguous cards, so the owner accumulates
        // BATCH_N of each card design.
        for (uint256 k = 0; k < 4; k++) {
            assertEq(
                creator.balanceOf(owner, startingCardTokenId + k),
                BATCH_N,
                "card balance after batch"
            );
        }
    }

    // ---------------------------------------------------------------------
    // AC-7 + AC (rollback): a poisoned batch reverts the WHOLE batch and
    // leaves NO state change on the real creator core.
    // ---------------------------------------------------------------------

    function test_poisonedBatchOutOfRangeCardRevertsWhole() public {
        ICXRDSPacks.RipOrder[] memory orders = new ICXRDSPacks.RipOrder[](BATCH_N);
        for (uint256 i = 0; i < BATCH_N; i++) {
            orders[i] = buildFixtureRipOrder(i + 1);
        }

        // Poison the middle order: one card id just past the valid range.
        uint256 badPackId = 3;
        uint256[4] memory badCards = [
            startingCardTokenId,
            startingCardTokenId + 1,
            startingCardTokenId + 2,
            startingCardTokenId + NUM_CARD_DESIGNS() // out of range (>= start+251)
        ];
        orders[2] = buildRipOrder(OWNER_PK, badPackId, badCards, block.timestamp + 1 days);

        vm.prank(signerAddr);
        vm.expectRevert(ICXRDSPacks.InvalidCardIds.selector);
        cxrds.deliverBatch(orders);

        _assertNoStateChange();
    }

    function test_poisonedBatchExpiredDeadlineRevertsWhole() public {
        ICXRDSPacks.RipOrder[] memory orders = new ICXRDSPacks.RipOrder[](BATCH_N);
        for (uint256 i = 0; i < BATCH_N; i++) {
            orders[i] = buildFixtureRipOrder(i + 1);
        }

        // Poison the last order with an already-passed deadline.
        uint256 badPackId = 5;
        orders[4] = buildRipOrder(
            OWNER_PK,
            badPackId,
            cardsForPack(badPackId),
            block.timestamp - 1
        );

        vm.prank(signerAddr);
        vm.expectRevert(ICXRDSPacks.PermitExpired.selector);
        cxrds.deliverBatch(orders);

        _assertNoStateChange();
    }

    /// @dev After a reverted poisoned batch, no pack burned and no card minted.
    function _assertNoStateChange() internal {
        for (uint256 packId = 1; packId <= BATCH_N; packId++) {
            assertEq(cxrds.ownerOf(packId), owner, "pack NOT burned after revert");
        }
        for (uint256 k = 0; k < 4; k++) {
            assertEq(
                creator.balanceOf(owner, startingCardTokenId + k),
                0,
                "card NOT minted after revert"
            );
        }
    }

    // ---------------------------------------------------------------------
    // AC-8 (partial): initializeCards before registerExtension reverts on the
    // cards core's registration gate (mintExtensionNew requires registration).
    // ---------------------------------------------------------------------

    function test_initializeCardsWithoutRegisterExtensionReverts() public {
        vm.startPrank(owner);

        ERC1155Creator freshCreator = new ERC1155Creator("Fresh Cards", "FRESH");
        address[] memory allowedSeaDrop = new address[](1);
        allowedSeaDrop[0] = address(seaDropCaller);

        CXRDSPacks freshPacks = new CXRDSPacks(
            "Fresh Packs",
            "FPACK",
            allowedSeaDrop,
            address(freshCreator),
            owner
        );

        // NOTE: registerExtension deliberately NOT called. mintExtensionNew is
        // gated by requireExtension() on the cards core.
        vm.expectRevert(bytes("Must be registered extension"));
        freshPacks.initializeCards();

        vm.stopPrank();
    }

    /// @dev Local view mirror of the contract constant for readability.
    function NUM_CARD_DESIGNS() internal view returns (uint256) {
        return cxrds.NUM_CARD_DESIGNS();
    }
}
