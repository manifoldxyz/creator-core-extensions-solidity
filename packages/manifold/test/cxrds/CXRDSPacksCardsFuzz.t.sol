// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {CXRDSPacks} from "../../contracts/cxrds/CXRDSPacks.sol";
import {ICXRDSPacks} from "../../contracts/cxrds/ICXRDSPacks.sol";

import {CXRDSTestBase} from "./CXRDSTestBase.t.sol";

/**
 * @title  CXRDSPacksCardsFuzz
 * @notice US-010 — initializeCards boundary + folder-URI + card-id/permit-domain
 *         fuzz tests (AC-8, AC-12 fuzz leg).
 *
 *         Covers:
 *           - initializeCards reserves 251 contiguous 0-supply ids exactly once;
 *             a second call reverts CardsAlreadyInitialized (NOT AlreadyInitialized).
 *           - Folder-URI resolves at both range boundaries: tokenURI(creator,
 *             start) -> location/1 and tokenURI(creator, start+250) -> location/251.
 *           - Card-id range fuzz: any id in [start, start+251) is accepted, any id
 *             outside reverts InvalidCardIds. Boundary fuzz pins start-1 and
 *             start+251 as reverts, start and start+250 as valid.
 *           - Permit-domain fuzz: only the owner's exact signature over the order's
 *             (packId, deadline) verifies; wrong signer or mismatched signed payload
 *             reverts InvalidPermit.
 */
