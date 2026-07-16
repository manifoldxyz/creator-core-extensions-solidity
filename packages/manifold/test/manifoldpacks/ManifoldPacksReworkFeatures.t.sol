// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ManifoldPacksSeaDropShim} from "../../contracts/manifoldpacks/ManifoldPacksSeaDropShim.sol";
import {IManifoldPacksSeaDropShim} from "../../contracts/manifoldpacks/IManifoldPacksSeaDropShim.sol";

import {ManifoldPacksTestBase} from "./ManifoldPacksTestBase.t.sol";
import {MockERC1271Wallet} from "./mocks/MockERC1271Wallet.sol";

/**
 * @title  ManifoldPacksReworkFeatures
 * @notice Tests for the four PR-review reworks (Don, 2026-07-16):
 *           1. PackConfig owner-updatable params + raise-only guards.
 *           2. SignatureChecker/EIP-1271 support + break-glass off-switch +
 *              per-rip signatureVerified event flag.
 *           3. Dynamic cardIds/amounts with duplicate variations +
 *              sum(amounts) == cardsPerPack runtime check.
 *           (4 — removed pack tokenURI override — is asserted in the mint suite.)
 */
contract ManifoldPacksReworkFeatures is ManifoldPacksTestBase {
    event Ripped(
        uint256 indexed packId,
        address indexed owner,
        uint256[] cardIds,
        uint256[] amounts,
        bool signatureVerified
    );

    // -----------------------------------------------------------------
    // Break-glass signature off-switch (Don Q1 = option 2: default ON,
    // per-rip flag).
    // -----------------------------------------------------------------

    function test_sigRequiredByDefault_garbageSigReverts() public {
        // Default mode: a garbage signature reverts InvalidPermit.
        uint256[] memory ids = new uint256[](4);
        uint256[] memory amounts = new uint256[](4);
        for (uint256 i = 0; i < 4; i++) {
            ids[i] = startingCardTokenId;
            amounts[i] = 1;
        }
        IManifoldPacksSeaDropShim.RipOrder memory order = IManifoldPacksSeaDropShim.RipOrder({
            packId: 1,
            cardIds: ids,
            amounts: amounts,
            deadline: block.timestamp + 1 days,
            signature: hex"deadbeef" // garbage
        });
        IManifoldPacksSeaDropShim.RipOrder[] memory orders = new IManifoldPacksSeaDropShim.RipOrder[](1);
        orders[0] = order;

        // Default mode (sig required): garbage signature reverts InvalidPermit.
        vm.prank(signerAddr);
        vm.expectRevert(IManifoldPacksSeaDropShim.InvalidPermit.selector);
        packs.deliverBatch(orders);
    }

    function test_breakGlassOff_garbageSigStillRips() public {
        // Owner flips the switch off; the same garbage signature now rips.
        vm.prank(owner);
        packs.setRipSignatureRequired(false);

        uint256[] memory ids = new uint256[](4);
        uint256[] memory amounts = new uint256[](4);
        for (uint256 i = 0; i < 4; i++) {
            ids[i] = startingCardTokenId;
            amounts[i] = 1;
        }
        IManifoldPacksSeaDropShim.RipOrder memory order = IManifoldPacksSeaDropShim.RipOrder({
            packId: 1,
            cardIds: ids,
            amounts: amounts,
            deadline: block.timestamp + 1 days,
            signature: hex"" // empty
        });
        IManifoldPacksSeaDropShim.RipOrder[] memory orders = new IManifoldPacksSeaDropShim.RipOrder[](1);
        orders[0] = order;

        vm.prank(signerAddr);
        packs.deliverBatch(orders);

        // Pack burned, 4 cards minted to owner despite no valid signature.
        vm.expectRevert();
        packs.ownerOf(1);
        assertEq(creator.balanceOf(owner, startingCardTokenId), 4, "cards minted in break-glass");
    }

    function test_perRipFlag_trueInNormalMode() public {
        IManifoldPacksSeaDropShim.RipOrder[] memory orders = new IManifoldPacksSeaDropShim.RipOrder[](1);
        orders[0] = buildFixtureRipOrder(1);

        (uint256[] memory ids, uint256[] memory amounts) = _fixtureArrays(cardsForPack(1));
        vm.expectEmit(true, true, false, true, address(packs));
        emit Ripped(1, owner, ids, amounts, true);

        vm.prank(signerAddr);
        packs.deliverBatch(orders);
    }

    function test_perRipFlag_falseInBreakGlass() public {
        vm.prank(owner);
        packs.setRipSignatureRequired(false);

        (uint256[] memory ids, uint256[] memory amounts) = _fixtureArrays(cardsForPack(1));
        IManifoldPacksSeaDropShim.RipOrder memory order = IManifoldPacksSeaDropShim.RipOrder({
            packId: 1,
            cardIds: ids,
            amounts: amounts,
            deadline: block.timestamp + 1 days,
            signature: hex""
        });
        IManifoldPacksSeaDropShim.RipOrder[] memory orders = new IManifoldPacksSeaDropShim.RipOrder[](1);
        orders[0] = order;

        vm.expectEmit(true, true, false, true, address(packs));
        emit Ripped(1, owner, ids, amounts, false);

        vm.prank(signerAddr);
        packs.deliverBatch(orders);
    }

    function test_setRipSignatureRequired_onlyOwner() public {
        vm.prank(collector);
        vm.expectRevert();
        packs.setRipSignatureRequired(false);
    }

    // -----------------------------------------------------------------
    // EIP-1271 smart-contract-wallet rip (SignatureChecker path).
    // -----------------------------------------------------------------

    function test_eip1271WalletCanRip() public {
        // A smart-contract wallet owned by OWNER_PK holds a pack and rips it via
        // an EIP-1271 signature that SignatureChecker validates.
        MockERC1271Wallet smartWallet = new MockERC1271Wallet(owner);

        // Transfer fixture pack 1 into the smart wallet.
        vm.prank(owner);
        packs.transferFrom(owner, address(smartWallet), 1);
        assertEq(packs.ownerOf(1), address(smartWallet), "smart wallet holds pack");

        // The wallet's owner EOA signs the permit; the wallet validates it via
        // isValidSignature -> magic value, so SignatureChecker accepts it.
        (uint256[] memory ids, uint256[] memory amounts) = _fixtureArrays(cardsForPack(1));
        IManifoldPacksSeaDropShim.RipOrder memory order = IManifoldPacksSeaDropShim.RipOrder({
            packId: 1,
            cardIds: ids,
            amounts: amounts,
            deadline: block.timestamp + 1 days,
            signature: signRipPermitBytes(OWNER_PK, 1, block.timestamp + 1 days)
        });
        IManifoldPacksSeaDropShim.RipOrder[] memory orders = new IManifoldPacksSeaDropShim.RipOrder[](1);
        orders[0] = order;

        vm.prank(signerAddr);
        packs.deliverBatch(orders);

        // Cards land in the smart wallet (the pack owner) — 4 distinct fixture
        // variations, one unit each.
        vm.expectRevert();
        packs.ownerOf(1);
        assertEq(creator.balanceOf(address(smartWallet), startingCardTokenId), 1, "card A to smart wallet");
        assertEq(creator.balanceOf(address(smartWallet), startingCardTokenId + 3), 1, "card D to smart wallet");
    }

    // -----------------------------------------------------------------
    // Duplicate variations + sum(amounts) == cardsPerPack.
    // -----------------------------------------------------------------

    function test_duplicateVariationViaAmount() public {
        // A pack of 4 cards = 2 copies of variation A + 1 of B + 1 of C, encoded
        // as amounts [2,1,1] over 3 distinct ids (sum == cardsPerPack == 4).
        uint256[] memory ids = new uint256[](3);
        uint256[] memory amounts = new uint256[](3);
        ids[0] = startingCardTokenId;      amounts[0] = 2;
        ids[1] = startingCardTokenId + 1;  amounts[1] = 1;
        ids[2] = startingCardTokenId + 2;  amounts[2] = 1;

        IManifoldPacksSeaDropShim.RipOrder memory order =
            buildRipOrderDyn(OWNER_PK, 1, ids, amounts, block.timestamp + 1 days);
        IManifoldPacksSeaDropShim.RipOrder[] memory orders = new IManifoldPacksSeaDropShim.RipOrder[](1);
        orders[0] = order;

        vm.prank(signerAddr);
        packs.deliverBatch(orders);

        assertEq(creator.balanceOf(owner, startingCardTokenId), 2, "2 copies of variation A");
        assertEq(creator.balanceOf(owner, startingCardTokenId + 1), 1, "1 of B");
        assertEq(creator.balanceOf(owner, startingCardTokenId + 2), 1, "1 of C");
    }

    function test_sumAmountsNotCardsPerPackReverts() public {
        // amounts sum to 3, not cardsPerPack (4) -> InvalidCardAmounts.
        uint256[] memory ids = new uint256[](3);
        uint256[] memory amounts = new uint256[](3);
        for (uint256 i = 0; i < 3; i++) {
            ids[i] = startingCardTokenId + i;
            amounts[i] = 1;
        }
        IManifoldPacksSeaDropShim.RipOrder memory order =
            buildRipOrderDyn(OWNER_PK, 1, ids, amounts, block.timestamp + 1 days);
        IManifoldPacksSeaDropShim.RipOrder[] memory orders = new IManifoldPacksSeaDropShim.RipOrder[](1);
        orders[0] = order;

        vm.prank(signerAddr);
        vm.expectRevert(IManifoldPacksSeaDropShim.InvalidCardAmounts.selector);
        packs.deliverBatch(orders);
    }

    // -----------------------------------------------------------------
    // ripEndDate gate + maxCardsSupply cap.
    // -----------------------------------------------------------------

    function test_ripEndDateGate() public {
        _setRipWindow(block.timestamp, block.timestamp + 1 days);
        vm.warp(block.timestamp + 2 days); // past ripEndDate

        IManifoldPacksSeaDropShim.RipOrder[] memory orders = new IManifoldPacksSeaDropShim.RipOrder[](1);
        orders[0] = buildFixtureRipOrder(1);

        vm.prank(signerAddr);
        vm.expectRevert(IManifoldPacksSeaDropShim.RipEnded.selector);
        packs.deliverBatch(orders);
    }

    function test_maxCardsSupplyCap() public {
        // Cap total card units at 4: the first pack rips fine, the second trips
        // MaxCardsSupplyExceeded.
        _setMaxCardsSupply(4);

        IManifoldPacksSeaDropShim.RipOrder[] memory first = new IManifoldPacksSeaDropShim.RipOrder[](1);
        first[0] = buildFixtureRipOrder(1);
        vm.prank(signerAddr);
        packs.deliverBatch(first);
        assertEq(packs.mintedCards(), 4, "first rip minted 4");

        IManifoldPacksSeaDropShim.RipOrder[] memory second = new IManifoldPacksSeaDropShim.RipOrder[](1);
        second[0] = buildFixtureRipOrder(2);
        vm.prank(signerAddr);
        vm.expectRevert(IManifoldPacksSeaDropShim.MaxCardsSupplyExceeded.selector);
        packs.deliverBatch(second);
    }

    // -----------------------------------------------------------------
    // updateConfig guards (Serendipity ideology).
    // -----------------------------------------------------------------

    function test_updateConfig_cannotLowerVariations() public {
        IManifoldPacksSeaDropShim.PackConfig memory cfg = packs.getConfig();
        cfg.numberOfVariations = cfg.numberOfVariations - 1;
        vm.prank(owner);
        vm.expectRevert(IManifoldPacksSeaDropShim.CannotChangeVariations.selector);
        packs.updateConfig(cfg);
    }

    function test_updateConfig_cannotRaiseVariations() public {
        // numberOfVariations is fixed at init — raising it also reverts.
        IManifoldPacksSeaDropShim.PackConfig memory cfg = packs.getConfig();
        cfg.numberOfVariations = cfg.numberOfVariations + 1;
        vm.prank(owner);
        vm.expectRevert(IManifoldPacksSeaDropShim.CannotChangeVariations.selector);
        packs.updateConfig(cfg);
    }

    function test_updateConfig_cannotLowerMaxBelowMinted() public {
        // Rip one pack (mints 4 cards), then try to set maxCardsSupply below 4.
        IManifoldPacksSeaDropShim.RipOrder[] memory orders = new IManifoldPacksSeaDropShim.RipOrder[](1);
        orders[0] = buildFixtureRipOrder(1);
        vm.prank(signerAddr);
        packs.deliverBatch(orders);

        IManifoldPacksSeaDropShim.PackConfig memory cfg = packs.getConfig();
        cfg.maxCardsSupply = 2; // below the 4 already minted
        vm.prank(owner);
        vm.expectRevert(IManifoldPacksSeaDropShim.CannotLowerMaxBeyondMinted.selector);
        packs.updateConfig(cfg);
    }

    function test_updateConfig_onlyOwner() public {
        IManifoldPacksSeaDropShim.PackConfig memory cfg = packs.getConfig();
        vm.prank(collector);
        vm.expectRevert();
        packs.updateConfig(cfg);
    }
}
