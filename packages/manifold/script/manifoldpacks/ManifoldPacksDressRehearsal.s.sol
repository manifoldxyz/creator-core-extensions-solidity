// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import {ManifoldPacksSeaDropShim} from "../../contracts/manifoldpacks/ManifoldPacksSeaDropShim.sol";
import {IManifoldPacksSeaDropShim} from "../../contracts/manifoldpacks/IManifoldPacksSeaDropShim.sol";
import {ISeaDrop} from "seadrop/src/interfaces/ISeaDrop.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC1155MetadataURI} from "@openzeppelin/contracts/token/ERC1155/extensions/IERC1155MetadataURI.sol";

/**
 * @title  ManifoldPacksDressRehearsal
 * @author manifold.xyz
 * @notice AC-11 dress-rehearsal harness for the ManifoldPacksSeaDropShim pack "rip" journey,
 *         designed to run against Shape Sepolia (or any fork of it). It drives
 *         the full end-to-end flow with real txs and captures a receipt/log per
 *         leg so the QA/preview gate has human-visible artifacts:
 *
 *           LEG 1 — SeaDrop-path mint: a PAYER wallet calls
 *                   `ISeaDrop.mintPublic{value}(packs, feeRecipient, collector, 1)`
 *                   minting ONE pack to the ZERO-BALANCE `collector`
 *                   (`minterIfNotPayer = collector`, so the collector spends no
 *                   ETH — the payer covers price + gas). Captures the pack
 *                   tokenId + the mint tx.
 *           LEG 2 — Gasless consent: the zero-balance `collector` signs an
 *                   EIP-712 `RipPermit(packId, deadline)` OFF-CHAIN (no tx, no
 *                   gas). Reproduces the exact digest `ManifoldPacksSeaDropShim` verifies via
 *                   `_hashTypedDataV4` using the on-chain `RIP_TYPEHASH` + the
 *                   OZ EIP712("ManifoldPacksSeaDropShim","1") domain.
 *           LEG 3 — Delivery: the authorized `signer` submits ONE
 *                   `deliverBatch([order])` tx that atomically burns the pack and
 *                   mints the 4 correct cards to the collector on the 1155 cards
 *                   core. The signer pays gas; the collector's ETH is untouched
 *                   throughout (AC-4 gasless leg on a live chain).
 *           VERIFY — asserts `ownerOf(packId)` now reverts (pack burned), the
 *                   collector holds 1 of each of the 4 cards on the cards core,
 *                   and logs the resolved card metadata URIs (via the extension
 *                   `tokenURI(creator, cardId)` folder-pattern resolver and the
 *                   cards-core `uri(cardId)`), measuring OpenSea Shape indexing
 *                   latency as a side artifact (open-Q O2).
 *
 *         SCOPE: this is the BUILDABLE harness — it compiles under `forge build`
 *         and can be DRY-RUN against a local fork. NEVER broadcast a live tx
 *         from CI; the real Shape Sepolia run with linked receipts is the
 *         downstream Phase-6 live-ops execution (ASSUMPTIONS #11, QA-11).
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * PRECONDITIONS (the stack must already be deployed + configured — US-013 runbook)
 * ─────────────────────────────────────────────────────────────────────────────
 *   - ManifoldPacksSeaDropShim deployed, registered as an extension on the cards core, and
 *     initializeCards() run (startingCardTokenId != 0).
 *   - signer + ripStart set (ripStart <= now), cardsLocation set.
 *   - SeaDrop public drop configured (US-013 step 4) with the SeaDrop at
 *     SEADROP_ADDRESS allowed and the public window OPEN, price 0.0069 ETH.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * ENV VARS (all secrets via env — NEVER hardcode keys)
 * ─────────────────────────────────────────────────────────────────────────────
 *   MANIFOLD_PACKS         (address) — deployed ManifoldPacksSeaDropShim.
 *   SEADROP_ADDRESS     (address) — SeaDrop to mint through
 *                                   (0x00005EA00Ac477B1030CE78506496e8C2dE24bf5).
 *   FEE_RECIPIENT       (address) — allowed SeaDrop fee recipient (from US-013).
 *   PAYER_PRIVATE_KEY   (uint256) — wallet that PAYS for the mint (price + gas).
 *                                   Distinct from the collector so the collector
 *                                   stays zero-balance.
 *   COLLECTOR_PRIVATE_KEY (uint256) — the ZERO-BALANCE collector. Receives the
 *                                   pack and the cards; signs the RipPermit
 *                                   off-chain; spends NO ETH.
 *   SIGNER_PRIVATE_KEY  (uint256) — the authorized rip signer. Submits
 *                                   deliverBatch and pays its gas.
 *   MINT_PRICE_WEI      (uint256) — public mint price in wei (0.0069 ETH).
 *                                   Optional; defaults to 0.0069 ether.
 *   PERMIT_DEADLINE     (uint256) — RipPermit deadline. Optional; defaults to
 *                                   now + 1 hour.
 *
 * Example (DRY RUN against a local fork of Shape Sepolia — NO broadcast):
 *   forge script script/manifoldpacks/ManifoldPacksDressRehearsal.s.sol:ManifoldPacksDressRehearsal \
 *     --rpc-url $SHAPE_SEPOLIA_RPC_URL
 *
 * Example (LIVE — downstream live-ops ONLY, not CI):
 *   forge script script/manifoldpacks/ManifoldPacksDressRehearsal.s.sol:ManifoldPacksDressRehearsal \
 *     --rpc-url $SHAPE_SEPOLIA_RPC_URL --broadcast --slow
 */
