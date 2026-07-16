// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import {ManifoldPacksTestBase} from "./ManifoldPacksTestBase.t.sol";

import {SeaDrop} from "seadrop/src/SeaDrop.sol";
import {ISeaDrop} from "seadrop/src/interfaces/ISeaDrop.sol";
import {ISeaDropTokenContractMetadata} from "seadrop/src/interfaces/ISeaDropTokenContractMetadata.sol";
import {
    ERC721SeaDropStructsErrorsAndEvents
} from "seadrop/src/lib/ERC721SeaDropStructsErrorsAndEvents.sol";
import {
    PublicDrop,
    AllowListData,
    TokenGatedDropStage,
    SignedMintValidationParams
} from "seadrop/src/lib/SeaDropStructs.sol";

/**
 * @title  ManifoldPacksSeaDropConfig
 * @author manifold.xyz
 * @notice Verifies the US-013 SeaDrop drop configuration is REAL against the
 *         canonical SeaDrop surface — the 3-phase drop config (artists → allow
 *         list → public), price 0.0069 ETH, per-wallet cap 2, maxSupply 3943,
 *         fee recipient/feeBps, allowlist merkle root, creator payout, and the
 *         ERC-2981 royalty (`setRoyaltyInfo`) — then reads every value back via
 *         `getMintStats` / `maxSupply` / `getPublicDrop` / `getAllowListMerkleRoot`
 *         / `getCreatorPayoutAddress` / `getFeeRecipientIsAllowed` / `royaltyInfo`.
 *
 *         Two paths:
 *           1. ALWAYS-GREEN (offline): deploys a LOCAL `SeaDrop` instance
 *              (`lib/seadrop/src/SeaDrop.sol`) and drives the inherited
 *              `multiConfigure` against it. No RPC required — runs in CI and
 *              offline.
 *           2. FORK (opt-in): if the env var `MANIFOLD_FORK_RPC_URL` is set, forks
 *              that chain and drives the SAME config against the LIVE canonical
 *              SeaDrop at 0x00005EA00Ac477B1030CE78506496e8C2dE24bf5 (verified
 *              live on both Shape chains). When the env var is UNSET the fork
 *              test logs a skip notice and returns cleanly — it must NEVER fail
 *              the suite offline.
 *
 *         Inherits `ManifoldPacksTestBase` (US-004 base) for the deployed ManifoldPacks +
 *         cards core + wallets. The base already minted the fixture packs via a
 *         mock SeaDrop caller in setUp; this test replaces the allowed-SeaDrop
 *         set with the (local or live) SeaDrop before configuring, since
 *         `multiConfigure` gates every leg on `_onlyAllowedSeaDrop(seaDropImpl)`.
 */
