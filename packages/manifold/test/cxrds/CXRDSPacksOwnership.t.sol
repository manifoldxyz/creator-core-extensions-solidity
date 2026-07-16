// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {CXRDSTestBase} from "./CXRDSTestBase.t.sol";

/**
 * @title  CXRDSPacksOwnership
 * @notice US-012 — Two-step ownership transfer + post-transfer auth matrix (AC-9).
 *
 *         Exercises the inherited TwoStepOwnable flow (transferOwnership ->
 *         acceptOwnership) transferring the CXRDSPacks owner role to a partner
 *         wallet. After the new owner accepts:
 *           - the OLD owner can no longer call ANY owner-gated function
 *             (setSigner / setRipStart / setCardsLocation / initializeCards and
 *             the SeaDrop-token config: setMaxSupply / setBaseURI /
 *             updateAllowedSeaDrop) — all revert OnlyOwner.
 *           - the NEW owner CAN run setSigner / setRipStart and the SeaDrop config.
 *
 *         All owner-gated paths revert with the `OnlyOwner()` custom error
 *         (selector shared by TwoStepOwnable and ERC721ContractMetadata's
 *         `_onlyOwnerOrSelf`), asserted via its selector.
 */
contract CXRDSPacksOwnership is CXRDSTestBase {
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
        cxrds.transferOwnership(partner);

        // Until accepted, owner is unchanged and partner cannot act as owner.
        assertEq(cxrds.owner(), owner, "owner unchanged before accept");

        vm.prank(partner);
        vm.expectRevert(ONLY_OWNER_SELECTOR);
        cxrds.setSigner(partner);

        // Step 2: partner accepts.
        vm.prank(partner);
        cxrds.acceptOwnership();

        assertEq(cxrds.owner(), partner, "owner is partner after accept");
    }

    function test_onlyPotentialOwnerCanAccept() public {
        vm.prank(owner);
        cxrds.transferOwnership(partner);

        // A random address (the collector) cannot accept.
        vm.prank(collector);
        vm.expectRevert(); // NotNextOwner
        cxrds.acceptOwnership();
    }

    // ---------------------------------------------------------------------
    // AC-9: post-accept auth matrix.
    // ---------------------------------------------------------------------

    function test_postTransferOldOwnerLockedOut() public {
        _transferTo(partner);

        // Precompute view values so no external view call is captured by an
        // expectRevert (expectRevert binds to the very next external call).
        uint256 maxPacks = cxrds.MAX_PACKS();
        address[] memory allowed = new address[](1);
        allowed[0] = address(seaDropCaller);

        // Every owner-gated function reverts OnlyOwner for the OLD owner. Each
        // is pranked individually so expectRevert binds cleanly to one call.
        vm.prank(owner);
        vm.expectRevert(ONLY_OWNER_SELECTOR);
        cxrds.setSigner(owner);

        vm.prank(owner);
        vm.expectRevert(ONLY_OWNER_SELECTOR);
        cxrds.setRipStart(block.timestamp + 1);

        vm.prank(owner);
        vm.expectRevert(ONLY_OWNER_SELECTOR);
        cxrds.setCardsLocation("ipfs://old/");

        vm.prank(owner);
        vm.expectRevert(ONLY_OWNER_SELECTOR);
        cxrds.initializeCards();

        // SeaDrop-token config is equally locked for the old owner.
        vm.prank(owner);
        vm.expectRevert(ONLY_OWNER_SELECTOR);
        cxrds.setMaxSupply(maxPacks);

        vm.prank(owner);
        vm.expectRevert(ONLY_OWNER_SELECTOR);
        cxrds.setBaseURI("ipfs://old-base/");

        vm.prank(owner);
        vm.expectRevert(ONLY_OWNER_SELECTOR);
        cxrds.updateAllowedSeaDrop(allowed);
    }

    function test_postTransferNewOwnerHasFullControl() public {
        _transferTo(partner);

        vm.startPrank(partner);

        // setSigner + read back via signer().
        cxrds.setSigner(collector);
        assertEq(cxrds.signer(), collector, "new owner set signer");

        // setRipStart + read back.
        uint256 newRipStart = block.timestamp + 7 days;
        cxrds.setRipStart(newRipStart);
        assertEq(cxrds.ripStart(), newRipStart, "new owner set ripStart");

        // setCardsLocation + read back.
        cxrds.setCardsLocation("ipfs://partner/");
        assertEq(cxrds.cardsLocation(), "ipfs://partner/", "new owner set location");

        // SeaDrop config surface the new owner can run.
        cxrds.setMaxSupply(cxrds.MAX_PACKS());
        assertEq(cxrds.maxSupply(), cxrds.MAX_PACKS(), "new owner set maxSupply");

        cxrds.setBaseURI("ipfs://partner-base/");

        address[] memory allowed = new address[](1);
        allowed[0] = address(seaDropCaller);
        cxrds.updateAllowedSeaDrop(allowed);

        vm.stopPrank();
    }

    // ---------------------------------------------------------------------
    // Helper.
    // ---------------------------------------------------------------------

    function _transferTo(address newOwner) internal {
        vm.prank(owner);
        cxrds.transferOwnership(newOwner);
        vm.prank(newOwner);
        cxrds.acceptOwnership();
        assertEq(cxrds.owner(), newOwner, "ownership accepted");
    }
}
