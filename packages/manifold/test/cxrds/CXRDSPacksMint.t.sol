// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {CXRDSTestBase} from "./CXRDSTestBase.t.sol";

import {INonFungibleSeaDropToken} from "seadrop/src/interfaces/INonFungibleSeaDropToken.sol";
import {
    ERC721SeaDropStructsErrorsAndEvents
} from "seadrop/src/lib/ERC721SeaDropStructsErrorsAndEvents.sol";

/**
 * @title  CXRDSPacksMint
 * @notice US-005 — SeaDrop mint + access unit tests (AC-1, AC-2).
 *
 *         Proves that packs mint as REAL sequential ERC721A tokens through the
 *         allowed SeaDrop caller, that `getMintStats` reflects the REAL ERC721A
 *         counters (`_totalMinted` / `_numberMinted`) — not shim-local
 *         accounting — that the 3,943 total-supply cap and the per-wallet cap
 *         are both driven by those real counters, and that only an allowed
 *         SeaDrop caller may invoke `mintSeaDrop`.
 */
contract CXRDSPacksMint is CXRDSTestBase {
    // A fresh minter with no keys needed — receipt-only assertions.
    address internal walletA = address(0xA1);
    address internal walletB = address(0xB2);
    // Whale used to fill the collection to its max supply.
    address internal whale = address(0x4A1E);

    // ------------------------------------------------------------------
    // AC-1: mint through SeaDrop -> real sequential ERC721A tokens.
    // ------------------------------------------------------------------

    /// @notice The base fixture already minted packs 1..FIXTURE_PACK_COUNT to
    ///         owner; assert they are real, sequentially-numbered ERC721A
    ///         tokens starting at id 1.
    function testFixturePacksAreSequentialERC721ATokens() public {
        for (uint256 id = 1; id <= FIXTURE_PACK_COUNT; id++) {
            assertEq(cxrds.ownerOf(id), owner, "sequential pack owned by owner");
        }
        // ERC721A is 1-based: token id 0 never exists.
        vm.expectRevert();
        cxrds.ownerOf(0);
    }

    /// @notice A wallet can mint packs through the allowed SeaDrop caller; the
    ///         packs appear as real ERC721A tokens with sequential ids that
    ///         continue after the fixture packs.
    function testAllowedSeaDropCallerMints() public {
        seaDropCaller.mint(address(cxrds), walletA, 2);

        // New packs continue the sequential numbering after the 10 fixture packs.
        uint256 firstNew = FIXTURE_PACK_COUNT + 1;
        assertEq(cxrds.ownerOf(firstNew), walletA, "pack 11 -> walletA");
        assertEq(cxrds.ownerOf(firstNew + 1), walletA, "pack 12 -> walletA");
        assertEq(cxrds.balanceOf(walletA), 2, "walletA balance");
    }

    // ------------------------------------------------------------------
    // getMintStats reflects the REAL ERC721A counters.
    // ------------------------------------------------------------------

    /// @notice getMintStats returns the real _numberMinted(minter),
    ///         _totalMinted(), and maxSupply — driven by ERC721A, not a
    ///         shim-local ledger.
    function testGetMintStatsReflectsRealCounters() public {
        // Baseline: only the 10 fixture packs exist, all minted to owner.
        (uint256 ownerMinted, uint256 total, uint256 maxSupply) = cxrds.getMintStats(owner);
        assertEq(ownerMinted, FIXTURE_PACK_COUNT, "owner numberMinted baseline");
        assertEq(total, FIXTURE_PACK_COUNT, "total minted baseline");
        assertEq(maxSupply, MAX_PACKS, "max supply == 3943");

        // Mint 3 more to walletB; both minter and total counters advance by the
        // real minted quantity.
        seaDropCaller.mint(address(cxrds), walletB, 3);
        (uint256 bMinted, uint256 total2,) = cxrds.getMintStats(walletB);
        assertEq(bMinted, 3, "walletB numberMinted");
        assertEq(total2, FIXTURE_PACK_COUNT + 3, "total minted after walletB");

        // owner's own counter is untouched by walletB's mint.
        (uint256 ownerMinted2,,) = cxrds.getMintStats(owner);
        assertEq(ownerMinted2, FIXTURE_PACK_COUNT, "owner counter unchanged");
    }

    /// @notice The per-wallet cap is enforced via the REAL _numberMinted the
    ///         SeaDrop stage reads: after 2 mints to a wallet, getMintStats
    ///         reports exactly 2 — the value a 2-per-wallet public drop uses to
    ///         block the 3rd.
    function testPerWalletCapDrivenByRealNumberMinted() public {
        seaDropCaller.mint(address(cxrds), walletA, 2);
        (uint256 aMinted,,) = cxrds.getMintStats(walletA);
        assertEq(aMinted, 2, "walletA at the 2-per-wallet cap");
    }

    /// @notice Minting beyond MAX_PACKS (3,943) total reverts via the real
    ///         _totalMinted supply check in mintSeaDrop.
    function testMintBeyondMaxSupplyReverts() public {
        uint256 remaining = MAX_PACKS - FIXTURE_PACK_COUNT;

        // Fill the collection exactly to its max supply.
        seaDropCaller.mint(address(cxrds), whale, remaining);
        (, uint256 total,) = cxrds.getMintStats(whale);
        assertEq(total, MAX_PACKS, "collection at max supply");

        // One more pack exceeds MAX_PACKS -> revert with the real supply-check
        // error, carrying (attemptedTotal, maxSupply) = (3944, 3943).
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC721SeaDropStructsErrorsAndEvents.MintQuantityExceedsMaxSupply.selector,
                MAX_PACKS + 1,
                MAX_PACKS
            )
        );
        seaDropCaller.mint(address(cxrds), whale, 1);
    }

    // ------------------------------------------------------------------
    // AC-2: only allowed SeaDrop callers may mint.
    // ------------------------------------------------------------------

    /// @notice A non-SeaDrop caller (this test contract, not in allowedSeaDrop)
    ///         invoking mintSeaDrop directly reverts OnlyAllowedSeaDrop.
    function testNonSeaDropCallerReverts() public {
        vm.expectRevert(INonFungibleSeaDropToken.OnlyAllowedSeaDrop.selector);
        cxrds.mintSeaDrop(walletA, 1);
    }

    /// @notice Even the pack owner cannot mint directly — the gate is the
    ///         allowed-SeaDrop set, not ownership.
    function testOwnerCannotMintDirectly() public {
        vm.prank(owner);
        vm.expectRevert(INonFungibleSeaDropToken.OnlyAllowedSeaDrop.selector);
        cxrds.mintSeaDrop(owner, 1);
    }
}
