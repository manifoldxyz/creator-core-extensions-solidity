// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ManifoldPacksTestBase} from "./ManifoldPacksTestBase.t.sol";
import {IManifoldPacks} from "../../contracts/manifoldpacks/IManifoldPacks.sol";

/**
 * @title  ManifoldPacksOwnership
 * @notice US-012 — Two-step ownership transfer + post-transfer auth matrix (AC-9).
 *
 *         Exercises the inherited TwoStepOwnable flow (transferOwnership ->
 *         acceptOwnership) transferring the ManifoldPacks owner role to a partner
 *         After the new owner accepts:
 *           - the OLD owner can no longer call ANY owner-gated function
 *             (setSigner / updateConfig / initializeCards and the SeaDrop-token
 *             config: setMaxSupply / setBaseURI / updateAllowedSeaDrop) — all
 *             revert OnlyOwner.
 *           - the NEW owner CAN run setSigner / updateConfig and the SeaDrop
 *             config.
 *
 *         All owner-gated paths revert with the `OnlyOwner()` custom error
 *         (selector shared by TwoStepOwnable and ERC721ContractMetadata's
 *         `_onlyOwnerOrSelf`), asserted via its selector.
 */
contract ManifoldPacksOwnership is ManifoldPacksTestBase {
    /// @dev `OnlyOwner()` selector — shared by TwoStepOwnable.onlyOwner and the
    ///      SeaDrop `_onlyOwnerOrSelf` gate.
    bytes4 internal constant ONLY_OWNER_SELECTOR = bytes4(keccak256("OnlyOwner()"));

    /// @notice Partner wallet that will receive ownership.
    uint256 internal constant PARTNER_PK = 0xDECAF;
    address internal partner;

    function setUp() public virtual override {
        super.setUp();
        partner = vm.addr(PARTNER_PK);
    }

    // ---------------------------------------------------------------------
    // AC-9: two-step transfer requires accept; partner is not owner until then.
    // ---------------------------------------------------------------------

    function test_twoStepRequiresAccept() public {
        // Step 1: current owner initiates transfer.
        vm.prank(owner);
        packs.transferOwnership(partner);

        // Until accepted, owner is unchanged and partner cannot act as owner.
        assertEq(packs.owner(), owner, "owner unchanged before accept");

        vm.prank(partner);
        vm.expectRevert(ONLY_OWNER_SELECTOR);
        packs.setSigner(partner);

        // Step 2: partner accepts.
        vm.prank(partner);
        packs.acceptOwnership();

        assertEq(packs.owner(), partner, "owner is partner after accept");
    }

    function test_onlyPotentialOwnerCanAccept() public {
        vm.prank(owner);
        packs.transferOwnership(partner);

        // A random address (the collector) cannot accept.
        vm.prank(collector);
        vm.expectRevert(); // NotNextOwner
        packs.acceptOwnership();
    }

    // ---------------------------------------------------------------------
    // AC-9: post-accept auth matrix.
    // ---------------------------------------------------------------------

    function test_postTransferOldOwnerLockedOut() public {
        _transferTo(partner);

        // Precompute view values so no external view call is captured by an
        // expectRevert (expectRevert binds to the very next external call).
        uint256 maxPacks = MAX_PACKS;
        address[] memory allowed = new address[](1);
        allowed[0] = address(seaDropCaller);
        IManifoldPacks.PackConfig memory cfg = packs.getConfig();

        // Every owner-gated function reverts OnlyOwner for the OLD owner. Each
        // is pranked individually so expectRevert binds cleanly to one call.
        vm.prank(owner);
        vm.expectRevert(ONLY_OWNER_SELECTOR);
        packs.setSigner(owner);

        vm.prank(owner);
        vm.expectRevert(ONLY_OWNER_SELECTOR);
        packs.updateConfig(cfg);

        vm.prank(owner);
        vm.expectRevert(ONLY_OWNER_SELECTOR);
        packs.initializeCards(address(creator), cfg);

        // SeaDrop-token config is equally locked for the old owner.
        vm.prank(owner);
        vm.expectRevert(ONLY_OWNER_SELECTOR);
        packs.setMaxSupply(maxPacks);

        vm.prank(owner);
        vm.expectRevert(ONLY_OWNER_SELECTOR);
        packs.setBaseURI("ipfs://old-base/");

        vm.prank(owner);
        vm.expectRevert(ONLY_OWNER_SELECTOR);
        packs.updateAllowedSeaDrop(allowed);
    }

    function test_postTransferNewOwnerHasFullControl() public {
        _transferTo(partner);

        vm.startPrank(partner);

        // setSigner + read back via signer().
        packs.setSigner(collector);
        assertEq(packs.signer(), collector, "new owner set signer");

        // Update rip window + cards location via updateConfig + read back.
        uint256 newRipStart = block.timestamp + 7 days;
        IManifoldPacks.PackConfig memory cfg = packs.getConfig();
        cfg.ripStartDate = newRipStart;
        cfg.cardsLocation = "ipfs://partner/";
        packs.updateConfig(cfg);
        assertEq(packs.getConfig().ripStartDate, newRipStart, "new owner set ripStart");
        assertEq(packs.getConfig().cardsLocation, "ipfs://partner/", "new owner set location");

        // SeaDrop config surface the new owner can run.
        packs.setMaxSupply(MAX_PACKS);
        assertEq(packs.maxSupply(), MAX_PACKS, "new owner set maxSupply");

        packs.setBaseURI("ipfs://partner-base/");

        address[] memory allowed = new address[](1);
        allowed[0] = address(seaDropCaller);
        packs.updateAllowedSeaDrop(allowed);

        vm.stopPrank();
    }

    // ---------------------------------------------------------------------
    // Helper.
    // ---------------------------------------------------------------------

    function _transferTo(address newOwner) internal {
        vm.prank(owner);
        packs.transferOwnership(newOwner);
        vm.prank(newOwner);
        packs.acceptOwnership();
        assertEq(packs.owner(), newOwner, "ownership accepted");
    }
}
