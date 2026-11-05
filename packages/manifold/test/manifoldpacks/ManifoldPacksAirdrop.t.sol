// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ManifoldPacksTestBase} from "./ManifoldPacksTestBase.t.sol";
import {ManifoldPacksSeaDropShim} from "../../contracts/manifoldpacks/ManifoldPacksSeaDropShim.sol";
import {IManifoldPacksSeaDropShim} from "../../contracts/manifoldpacks/IManifoldPacksSeaDropShim.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

/**
 * @title  ManifoldPacksAirdrop
 * @notice Tests for the owner airdrop escape hatch: mint reserved card
 *         variations directly to recipients, bypassing the pack-burn rip flow.
 *         Verifies access control, array validation, range checks, rip-window
 *         independence, and that airdrops COUNT toward the minted total
 *         (`mintedCards`), auto-raising `maxCardsSupply` when needed — lazy-claim
 *         parity, so `maxCardsSupply` is a true total-supply cap (rips + airdrops).
 */
contract ManifoldPacksAirdrop is ManifoldPacksTestBase {
    // Re-declared here so vm.expectEmit can reference the event shape.
    event Airdropped(address[] recipients, uint256[] cardIds, uint256[] amounts);

    address internal alice = address(0xA11);
    address internal bob = address(0xB0B);

    function _single(address to, uint256 cardId, uint256 amount)
        internal
        pure
        returns (address[] memory tos, uint256[] memory ids, uint256[] memory amts)
    {
        tos = new address[](1);
        ids = new uint256[](1);
        amts = new uint256[](1);
        tos[0] = to;
        ids[0] = cardId;
        amts[0] = amount;
    }

    function test_ownerAirdropsSingleCard() public {
        (address[] memory tos, uint256[] memory ids, uint256[] memory amts) =
            _single(alice, startingCardTokenId, 3);

        vm.prank(owner);
        packs.airdrop(tos, ids, amts);

        assertEq(IERC1155(address(creator)).balanceOf(alice, startingCardTokenId), 3, "alice got 3 cards");
    }

    function test_ownerAirdropsParallelArraysToManyRecipients() public {
        address[] memory tos = new address[](3);
        uint256[] memory ids = new uint256[](3);
        uint256[] memory amts = new uint256[](3);
        tos[0] = alice; ids[0] = startingCardTokenId;     amts[0] = 1;
        tos[1] = bob;   ids[1] = startingCardTokenId + 1; amts[1] = 2;
        tos[2] = alice; ids[2] = startingCardTokenId + 2; amts[2] = 5;

        vm.prank(owner);
        packs.airdrop(tos, ids, amts);

        assertEq(IERC1155(address(creator)).balanceOf(alice, startingCardTokenId), 1, "alice card0");
        assertEq(IERC1155(address(creator)).balanceOf(bob, startingCardTokenId + 1), 2, "bob card1");
        assertEq(IERC1155(address(creator)).balanceOf(alice, startingCardTokenId + 2), 5, "alice card2");
    }

    function test_airdropEmitsEvent() public {
        (address[] memory tos, uint256[] memory ids, uint256[] memory amts) =
            _single(alice, startingCardTokenId, 1);

        vm.expectEmit(false, false, false, true, address(packs));
        emit Airdropped(tos, ids, amts);

        vm.prank(owner);
        packs.airdrop(tos, ids, amts);
    }

    function test_nonOwnerCannotAirdrop() public {
        (address[] memory tos, uint256[] memory ids, uint256[] memory amts) =
            _single(alice, startingCardTokenId, 1);

        vm.prank(collector);
        vm.expectRevert(); // TwoStepOwnable OnlyOwner
        packs.airdrop(tos, ids, amts);
    }

    function test_mismatchedLengthsRevert() public {
        address[] memory tos = new address[](2);
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amts = new uint256[](2);
        tos[0] = alice; tos[1] = bob;
        ids[0] = startingCardTokenId;
        amts[0] = 1; amts[1] = 1;

        vm.prank(owner);
        vm.expectRevert(IManifoldPacksSeaDropShim.InvalidAirdrop.selector);
        packs.airdrop(tos, ids, amts);
    }

    function test_emptyArraysRevert() public {
        address[] memory tos = new address[](0);
        uint256[] memory ids = new uint256[](0);
        uint256[] memory amts = new uint256[](0);

        vm.prank(owner);
        vm.expectRevert(IManifoldPacksSeaDropShim.InvalidAirdrop.selector);
        packs.airdrop(tos, ids, amts);
    }

    function test_outOfRangeCardIdReverts() public {
        // start + numberOfVariations is one past the reserved range.
        (address[] memory tos, uint256[] memory ids, uint256[] memory amts) =
            _single(alice, startingCardTokenId + NUM_CARD_DESIGNS, 1);

        vm.prank(owner);
        vm.expectRevert(IManifoldPacksSeaDropShim.InvalidCardIds.selector);
        packs.airdrop(tos, ids, amts);
    }

    function test_belowRangeCardIdReverts() public {
        // startingCardTokenId is 1 in the harness; id 0 is below the range.
        vm.assume(startingCardTokenId > 0);
        (address[] memory tos, uint256[] memory ids, uint256[] memory amts) =
            _single(alice, startingCardTokenId - 1, 1);

        vm.prank(owner);
        vm.expectRevert(IManifoldPacksSeaDropShim.InvalidCardIds.selector);
        packs.airdrop(tos, ids, amts);
    }

    function test_airdropWorksOutsideRipWindow() public {
        // Close the rip window entirely (start in the far future).
        _setRipWindow(block.timestamp + 30 days, block.timestamp + 60 days);

        (address[] memory tos, uint256[] memory ids, uint256[] memory amts) =
            _single(alice, startingCardTokenId, 1);

        vm.prank(owner);
        packs.airdrop(tos, ids, amts); // no RipNotStarted/RipEnded gate

        assertEq(IERC1155(address(creator)).balanceOf(alice, startingCardTokenId), 1, "airdrop ignores rip window");
    }

    /// @notice Airdrops now count toward the minted total (lazy-claim parity):
    ///         `mintedCards` increases by the airdropped amount, and if a cap is
    ///         set and would be exceeded the cap is RAISED to the new total so
    ///         the airdrop is never blocked. `maxCardsSupply` is therefore a real
    ///         total-supply figure (rips + airdrops), not a rip-only budget.
    function test_airdropIncrementsMintedAndRaisesCap() public {
        // Set a tight cap equal to exactly one pack's worth of cards.
        _setMaxCardsSupply(CARDS_PER_PACK);
        assertEq(packs.mintedCards(), 0, "no cards minted yet");

        // Airdrop more than the cap — it succeeds AND auto-raises the cap.
        uint256 airdropAmount = CARDS_PER_PACK * 10;
        (address[] memory tos, uint256[] memory ids, uint256[] memory amts) =
            _single(alice, startingCardTokenId, airdropAmount);
        vm.prank(owner);
        packs.airdrop(tos, ids, amts);

        // mintedCards bumped by the airdropped amount.
        assertEq(packs.mintedCards(), airdropAmount, "airdrop counted toward mintedCards");
        // Cap auto-raised to the new total (was CARDS_PER_PACK, now airdropAmount).
        assertEq(packs.getConfig().maxCardsSupply, airdropAmount, "cap raised to new minted total");

        // TRADE-OFF: the cap was raised to EXACTLY mintedCards, so there is zero
        // headroom left — a subsequent rip reverts until the owner raises the cap.
        IManifoldPacksSeaDropShim.RipOrder[] memory orders = new IManifoldPacksSeaDropShim.RipOrder[](1);
        orders[0] = buildFixtureRipOrder(1);
        vm.prank(signerAddr);
        vm.expectRevert(IManifoldPacksSeaDropShim.MaxCardsSupplyExceeded.selector);
        packs.deliverBatch(orders);

        // Owner raises the cap to make room, then the rip goes through and adds
        // to the running total.
        _setMaxCardsSupply(airdropAmount + CARDS_PER_PACK);
        orders[0] = buildFixtureRipOrder(1);
        vm.prank(signerAddr);
        packs.deliverBatch(orders);

        assertEq(packs.mintedCards(), airdropAmount + CARDS_PER_PACK, "rip adds to the airdrop total");
    }

    /// @notice With an UNLIMITED cap (maxCardsSupply == 0), an airdrop still
    ///         increments mintedCards but leaves the cap at 0 (unlimited).
    function test_airdropUnderUnlimitedCapIncrementsMintedOnly() public {
        // Default config has maxCardsSupply == 0 (unlimited).
        assertEq(packs.getConfig().maxCardsSupply, 0, "cap unlimited by default");

        (address[] memory tos, uint256[] memory ids, uint256[] memory amts) =
            _single(alice, startingCardTokenId, 7);
        vm.prank(owner);
        packs.airdrop(tos, ids, amts);

        assertEq(packs.mintedCards(), 7, "airdrop counted toward mintedCards");
        assertEq(packs.getConfig().maxCardsSupply, 0, "unlimited cap stays unlimited");
    }

    function test_airdropBeforeInitializeCardsReverts() public {
        // Fresh deploy without initializeCards.
        address[] memory allowed = new address[](1);
        allowed[0] = address(seaDropCaller);
        vm.prank(owner);
        ManifoldPacksSeaDropShim fresh = new ManifoldPacksSeaDropShim("Fresh", "FRSH", allowed, owner);

        (address[] memory tos, uint256[] memory ids, uint256[] memory amts) =
            _single(alice, 1, 1);

        vm.prank(owner);
        vm.expectRevert(IManifoldPacksSeaDropShim.CardsNotInitialized.selector);
        fresh.airdrop(tos, ids, amts);
    }
}
