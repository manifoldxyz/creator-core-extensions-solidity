// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ManifoldPacksTestBase} from "./ManifoldPacksTestBase.t.sol";
import {ManifoldPacks} from "../../contracts/manifoldpacks/ManifoldPacks.sol";
import {IManifoldPacks} from "../../contracts/manifoldpacks/IManifoldPacks.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

/**
 * @title  ManifoldPacksAirdrop
 * @notice Tests for the owner airdrop escape hatch: mint reserved card
 *         variations directly to recipients, bypassing the pack-burn rip flow.
 *         Verifies access control, array validation, range checks, rip-window
 *         independence, and — critically — that airdrops do NOT consume or
 *         corrupt the rip budget (`mintedCards` / `maxCardsSupply`).
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
        vm.expectRevert(IManifoldPacks.InvalidAirdrop.selector);
        packs.airdrop(tos, ids, amts);
    }

    function test_emptyArraysRevert() public {
        address[] memory tos = new address[](0);
        uint256[] memory ids = new uint256[](0);
        uint256[] memory amts = new uint256[](0);

        vm.prank(owner);
        vm.expectRevert(IManifoldPacks.InvalidAirdrop.selector);
        packs.airdrop(tos, ids, amts);
    }

    function test_outOfRangeCardIdReverts() public {
        // start + numberOfVariations is one past the reserved range.
        (address[] memory tos, uint256[] memory ids, uint256[] memory amts) =
            _single(alice, startingCardTokenId + NUM_CARD_DESIGNS, 1);

        vm.prank(owner);
        vm.expectRevert(IManifoldPacks.InvalidCardIds.selector);
        packs.airdrop(tos, ids, amts);
    }

    function test_belowRangeCardIdReverts() public {
        // startingCardTokenId is 1 in the harness; id 0 is below the range.
        vm.assume(startingCardTokenId > 0);
        (address[] memory tos, uint256[] memory ids, uint256[] memory amts) =
            _single(alice, startingCardTokenId - 1, 1);

        vm.prank(owner);
        vm.expectRevert(IManifoldPacks.InvalidCardIds.selector);
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

    /// @notice The critical invariant: airdrop must NOT touch mintedCards or the
    ///         rip cap, so a full-budget rip still succeeds afterwards.
    function test_airdropDoesNotConsumeRipBudget() public {
        // Set a tight cap equal to exactly one pack's worth of cards.
        _setMaxCardsSupply(CARDS_PER_PACK);
        assertEq(packs.mintedCards(), 0, "no cards minted yet");

        // Airdrop a bunch of cards — more than the cap.
        (address[] memory tos, uint256[] memory ids, uint256[] memory amts) =
            _single(alice, startingCardTokenId, CARDS_PER_PACK * 10);
        vm.prank(owner);
        packs.airdrop(tos, ids, amts);

        // mintedCards untouched by the airdrop.
        assertEq(packs.mintedCards(), 0, "airdrop did not touch mintedCards");

        // A full-cap rip of a fixture pack still succeeds (budget intact).
        IManifoldPacks.RipOrder[] memory orders = new IManifoldPacks.RipOrder[](1);
        orders[0] = buildFixtureRipOrder(1);
        vm.prank(signerAddr);
        packs.deliverBatch(orders);

        assertEq(packs.mintedCards(), CARDS_PER_PACK, "rip consumed exactly one pack of budget");
    }

    function test_airdropBeforeInitializeCardsReverts() public {
        // Fresh deploy without initializeCards.
        address[] memory allowed = new address[](1);
        allowed[0] = address(seaDropCaller);
        vm.prank(owner);
        ManifoldPacks fresh = new ManifoldPacks("Fresh", "FRSH", allowed, owner);

        (address[] memory tos, uint256[] memory ids, uint256[] memory amts) =
            _single(alice, 1, 1);

        vm.prank(owner);
        vm.expectRevert(IManifoldPacks.CardsNotInitialized.selector);
        fresh.airdrop(tos, ids, amts);
    }
}