contract ManifoldPacksDressRehearsal is Script {
    address internal constant CANONICAL_SEADROP = 0x00005EA00Ac477B1030CE78506496e8C2dE24bf5;
    uint256 internal constant DEFAULT_MINT_PRICE = 0.0069 ether;

    /// @notice Resolved run context, grouped to keep `run()` under the
    ///         stack-depth limit (avoids "Stack too deep" without via-ir).
    struct Ctx {
        ManifoldPacksSeaDropShim packs;
        address creator;
        address seaDrop;
        address feeRecipient;
        uint256 payerKey;
        uint256 collectorKey;
        uint256 signerKey;
        address payer;
        address collector;
        address signer;
        uint256 mintPrice;
        uint256 deadline;
    }

    function run() external {
        Ctx memory ctx = _loadCtx();

        require(address(ctx.packs) != address(0), "MANIFOLD_PACKS not set");
        require(ctx.feeRecipient != address(0), "FEE_RECIPIENT not set");
        require(ctx.packs.startingCardTokenId() != 0, "cards not initialized (run US-013 step 2)");
        require(ctx.packs.signer() == ctx.signer, "SIGNER_PRIVATE_KEY != configured rip signer");

        console.log("=== ManifoldPacksSeaDropShim dress rehearsal (AC-11) ===");
        console.log("packs:      ", address(ctx.packs));
        console.log("cards core: ", ctx.creator);
        console.log("seaDrop:    ", ctx.seaDrop);
        console.log("payer:      ", ctx.payer);
        console.log("collector:  ", ctx.collector);
        console.log("signer:     ", ctx.signer);
        console.log("collector ETH before:", ctx.collector.balance);

        uint256 packId = _legMint(ctx);
        uint256[4] memory cardIds = _pickCards(ctx.packs);
        _legDeliver(ctx, packId, cardIds);
        _verify(ctx, packId, cardIds);

        console.log("collector ETH after (must equal before):", ctx.collector.balance);
        console.log("=== dress rehearsal complete: attach the per-leg tx receipts to the preview gate ===");
    }

    /// @notice Load + derive all run parameters from env into a single struct.
    function _loadCtx() internal returns (Ctx memory ctx) {
        ctx.packs = ManifoldPacksSeaDropShim(vm.envAddress("MANIFOLD_PACKS"));
        ctx.creator = ctx.packs.creatorContractAddress();
        ctx.seaDrop = vm.envOr("SEADROP_ADDRESS", CANONICAL_SEADROP);
        ctx.feeRecipient = vm.envAddress("FEE_RECIPIENT");
        ctx.payerKey = vm.envUint("PAYER_PRIVATE_KEY");
        ctx.collectorKey = vm.envUint("COLLECTOR_PRIVATE_KEY");
        ctx.signerKey = vm.envUint("SIGNER_PRIVATE_KEY");
        ctx.payer = vm.addr(ctx.payerKey);
        ctx.collector = vm.addr(ctx.collectorKey);
        ctx.signer = vm.addr(ctx.signerKey);
        ctx.mintPrice = vm.envOr("MINT_PRICE_WEI", DEFAULT_MINT_PRICE);
        ctx.deadline = vm.envOr("PERMIT_DEADLINE", block.timestamp + 1 hours);
    }

    /**
     * @notice LEG 1: SeaDrop-path mint ONE pack to the zero-balance collector.
     *         The PAYER is msg.sender (pays price + gas); minterIfNotPayer =
     *         collector receives the pack, so the collector spends no ETH.
     */
    function _legMint(Ctx memory ctx) internal returns (uint256 packId) {
        packId = _totalMintedGuess(ctx.packs) + 1; // ERC721A ids are 1-based, sequential.
        vm.startBroadcast(ctx.payerKey);
        ISeaDrop(ctx.seaDrop).mintPublic{value: ctx.mintPrice}(
            address(ctx.packs),
            ctx.feeRecipient,
            ctx.collector,
            1
        );
        vm.stopBroadcast();

        packId = _resolveMintedPack(ctx.packs, ctx.collector, packId);
        require(ctx.packs.ownerOf(packId) == ctx.collector, "pack not owned by collector after mint");
        console.log("LEG 1 done. Pack minted to zero-balance collector. packId:", packId);
    }

    /**
     * @notice LEG 2 (off-chain sign) + LEG 3 (deliverBatch). The collector signs
     *         a RipPermit off-chain (no tx, no gas); the signer submits ONE
     *         deliverBatch tx that atomically burns the pack and mints 4 cards.
     */
    function _legDeliver(Ctx memory ctx, uint256 packId, uint256[4] memory cardIds) internal {
        IManifoldPacksSeaDropShim.RipOrder memory order =
            _buildSignedOrder(ctx.packs, ctx.collectorKey, packId, cardIds, ctx.deadline);
        console.log("LEG 2 done. Collector signed RipPermit off-chain. deadline:", ctx.deadline);
        console.log("collector ETH after signing:", ctx.collector.balance, "(unchanged)");

        IManifoldPacksSeaDropShim.RipOrder[] memory orders = new IManifoldPacksSeaDropShim.RipOrder[](1);
        orders[0] = order;
        vm.startBroadcast(ctx.signerKey);
        ctx.packs.deliverBatch(orders);
        vm.stopBroadcast();
        console.log("LEG 3 done. signer submitted deliverBatch (pack burned + 4 cards minted).");
    }

    /**
     * @notice VERIFY: pack burned, collector holds the 4 cards, metadata
     *         resolves. Logs the resolved card URIs (side artifact: OpenSea
     *         Shape indexing latency, open-Q O2).
     */
    function _verify(Ctx memory ctx, uint256 packId, uint256[4] memory cardIds) internal {
        bool burned;
        try ctx.packs.ownerOf(packId) returns (address) {
            burned = false;
        } catch {
            burned = true; // ERC721A OwnerQueryForNonexistentToken == burned.
        }
        require(burned, "pack NOT burned after deliverBatch");
        console.log("VERIFY: pack burned (ownerOf reverts OwnerQueryForNonexistentToken).");

        for (uint256 i = 0; i < 4; i++) {
            uint256 cardId = cardIds[i];
            require(
                IERC1155(ctx.creator).balanceOf(ctx.collector, cardId) == 1,
                "collector missing a card after rip"
            );
            string memory extUri = ctx.packs.tokenURI(ctx.creator, cardId);
            string memory coreUri = IERC1155MetadataURI(ctx.creator).uri(cardId);
            console.log("VERIFY card:", cardId, "balance 1. ext tokenURI:", extUri);
            console.log("            cards-core uri:", coreUri);
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────

    /**
     * @notice Best-effort next-pack-id guess from the collection's totalSupply.
     *         ERC721A mints sequentially from 1; totalSupply excludes burned
     *         tokens, so this is only a starting point — `_resolveMintedPack`
     *         confirms/scans for the actual minted id.
     */
    function _totalMintedGuess(ManifoldPacksSeaDropShim packs) internal returns (uint256) {
        try packs.totalSupply() returns (uint256 ts) {
            return ts;
        } catch {
            return 0;
        }
    }

    /**
     * @notice Confirm which pack id the collector received. Tries the guessed id
     *         first, then scans a small forward window (handles prior mints /
     *         burns shifting the sequential counter).
     */
    function _resolveMintedPack(ManifoldPacksSeaDropShim packs, address collector, uint256 guess)
        internal
        returns (uint256)
    {
        if (guess != 0 && _ownsQuietly(packs, guess) == collector) return guess;
        // Scan a bounded window around the guess for the collector's newest pack.
        uint256 start = guess > 8 ? guess - 8 : 1;
        for (uint256 id = start; id <= guess + 8; id++) {
            if (_ownsQuietly(packs, id) == collector) return id;
        }
        revert("could not resolve minted packId for collector");
    }

    function _ownsQuietly(ManifoldPacksSeaDropShim packs, uint256 id) internal returns (address) {
        try packs.ownerOf(id) returns (address o) {
            return o;
        } catch {
            return address(0);
        }
    }

    /**
     * @notice Pick 4 valid card ids from the reserved contiguous range. The
     *         backend chooses the actual card designs per pack off-chain; here we
     *         take the first four reserved variation ids (all inside
     *         [startingCardTokenId, startingCardTokenId + NUM_CARD_DESIGNS)).
     */
    function _pickCards(ManifoldPacksSeaDropShim packs) internal view returns (uint256[4] memory cardIds) {
        uint256 start = packs.startingCardTokenId();
        cardIds = [start, start + 1, start + 2, start + 3];
    }

    /**
     * @notice Reproduce the EXACT EIP-712 digest ManifoldPacksSeaDropShim verifies and sign it
     *         with the collector's key, producing a fully-populated RipOrder.
     *         Only (packId, deadline) are covered by the signature; cardIds are
     *         relay data validated on-chain (range check).
     */
    function _buildSignedOrder(
        ManifoldPacksSeaDropShim packs,
        uint256 collectorKey,
        uint256 packId,
        uint256[4] memory cardIds,
        uint256 deadline
    ) internal view returns (IManifoldPacksSeaDropShim.RipOrder memory order) {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes("ManifoldPacksSeaDropShim")),
                keccak256(bytes("1")),
                block.chainid,
                address(packs)
            )
        );
        bytes32 structHash = keccak256(abi.encode(packs.RIP_TYPEHASH(), packId, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(collectorKey, digest);

        // New RipOrder shape: dynamic cardIds/amounts (each amount 1, so
        // sum == cardsPerPack == 4) + a `bytes` ECDSA signature packed as
        // abi.encodePacked(r, s, v) for SignatureChecker (EOA path).
        uint256[] memory ids = new uint256[](4);
        uint256[] memory amounts = new uint256[](4);
        for (uint256 i = 0; i < 4; i++) {
            ids[i] = cardIds[i];
            amounts[i] = 1;
        }

        order = IManifoldPacksSeaDropShim.RipOrder({
            packId: packId,
            cardIds: ids,
            amounts: amounts,
            deadline: deadline,
            signature: abi.encodePacked(r, s, v)
        });
    }
}