contract CXRDSPacksCardsFuzz is CXRDSTestBase {
    string internal constant LOCATION = "ipfs://QmCardsFolder/";

    // ---------------------------------------------------------------------
    // AC-8: reservation semantics + double-init lock.
    // ---------------------------------------------------------------------

    function test_initializeReserves251ContiguousZeroSupplyIds() public {
        // 251 contiguous variation ids reserved; none minted (0 supply) yet.
        for (uint256 i = 0; i < NUM_CARD_DESIGNS; i++) {
            assertEq(
                creator.balanceOf(owner, startingCardTokenId + i),
                0,
                "reserved card starts at 0 supply"
            );
        }
    }

    function test_doubleInitRevertsCardsAlreadyInitialized() public {
        vm.prank(owner);
        vm.expectRevert(ICXRDSPacks.CardsAlreadyInitialized.selector);
        cxrds.initializeCards(defaultConfig());
    }

    // ---------------------------------------------------------------------
    // AC-8: folder-URI resolves at both range boundaries.
    // ---------------------------------------------------------------------

    function test_cardURIResolvesAtRangeBoundaries() public {
        ICXRDSPacks.PackConfig memory cfg = cxrds.getConfig();
        cfg.cardsLocation = LOCATION;
        vm.prank(owner);
        cxrds.updateConfig(cfg);

        // First reserved card -> location/1.
        assertEq(
            cxrds.tokenURI(address(creator), startingCardTokenId),
            string(abi.encodePacked(LOCATION, "1")),
            "first card URI"
        );

        // 251st reserved card (start+250) -> location/251.
        assertEq(
            cxrds.tokenURI(address(creator), startingCardTokenId + 250),
            string(abi.encodePacked(LOCATION, "251")),
            "last card URI"
        );
    }

    // ---------------------------------------------------------------------
    // AC-12 fuzz leg: card-id range acceptance.
    // Foundry snapshots after setUp and reverts between fuzz runs, so ripping
    // fixture pack 1 in each run is safe.
    // ---------------------------------------------------------------------

    function testFuzz_inRangeCardIdsAccepted(uint256 rawCardId) public {
        uint256 start = startingCardTokenId;
        uint256 cardId = bound(rawCardId, start, start + NUM_CARDS() - 1);

        uint256[4] memory cards = [cardId, cardId, cardId, cardId];
        ICXRDSPacks.RipOrder[] memory orders = new ICXRDSPacks.RipOrder[](1);
        orders[0] = buildRipOrder(OWNER_PK, 1, cards, block.timestamp + 1 days);

        vm.prank(signerAddr);
        cxrds.deliverBatch(orders);

        // Pack burned; four of the fuzzed card design minted to owner.
        vm.expectRevert();
        cxrds.ownerOf(1);
        assertEq(creator.balanceOf(owner, cardId), 4, "in-range cards minted");
    }

    function testFuzz_outOfRangeCardIdsRevert(uint256 rawCardId) public {
        uint256 start = startingCardTokenId;
        uint256 end = start + NUM_CARDS(); // first id past the valid range

        // Partition to strictly-out-of-range: below start OR at/after end.
        uint256 cardId;
        if (rawCardId % 2 == 0) {
            // Below start (start > 0 always after init).
            cardId = bound(rawCardId, 0, start - 1);
        } else {
            // At or past the end boundary.
            cardId = bound(rawCardId, end, type(uint256).max);
        }

        uint256[4] memory cards = [start, start, start, cardId];
        ICXRDSPacks.RipOrder[] memory orders = new ICXRDSPacks.RipOrder[](1);
        orders[0] = buildRipOrder(OWNER_PK, 1, cards, block.timestamp + 1 days);

        vm.prank(signerAddr);
        vm.expectRevert(ICXRDSPacks.InvalidCardIds.selector);
        cxrds.deliverBatch(orders);
    }

    // ---------------------------------------------------------------------
    // AC-8/AC-12: hard boundary assertions (start, start+250 valid;
    // start-1, start+251 revert).
    // ---------------------------------------------------------------------

    function test_boundaryStartAndLastValid() public {
        _ripSingleCard(1, startingCardTokenId);
        _ripSingleCard(2, startingCardTokenId + 250);
    }

    function test_boundaryStartMinusOneReverts() public {
        _expectInvalidCardIds(1, startingCardTokenId - 1);
    }

    function test_boundaryStartPlus251Reverts() public {
        _expectInvalidCardIds(1, startingCardTokenId + 251);
    }

    // ---------------------------------------------------------------------
    // AC-12 fuzz leg: permit domain — only the owner's exact signature over the
    // order's (packId, deadline) verifies.
    // ---------------------------------------------------------------------

    function testFuzz_wrongSignerRevertsPermitSignerNotOwner(uint256 rawPk) public {
        // Any well-formed key that is not the pack owner's.
        uint256 wrongPk = bound(rawPk, 1, type(uint128).max);
        vm.assume(wrongPk != OWNER_PK);

        ICXRDSPacks.RipOrder[] memory orders = new ICXRDSPacks.RipOrder[](1);
        orders[0] = buildRipOrder(wrongPk, 1, cardsForPack(1), block.timestamp + 1 days);

        vm.prank(signerAddr);
        vm.expectRevert(ICXRDSPacks.InvalidPermit.selector);
        cxrds.deliverBatch(orders);
    }

    function testFuzz_mismatchedSignedPayloadReverts(
        uint256 rawSignedDeadline,
        uint256 rawOrderDeadline
    ) public {
        // Owner signs over signedDeadline, but the order carries orderDeadline.
        // Both are far-future so PermitExpired is not what we trip; the digest
        // mismatch means the signature does not verify -> InvalidPermit.
        uint256 signedDeadline = bound(rawSignedDeadline, block.timestamp + 1, block.timestamp + 100 days);
        uint256 orderDeadline = bound(rawOrderDeadline, block.timestamp + 1, block.timestamp + 100 days);
        vm.assume(signedDeadline != orderDeadline);

        // Sign over signedDeadline, but assemble the order with orderDeadline.
        uint256[4] memory sheet = cardsForPack(1);
        (uint256[] memory ids, uint256[] memory amounts) = _fixtureArrays(sheet);
        ICXRDSPacks.RipOrder memory order = ICXRDSPacks.RipOrder({
            packId: 1,
            cardIds: ids,
            amounts: amounts,
            deadline: orderDeadline, // != signed deadline -> digest mismatch
            signature: signRipPermitBytes(OWNER_PK, 1, signedDeadline)
        });
        ICXRDSPacks.RipOrder[] memory orders = new ICXRDSPacks.RipOrder[](1);
        orders[0] = order;

        vm.prank(signerAddr);
        vm.expectRevert(ICXRDSPacks.InvalidPermit.selector);
        cxrds.deliverBatch(orders);
    }

    function testFuzz_mismatchedSignedPackIdReverts(uint256 rawSignedPackId) public {
        // Owner signs over a different packId than the order targets.
        uint256 signedPackId = bound(rawSignedPackId, 1, FIXTURE_PACK_COUNT);
        vm.assume(signedPackId != 1);
        uint256 deadline = block.timestamp + 1 days;

        uint256[4] memory sheet = cardsForPack(1);
        (uint256[] memory ids, uint256[] memory amounts) = _fixtureArrays(sheet);
        ICXRDSPacks.RipOrder memory order = ICXRDSPacks.RipOrder({
            packId: 1, // order targets pack 1, but sig covers signedPackId
            cardIds: ids,
            amounts: amounts,
            deadline: deadline,
            signature: signRipPermitBytes(OWNER_PK, signedPackId, deadline)
        });
        ICXRDSPacks.RipOrder[] memory orders = new ICXRDSPacks.RipOrder[](1);
        orders[0] = order;

        vm.prank(signerAddr);
        vm.expectRevert(ICXRDSPacks.InvalidPermit.selector);
        cxrds.deliverBatch(orders);
    }

    // ---------------------------------------------------------------------
    // Helpers.
    // ---------------------------------------------------------------------

    function NUM_CARDS() internal pure returns (uint256) {
        return NUM_CARD_DESIGNS;
    }

    function _ripSingleCard(uint256 packId, uint256 cardId) internal {
        uint256[4] memory cards = [cardId, cardId, cardId, cardId];
        ICXRDSPacks.RipOrder[] memory orders = new ICXRDSPacks.RipOrder[](1);
        orders[0] = buildRipOrder(OWNER_PK, packId, cards, block.timestamp + 1 days);

        vm.prank(signerAddr);
        cxrds.deliverBatch(orders);

        assertEq(creator.balanceOf(owner, cardId), 4, "boundary card minted");
    }

    function _expectInvalidCardIds(uint256 packId, uint256 cardId) internal {
        uint256[4] memory cards = [cardId, cardId, cardId, cardId];
        ICXRDSPacks.RipOrder[] memory orders = new ICXRDSPacks.RipOrder[](1);
        orders[0] = buildRipOrder(OWNER_PK, packId, cards, block.timestamp + 1 days);

        vm.prank(signerAddr);
        vm.expectRevert(ICXRDSPacks.InvalidCardIds.selector);
        cxrds.deliverBatch(orders);
    }
}
