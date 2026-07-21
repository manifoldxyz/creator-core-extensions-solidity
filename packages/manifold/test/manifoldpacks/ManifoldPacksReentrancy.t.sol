// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ManifoldPacksTestBase} from "./ManifoldPacksTestBase.t.sol";
import {IManifoldPacksSeaDropShim} from "../../contracts/manifoldpacks/IManifoldPacksSeaDropShim.sol";
import {ReentrantCardReceiver} from "./mocks/ReentrantCardReceiver.sol";

/**
 * @title  ManifoldPacksReentrancy
 * @notice Proves the `nonReentrant` guard on `deliverBatch` holds against a
 *         malicious card recipient that re-enters from the ERC1155 receive hook.
 *
 *         Rip delivers cards to `ownerOf(packId)`. If that owner is a contract,
 *         `_mintBatch` fires `onERC1155BatchReceived` on it BEFORE `deliverBatch`
 *         returns — the classic re-entrancy window. A recipient that calls
 *         `deliverBatch` again from the hook must be blocked by the guard, and
 *         since a rip batch is atomic, the whole outer rip reverts.
 */
contract ManifoldPacksReentrancy is ManifoldPacksTestBase {
    ReentrantCardReceiver internal attacker;

    function setUp() public override {
        super.setUp();
        attacker = new ReentrantCardReceiver(address(packs));

        // Break-glass OFF-signature mode so the signer alone can rip the pack now
        // owned by the attacker contract (a contract can't easily ECDSA-sign; this
        // isolates the re-entrancy axis from the permit axis).
        vm.prank(owner);
        packs.setRipSignatureRequired(false);

        // Open trading so we can move a pack to the attacker contract.
        vm.prank(owner);
        packs.updateTransfersPaused(false);

        // Give the attacker pack 1 (cards will be delivered to it on rip).
        vm.prank(owner);
        packs.transferFrom(owner, address(attacker), 1);
        assertEq(packs.ownerOf(1), address(attacker), "attacker owns pack 1");
    }

    /// @dev Override the base harness sanity check: this suite deliberately moves
    ///      fixture pack 1 to the attacker contract in setUp, so the base
    ///      assertion (pack 1 owned by `owner`) no longer holds. Re-assert the
    ///      modified invariant instead.
    function testHarnessSetup() public override {
        assertEq(packs.owner(), owner, "packs owner");
        assertEq(packs.signer(), signerAddr, "backend signer");
        assertEq(packs.ownerOf(1), address(attacker), "pack 1 moved to attacker");
    }

    function test_reentrantDeliverBatchReverts() public {
        // Arm the attacker to replay a (valid-looking) order from the hook.
        attacker.arm(buildFixtureRipOrder(2));

        IManifoldPacksSeaDropShim.RipOrder[] memory orders =
            new IManifoldPacksSeaDropShim.RipOrder[](1);
        orders[0] = buildFixtureRipOrder(1);

        // The re-entrant call from onERC1155BatchReceived hits nonReentrant and
        // reverts; the atomic batch bubbles that up, reverting the whole rip.
        vm.prank(signerAddr);
        vm.expectRevert();
        packs.deliverBatch(orders);

        // Pack 1 must NOT have been burned (whole tx rolled back).
        assertEq(packs.ownerOf(1), address(attacker), "pack 1 still exists after reverted rip");
    }

    function test_nonReentrantRecipientRipsFine() public {
        // Control: same setup but attacker NOT armed -> rip succeeds, cards land.
        // (attacker.armed defaults false, so the hook is a passthrough.)
        IManifoldPacksSeaDropShim.RipOrder[] memory orders =
            new IManifoldPacksSeaDropShim.RipOrder[](1);
        orders[0] = buildFixtureRipOrder(1);

        vm.prank(signerAddr);
        packs.deliverBatch(orders);

        vm.expectRevert();
        packs.ownerOf(1); // burned
        uint256[4] memory ids = cardsForPack(1);
        for (uint256 i = 0; i < 4; i++) {
            assertEq(creator.balanceOf(address(attacker), ids[i]), 1, "cards delivered to contract owner");
        }
    }
}
