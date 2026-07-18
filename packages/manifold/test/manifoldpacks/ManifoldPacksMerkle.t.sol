// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ManifoldPacksTestBase} from "./ManifoldPacksTestBase.t.sol";
import {IManifoldPacksSeaDropShim} from "../../contracts/manifoldpacks/IManifoldPacksSeaDropShim.sol";

/**
 * @title  ManifoldPacksMerkleTest
 * @notice Coverage for the Merkle contents-commitment ("delivery check") — the
 *         F1 fix. Each pack's exact contents are committed to a root; a
 *         compromised signer can only deliver a pack's committed cards or
 *         revert. These tests build a REAL murky tree with
 *         keccak256(abi.encode(packId, cardIds, amounts, salt)) leaves and prove
 *         real proofs verify against the deployed contract — a single-vs-double
 *         hash or sorted-pair mismatch between the off-chain tree and the
 *         on-chain OZ MerkleProof.verify would fail test_happyPath_realProof,
 *         so that test doubles as the anti-bricking hash-convention check.
 *
 *         Trust model under test (per Don, this session): the root binds the
 *         SIGNER, not the owner. The owner may re-seed at any time — verified in
 *         test_ownerCanReseedAfterMint — so there is NO _totalMinted()==0 lock.
 */
contract ManifoldPacksMerkleTest is ManifoldPacksTestBase {
    /// @notice Mirror of IManifoldPacksSeaDropShim.ContentsSeeded for expectEmit.
    event ContentsSeeded(bytes32 root);

    // ---------------------------------------------------------------------
    // 1. Happy path — a real proof for a committed pack rips (convention test).
    // ---------------------------------------------------------------------

    function test_happyPath_realProof() public {
        IManifoldPacksSeaDropShim.RipOrder[] memory orders = new IManifoldPacksSeaDropShim.RipOrder[](1);
        orders[0] = buildFixtureRipOrder(1);

        vm.prank(signerAddr);
        packs.deliverBatch(orders);

        // Pack burned; the 4 committed cards minted to owner.
        vm.expectRevert();
        packs.ownerOf(1);
        for (uint256 i = 0; i < 4; i++) {
            assertEq(creator.balanceOf(owner, startingCardTokenId + i), 1, "committed card minted");
        }
    }

    // ---------------------------------------------------------------------
    // 2. ContentsMismatch — substitute a different (still in-range, still
    //    summing) multiset that is NOT the pack's committed contents.
    // ---------------------------------------------------------------------

    function test_substituteContents_revertsContentsMismatch() public {
        // Pack 1 is committed to [start, start+1, start+2, start+3]. The signer
        // tries to deliver 4 copies of start+5 (in-range, sum == 4) with pack 1's
        // real proof — the leaf no longer matches.
        uint256[] memory ids = new uint256[](4);
        uint256[] memory amounts = new uint256[](4);
        for (uint256 i = 0; i < 4; i++) {
            ids[i] = startingCardTokenId + 5;
            amounts[i] = 1;
        }
        IManifoldPacksSeaDropShim.RipOrder memory order = IManifoldPacksSeaDropShim.RipOrder({
            packId: 1,
            cardIds: ids,
            amounts: amounts,
            deadline: block.timestamp + 1 days,
            signature: signRipPermitBytes(OWNER_PK, 1, block.timestamp + 1 days),
            salt: committedSalt[1],
            proof: _proofFor(1)
        });
        IManifoldPacksSeaDropShim.RipOrder[] memory orders = new IManifoldPacksSeaDropShim.RipOrder[](1);
        orders[0] = order;

        vm.prank(signerAddr);
        vm.expectRevert(IManifoldPacksSeaDropShim.ContentsMismatch.selector);
        packs.deliverBatch(orders);
    }

    // ---------------------------------------------------------------------
    // 3. Cross-pack swap (A5) — pack 2's committed cards+salt+proof submitted
    //    against packId = 1 (whose owner signed a valid permit).
    // ---------------------------------------------------------------------

    function test_crossPackSwap_revertsContentsMismatch() public {
        // Use pack 2's committed contents/salt/proof but target packId 1.
        (uint256[] memory ids, uint256[] memory amounts) = _fixtureArrays(fixtureCards[2]);
        IManifoldPacksSeaDropShim.RipOrder memory order = IManifoldPacksSeaDropShim.RipOrder({
            packId: 1,
            cardIds: ids,
            amounts: amounts,
            deadline: block.timestamp + 1 days,
            signature: signRipPermitBytes(OWNER_PK, 1, block.timestamp + 1 days),
            salt: committedSalt[2],
            proof: _proofFor(2)
        });
        IManifoldPacksSeaDropShim.RipOrder[] memory orders = new IManifoldPacksSeaDropShim.RipOrder[](1);
        orders[0] = order;

        // The leaf recomputes over packId=1 (the order field), so pack 2's proof
        // no longer verifies — packId is bound into the leaf.
        vm.prank(signerAddr);
        vm.expectRevert(IManifoldPacksSeaDropShim.ContentsMismatch.selector);
        packs.deliverBatch(orders);
    }

    // ---------------------------------------------------------------------
    // 4. Wrong salt — correct cards, wrong salt.
    // ---------------------------------------------------------------------

    function test_wrongSalt_revertsContentsMismatch() public {
        (uint256[] memory ids, uint256[] memory amounts) = _fixtureArrays(fixtureCards[1]);
        IManifoldPacksSeaDropShim.RipOrder memory order = IManifoldPacksSeaDropShim.RipOrder({
            packId: 1,
            cardIds: ids,
            amounts: amounts,
            deadline: block.timestamp + 1 days,
            signature: signRipPermitBytes(OWNER_PK, 1, block.timestamp + 1 days),
            salt: keccak256("not-the-committed-salt"),
            proof: _proofFor(1)
        });
        IManifoldPacksSeaDropShim.RipOrder[] memory orders = new IManifoldPacksSeaDropShim.RipOrder[](1);
        orders[0] = order;

        vm.prank(signerAddr);
        vm.expectRevert(IManifoldPacksSeaDropShim.ContentsMismatch.selector);
        packs.deliverBatch(orders);
    }

    // ---------------------------------------------------------------------
    // 5. Empty proof — a truncated/absent proof cannot verify.
    // ---------------------------------------------------------------------

    function test_emptyProof_revertsContentsMismatch() public {
        (uint256[] memory ids, uint256[] memory amounts) = _fixtureArrays(fixtureCards[1]);
        IManifoldPacksSeaDropShim.RipOrder memory order = IManifoldPacksSeaDropShim.RipOrder({
            packId: 1,
            cardIds: ids,
            amounts: amounts,
            deadline: block.timestamp + 1 days,
            signature: signRipPermitBytes(OWNER_PK, 1, block.timestamp + 1 days),
            salt: committedSalt[1],
            proof: new bytes32[](0)
        });
        IManifoldPacksSeaDropShim.RipOrder[] memory orders = new IManifoldPacksSeaDropShim.RipOrder[](1);
        orders[0] = order;

        vm.prank(signerAddr);
        vm.expectRevert(IManifoldPacksSeaDropShim.ContentsMismatch.selector);
        packs.deliverBatch(orders);
    }

    // ---------------------------------------------------------------------
    // 6. ContentsNotSeeded — deliverBatch before a root exists.
    // ---------------------------------------------------------------------

    function test_deliverBeforeSeed_revertsContentsNotSeeded() public {
        // Re-seed to zero to simulate the unseeded state (owner-mutable root).
        vm.prank(owner);
        packs.seedContents(bytes32(0));

        IManifoldPacksSeaDropShim.RipOrder[] memory orders = new IManifoldPacksSeaDropShim.RipOrder[](1);
        orders[0] = buildFixtureRipOrder(1);

        vm.prank(signerAddr);
        vm.expectRevert(IManifoldPacksSeaDropShim.ContentsNotSeeded.selector);
        packs.deliverBatch(orders);
    }

    // ---------------------------------------------------------------------
    // 7. seedContents before init reverts.
    // ---------------------------------------------------------------------

    function test_seedBeforeInit_revertsCardsNotInitialized() public {
        // A fresh, uninitialized pack contract.
        address[] memory allowed = new address[](1);
        allowed[0] = address(seaDropCaller);
        vm.startPrank(owner);
        ManifoldPacksSeaDropShimHarness fresh = new ManifoldPacksSeaDropShimHarness(allowed, owner);
        vm.expectRevert(IManifoldPacksSeaDropShim.CardsNotInitialized.selector);
        fresh.seedContents(keccak256("root"));
        vm.stopPrank();
    }

    // ---------------------------------------------------------------------
    // 8. Owner can re-seed at any time (the deliberate trust choice — NO
    //    _totalMinted()==0 lock). Fixture packs are already minted in setUp.
    // ---------------------------------------------------------------------

    function test_ownerCanReseedAfterMint() public {
        assertGt(packs.totalSupply(), 0, "packs already minted in setUp");
        bytes32 newRoot = keccak256("a-fresh-root");
        vm.prank(owner);
        packs.seedContents(newRoot);
        assertEq(packs.contentsRoot(), newRoot, "owner re-seeded after mint");
    }

    function test_seedContents_onlyOwner() public {
        vm.prank(collector);
        vm.expectRevert();
        packs.seedContents(keccak256("x"));
    }

    function test_seedContents_emitsEvent() public {
        bytes32 root = keccak256("emit-root");
        vm.expectEmit(false, false, false, true, address(packs));
        emit ContentsSeeded(root);
        vm.prank(owner);
        packs.seedContents(root);
    }

    // ---------------------------------------------------------------------
    // 9. Additivity — a merkle-valid order with an INVALID owner permit still
    //    reverts on the signature gate. Both gates are independent.
    // ---------------------------------------------------------------------

    function test_sigStillEnforced_withValidProof() public {
        // Valid contents + valid proof, but signed by the WRONG key.
        IManifoldPacksSeaDropShim.RipOrder memory order = buildRipOrder(
            COLLECTOR_PK, // not the pack owner
            1,
            fixtureCards[1],
            block.timestamp + 1 days
        );
        IManifoldPacksSeaDropShim.RipOrder[] memory orders = new IManifoldPacksSeaDropShim.RipOrder[](1);
        orders[0] = order;

        vm.prank(signerAddr);
        vm.expectRevert(IManifoldPacksSeaDropShim.InvalidPermit.selector);
        packs.deliverBatch(orders);
    }

    // ---------------------------------------------------------------------
    // 10. Re-seeding to new contents lets the SAME pack rip its NEW cards — the
    //     owner-mutable-root path end to end (mirrors a live sheet correction).
    // ---------------------------------------------------------------------

    function test_reseedNewContents_ripsNewCards() public {
        // Commit pack 1 to a NEW multiset (4 copies of start+10) and re-seed.
        uint256[] memory ids = new uint256[](4);
        uint256[] memory amounts = new uint256[](4);
        for (uint256 i = 0; i < 4; i++) {
            ids[i] = startingCardTokenId + 10;
            amounts[i] = 1;
        }
        _commitAndSeed(1, ids, amounts, keccak256("reseed-salt"));

        IManifoldPacksSeaDropShim.RipOrder memory order = IManifoldPacksSeaDropShim.RipOrder({
            packId: 1,
            cardIds: ids,
            amounts: amounts,
            deadline: block.timestamp + 1 days,
            signature: signRipPermitBytes(OWNER_PK, 1, block.timestamp + 1 days),
            salt: committedSalt[1],
            proof: _proofFor(1)
        });
        IManifoldPacksSeaDropShim.RipOrder[] memory orders = new IManifoldPacksSeaDropShim.RipOrder[](1);
        orders[0] = order;

        vm.prank(signerAddr);
        packs.deliverBatch(orders);

        assertEq(creator.balanceOf(owner, startingCardTokenId + 10), 4, "new committed cards minted");
    }
}

/**
 * @notice Minimal ctor wrapper so test 7 can deploy an uninitialized pack
 *         contract with a fixed name/symbol without repeating the constructor
 *         args inline.
 */
import {ManifoldPacksSeaDropShim} from "../../contracts/manifoldpacks/ManifoldPacksSeaDropShim.sol";

contract ManifoldPacksSeaDropShimHarness is ManifoldPacksSeaDropShim {
    constructor(address[] memory allowedSeaDrop_, address initialOwner_)
        ManifoldPacksSeaDropShim("Fresh", "FRESH", allowedSeaDrop_, initialOwner_)
    {}
}
