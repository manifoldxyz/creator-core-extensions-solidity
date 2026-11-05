// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ManifoldPacksTestBase} from "./ManifoldPacksTestBase.t.sol";
import {IManifoldPacksSeaDropShim} from "../../contracts/manifoldpacks/IManifoldPacksSeaDropShim.sol";

/**
 * @title  ManifoldPacksCardTransfer
 * @notice Coverage proving the delivered CARDS (stock ERC1155 on the cards core)
 *         are fully free to transfer and burn — independent of the pack
 *         collection's secondary-transfer pause. The pause lives on the ERC721
 *         pack contract's `_beforeTokenTransfers`; the cards are a separate
 *         ERC1155Creator with no such gate, so card holders always have full
 *         custody (transfer, batch-transfer, burn), even while pack trading is
 *         paused.
 *
 *         Cards are delivered to the pack owner on rip (see buildFixtureRipOrder,
 *         which rips a fixture pack owned by `owner`). Each fixture pack commits
 *         to the four cards startingCardTokenId..+3, amount 1 each.
 */
contract ManifoldPacksCardTransfer is ManifoldPacksTestBase {
    /// @notice Rip fixture pack 1 (signer-authorized) so `owner` holds its 4 cards.
    function _ripPackToOwner(uint256 packId) internal returns (uint256[4] memory ids) {
        IManifoldPacksSeaDropShim.RipOrder[] memory orders = new IManifoldPacksSeaDropShim.RipOrder[](1);
        orders[0] = buildFixtureRipOrder(packId);
        vm.prank(signerAddr);
        packs.deliverBatch(orders);
        ids = cardsForPack(packId);
        // Sanity: owner holds one of each delivered card.
        for (uint256 i = 0; i < 4; i++) {
            assertEq(creator.balanceOf(owner, ids[i]), 1, "card delivered to owner");
        }
    }

    // ---------------------------------------------------------------------
    // Cards are freely transferable.
    // ---------------------------------------------------------------------

    function test_cardsFreelyTransferable() public {
        uint256[4] memory ids = _ripPackToOwner(1);

        // Owner transfers one card to collector — no approval gate, no pause.
        vm.prank(owner);
        creator.safeTransferFrom(owner, collector, ids[0], 1, "");

        assertEq(creator.balanceOf(collector, ids[0]), 1, "collector received card");
        assertEq(creator.balanceOf(owner, ids[0]), 0, "owner card debited");
    }

    function test_cardsBatchTransferable() public {
        uint256[4] memory ids = _ripPackToOwner(1);

        uint256[] memory tokenIds = new uint256[](4);
        uint256[] memory amounts = new uint256[](4);
        for (uint256 i = 0; i < 4; i++) {
            tokenIds[i] = ids[i];
            amounts[i] = 1;
        }

        vm.prank(owner);
        creator.safeBatchTransferFrom(owner, collector, tokenIds, amounts, "");

        for (uint256 i = 0; i < 4; i++) {
            assertEq(creator.balanceOf(collector, ids[i]), 1, "collector got each card");
            assertEq(creator.balanceOf(owner, ids[i]), 0, "owner debited each card");
        }
    }

    /// @notice The pack pause must NOT touch card transfers — cards are a
    ///         separate ERC1155 with no pause gate. This is the load-bearing
    ///         separation: pausing pack secondary trading leaves card custody
    ///         fully intact.
    function test_cardsTransferableWhilePacksPaused() public {
        uint256[4] memory ids = _ripPackToOwner(1);

        // Pause PACK secondary transfers.
        vm.prank(owner);
        packs.updateTransfersPaused(true);

        // Card transfer still works — cards live on a different contract.
        vm.prank(owner);
        creator.safeTransferFrom(owner, collector, ids[1], 1, "");
        assertEq(creator.balanceOf(collector, ids[1]), 1, "card transfers while packs paused");
    }

    // ---------------------------------------------------------------------
    // Cards are burnable.
    // ---------------------------------------------------------------------

    function test_cardsBurnable() public {
        uint256[4] memory ids = _ripPackToOwner(1);

        uint256 supplyBefore = creator.totalSupply(ids[0]);

        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        tokenIds[0] = ids[0];
        amounts[0] = 1;

        // Holder burns their own card (burn requires account == msg.sender).
        vm.prank(owner);
        creator.burn(owner, tokenIds, amounts);

        assertEq(creator.balanceOf(owner, ids[0]), 0, "card burned from holder");
        assertEq(creator.totalSupply(ids[0]), supplyBefore - 1, "total supply decremented");
    }

    function test_cardsBatchBurnable() public {
        uint256[4] memory ids = _ripPackToOwner(1);

        uint256[] memory tokenIds = new uint256[](4);
        uint256[] memory amounts = new uint256[](4);
        for (uint256 i = 0; i < 4; i++) {
            tokenIds[i] = ids[i];
            amounts[i] = 1;
        }

        vm.prank(owner);
        creator.burn(owner, tokenIds, amounts);

        for (uint256 i = 0; i < 4; i++) {
            assertEq(creator.balanceOf(owner, ids[i]), 0, "each card burned");
        }
    }

    /// @notice Burning cards is unaffected by the pack pause too.
    function test_cardsBurnableWhilePacksPaused() public {
        uint256[4] memory ids = _ripPackToOwner(1);

        vm.prank(owner);
        packs.updateTransfersPaused(true);

        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        tokenIds[0] = ids[2];
        amounts[0] = 1;

        vm.prank(owner);
        creator.burn(owner, tokenIds, amounts);
        assertEq(creator.balanceOf(owner, ids[2]), 0, "card burns while packs paused");
    }

    /// @notice A recipient of a transferred card can then burn it — full custody
    ///         transfers with the token.
    function test_transferredCardBurnableByNewHolder() public {
        uint256[4] memory ids = _ripPackToOwner(1);

        vm.prank(owner);
        creator.safeTransferFrom(owner, collector, ids[3], 1, "");

        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        tokenIds[0] = ids[3];
        amounts[0] = 1;

        vm.prank(collector);
        creator.burn(collector, tokenIds, amounts);
        assertEq(creator.balanceOf(collector, ids[3]), 0, "new holder burned received card");
    }

    // ---------------------------------------------------------------------
    // Operator approval on the cards core (setApprovalForAll).
    // ---------------------------------------------------------------------

    /// @notice A card holder can approve an operator on the ERC1155 cards core,
    ///         and the approval flag reads back true.
    function test_cardsSetApprovalForAll() public {
        uint256[4] memory ids = _ripPackToOwner(1);
        ids; // silence unused

        vm.prank(owner);
        creator.setApprovalForAll(collector, true);
        assertTrue(creator.isApprovedForAll(owner, collector), "operator approved on cards core");

        vm.prank(owner);
        creator.setApprovalForAll(collector, false);
        assertFalse(creator.isApprovedForAll(owner, collector), "operator approval revoked");
    }

    /// @notice An approved operator can transfer the holder's cards.
    function test_approvedOperatorCanTransferCards() public {
        uint256[4] memory ids = _ripPackToOwner(1);

        // Holder approves collector as operator.
        vm.prank(owner);
        creator.setApprovalForAll(collector, true);

        // Operator moves a card from owner to itself.
        vm.prank(collector);
        creator.safeTransferFrom(owner, collector, ids[0], 1, "");

        assertEq(creator.balanceOf(collector, ids[0]), 1, "operator transferred card");
        assertEq(creator.balanceOf(owner, ids[0]), 0, "holder card debited by operator");
    }

    /// @notice An approved operator can burn the holder's cards (burn allows
    ///         account == msg.sender OR isApprovedForAll(account, msg.sender)).
    function test_approvedOperatorCanBurnCards() public {
        uint256[4] memory ids = _ripPackToOwner(1);

        vm.prank(owner);
        creator.setApprovalForAll(collector, true);

        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        tokenIds[0] = ids[1];
        amounts[0] = 1;

        // Operator burns the holder's card on their behalf.
        vm.prank(collector);
        creator.burn(owner, tokenIds, amounts);
        assertEq(creator.balanceOf(owner, ids[1]), 0, "operator burned holder's card");
    }

    /// @notice Without approval, a third party cannot transfer or burn the
    ///         holder's cards — the approval is what unlocks operator custody.
    function test_unapprovedOperatorCannotTransferOrBurn() public {
        uint256[4] memory ids = _ripPackToOwner(1);

        // No setApprovalForAll — collector has no rights over owner's cards.
        vm.prank(collector);
        vm.expectRevert();
        creator.safeTransferFrom(owner, collector, ids[0], 1, "");

        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        tokenIds[0] = ids[0];
        amounts[0] = 1;

        vm.prank(collector);
        vm.expectRevert();
        creator.burn(owner, tokenIds, amounts);
    }
}