contract ManifoldPacksSeaDropConfig is ManifoldPacksTestBase {
    /// @notice Canonical SeaDrop 1.0, live on both Shape chains.
    address internal constant CANONICAL_SEADROP = 0x00005EA00Ac477B1030CE78506496e8C2dE24bf5;

    /// @notice Locked drop economics (US-013 / US-014 AC).
    uint256 internal constant MINT_PRICE = 0.0069 ether;
    uint16 internal constant MAX_PER_WALLET = 2;
    uint256 internal constant DROP_MAX_SUPPLY = 3943;
    uint16 internal constant FEE_BPS = 500; // 5% platform fee (example ops input)
    uint96 internal constant ROYALTY_BPS = 690; // 6.9% creator royalty
    bytes32 internal constant ALLOWLIST_ROOT = keccak256("packs-allowlist-root-fixture");

    // Config parties (parameterizable in ops; fixed fixtures here).
    address internal feeRecipient = address(0xFEE);
    address internal creatorPayout = address(0xC0FFEE01);
    address internal royaltyRecipient = address(0x2981);

    /// @notice Public phase window fixture (artists/allowlist windows precede
    ///         it; the public stage is the on-chain-pushed leg). Exact
    ///         timestamps are TBD-5 ops inputs.
    uint256 internal publicStart;
    uint256 internal publicEnd;

    function setUp() public override {
        super.setUp();
        // Public phase: opens 3h after now (artists 1h + allowlist 2h), 24h long.
        publicStart = block.timestamp + 3 hours;
        publicEnd = publicStart + 24 hours;
    }

    // ─────────────────────────────────────────────────────────────────────
    // Path 1 — ALWAYS-GREEN local SeaDrop. No RPC.
    // ─────────────────────────────────────────────────────────────────────

    function testConfigAgainstLocalSeaDrop() public {
        SeaDrop seaDrop = new SeaDrop();
        _configureAndAssert(address(seaDrop));
    }

    // ─────────────────────────────────────────────────────────────────────
    // Path 2 — FORK against the LIVE canonical SeaDrop. Skips cleanly when
    // `MANIFOLD_FORK_RPC_URL` is unset (offline / CI without a fork RPC).
    // ─────────────────────────────────────────────────────────────────────

    function testConfigAgainstLiveSeaDropFork() public {
        string memory rpcUrl = vm.envOr("MANIFOLD_FORK_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) {
            emit log("SKIP: MANIFOLD_FORK_RPC_URL not set - live SeaDrop fork leg skipped (offline OK)");
            return;
        }

        // Fork the chain where the canonical SeaDrop is deployed, then rebuild
        // the system under test on the fork so `multiConfigure` hits the LIVE
        // SeaDrop code at CANONICAL_SEADROP.
        vm.createSelectFork(rpcUrl);

        // Sanity: the canonical SeaDrop must actually have code on this fork.
        require(CANONICAL_SEADROP.code.length > 0, "no SeaDrop code at canonical address on fork");

        // The base setUp() ran on the non-fork state; re-run it so the deployed
        // contracts live on the fork and reference the live SeaDrop is possible.
        super.setUp();
        publicStart = block.timestamp + 3 hours;
        publicEnd = publicStart + 24 hours;

        _configureAndAssert(CANONICAL_SEADROP);
    }

    // ─────────────────────────────────────────────────────────────────────
    // Shared config + assertions.
    // ─────────────────────────────────────────────────────────────────────

    function _configureAndAssert(address seaDropImpl) internal {
        // multiConfigure gates every leg on _onlyAllowedSeaDrop(seaDropImpl):
        // replace the allowed-SeaDrop set (base wired the mock caller) with the
        // SeaDrop under test. Owner-only.
        address[] memory allowed = new address[](1);
        allowed[0] = seaDropImpl;

        ERC721SeaDropStructsErrorsAndEvents.MultiConfigureStruct memory cfg =
            _buildConfig(seaDropImpl);

        ISeaDropTokenContractMetadata.RoyaltyInfo memory royalty =
            ISeaDropTokenContractMetadata.RoyaltyInfo({
                royaltyAddress: royaltyRecipient,
                royaltyBps: ROYALTY_BPS
            });

        vm.startPrank(owner);
        packs.updateAllowedSeaDrop(allowed);
        packs.multiConfigure(cfg);
        packs.setRoyaltyInfo(royalty);
        vm.stopPrank();

        // AC-1: maxSupply + per-wallet cap + price readable back.
        assertEq(packs.maxSupply(), DROP_MAX_SUPPLY, "maxSupply back");

        (uint256 minterNumMinted, uint256 currentTotalSupply, uint256 statsMaxSupply) =
            packs.getMintStats(collector);
        assertEq(minterNumMinted, 0, "collector minted 0");
        // Base minted FIXTURE_PACK_COUNT packs to owner in setUp.
        assertEq(currentTotalSupply, FIXTURE_PACK_COUNT, "total minted = fixture");
        assertEq(statsMaxSupply, DROP_MAX_SUPPLY, "getMintStats maxSupply");

        // Public drop stage pushed to SeaDrop and readable back.
        PublicDrop memory pd = ISeaDrop(seaDropImpl).getPublicDrop(address(packs));
        assertEq(uint256(pd.mintPrice), MINT_PRICE, "public price 0.0069 ETH");
        assertEq(uint256(pd.maxTotalMintableByWallet), uint256(MAX_PER_WALLET), "per-wallet cap 2");
        assertEq(uint256(pd.startTime), publicStart, "public start");
        assertEq(uint256(pd.endTime), publicEnd, "public end");
        assertEq(uint256(pd.feeBps), uint256(FEE_BPS), "feeBps");
        assertTrue(pd.restrictFeeRecipients, "restrict fee recipients");

        // Allowlist merkle root pushed and readable back.
        assertEq(
            ISeaDrop(seaDropImpl).getAllowListMerkleRoot(address(packs)),
            ALLOWLIST_ROOT,
            "allowlist root"
        );

        // Creator payout + fee recipient allowlisting readable back.
        assertEq(
            ISeaDrop(seaDropImpl).getCreatorPayoutAddress(address(packs)),
            creatorPayout,
            "creator payout"
        );
        assertTrue(
            ISeaDrop(seaDropImpl).getFeeRecipientIsAllowed(address(packs), feeRecipient),
            "fee recipient allowed"
        );

        // AC-2: ERC-2981 royalty configurable + readable back.
        (address recv, uint256 amount) = packs.royaltyInfo(1, 1 ether);
        assertEq(recv, royaltyRecipient, "royalty receiver");
        assertEq(amount, (1 ether * ROYALTY_BPS) / 10_000, "royalty amount 6.9%");
    }

    /**
     * @notice Build the SeaDrop `MultiConfigureStruct` for the public drop stage
     *         + allowlist root + fee/payout. The artists (1h) and allowlist (2h)
     *         windows are server-signed / merkle-gated stages enforced off-chain
     *         by the SeaDrop backend using the same price/feeBps/cap — the public
     *         stage + allowlist root are the on-chain-pushed legs. Phase
     *         timestamps + allowlist CSV are TBD-5 ops inputs (fixtures here).
     */
    function _buildConfig(address seaDropImpl)
        internal
        view
        returns (ERC721SeaDropStructsErrorsAndEvents.MultiConfigureStruct memory cfg)
    {
        PublicDrop memory publicDrop = PublicDrop({
            mintPrice: uint80(MINT_PRICE),
            startTime: uint48(publicStart),
            endTime: uint48(publicEnd),
            maxTotalMintableByWallet: MAX_PER_WALLET,
            feeBps: FEE_BPS,
            restrictFeeRecipients: true
        });

        AllowListData memory allowListData = AllowListData({
            merkleRoot: ALLOWLIST_ROOT,
            publicKeyURIs: new string[](0),
            allowListURI: "ipfs://packs-allowlist"
        });

        address[] memory allowedFeeRecipients = new address[](1);
        allowedFeeRecipients[0] = feeRecipient;

        cfg = ERC721SeaDropStructsErrorsAndEvents.MultiConfigureStruct({
            maxSupply: DROP_MAX_SUPPLY,
            baseURI: "ipfs://packs-pack-base/",
            contractURI: "ipfs://packs-contract",
            seaDropImpl: seaDropImpl,
            publicDrop: publicDrop,
            dropURI: "",
            allowListData: allowListData,
            creatorPayoutAddress: creatorPayout,
            provenanceHash: bytes32(0),
            allowedFeeRecipients: allowedFeeRecipients,
            disallowedFeeRecipients: new address[](0),
            allowedPayers: new address[](0),
            disallowedPayers: new address[](0),
            tokenGatedAllowedNftTokens: new address[](0),
            tokenGatedDropStages: new TokenGatedDropStage[](0),
            disallowedTokenGatedAllowedNftTokens: new address[](0),
            signers: new address[](0),
            signedMintValidationParams: new SignedMintValidationParams[](0),
            disallowedSigners: new address[](0)
        });
    }
}
