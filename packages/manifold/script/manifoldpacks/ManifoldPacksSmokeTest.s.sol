// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import {ManifoldPacksSeaDropShim} from "../../contracts/manifoldpacks/ManifoldPacksSeaDropShim.sol";
import {IManifoldPacksSeaDropShim} from "../../contracts/manifoldpacks/IManifoldPacksSeaDropShim.sol";
import {ERC1155Creator} from "@manifoldxyz/creator-core-solidity/contracts/ERC1155Creator.sol";
import {ISeaDrop} from "seadrop/src/interfaces/ISeaDrop.sol";
import {PublicDrop} from "seadrop/src/lib/SeaDropStructs.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

/**
 * @title  ManifoldPacksSmokeTest
 * @author manifold.xyz
 * @notice SELF-CONTAINED live smoke test for the ManifoldPacksSeaDropShim pack "rip" journey on
 *         Shape Sepolia. Unlike the production runbook (`ManifoldPacksSeaDropShim.s.sol`,
 *         which crosses trust boundaries across multiple wallets), this script
 *         collapses EVERY role — cards-core admin, pack owner, backend signer,
 *         payer, and collector — into the SINGLE `TEST_WALLET_PRIVATE_KEY`
 *         wallet, so the entire flow runs as one ordered broadcast:
 *
 *           1. deploy a stock ERC1155Creator ("cards" core)   [deployer = admin]
 *           2. deploy ManifoldPacksSeaDropShim (collection name "TEST")      [deployer = owner]
 *           3. cards.registerExtension(packs, "")              [admin action]
 *           4. packs.initializeCards(cards, config)            [reserve N cards]
 *           5. packs.setSigner(deployer)                       [backend signer]
 *           6. packs.setMaxSupply(MAX_SUPPLY)
 *           7. packs.updateCreatorPayoutAddress(seaDrop, deployer)
 *           8. packs.updateAllowedFeeRecipient(seaDrop, deployer, true)
 *           9. packs.updatePublicDrop(seaDrop, publicDrop)     [open the mint]
 *          10. seaDrop.mintPublic{value}(packs, deployer, 0, 1)[MINT pack #1]
 *          11. deployer signs RipPermit(packId, deadline) off-chain (no tx)
 *          12. packs.deliverBatch([order])                     [BURN + mint 4 cards]
 *          13. VERIFY: pack burned (ownerOf reverts) + 4 cards delivered.
 *
 *         The whole thing is simulated against forked live state first (forge
 *         script's default), so the on-chain `require` gates act as a dry-run
 *         before a single wei is spent. Run WITHOUT --broadcast for the dry run,
 *         WITH --broadcast to actually deploy + exercise on Shape Sepolia.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * ENV VARS
 * ─────────────────────────────────────────────────────────────────────────────
 *   TEST_WALLET_PRIVATE_KEY (uint256) — funded Shape Sepolia burner. Plays ALL
 *                                       roles. NEVER a mainnet key.
 *   SEADROP_ADDRESS         (address) — optional; defaults to the canonical
 *                                       SeaDrop 1.0 at 0x00005EA0...bf5.
 *   PACKS_NAME              (string)  — optional; defaults to "TEST".
 *
 * Dry run (no broadcast, simulates against forked Shape Sepolia state):
 *   forge script script/manifoldpacks/ManifoldPacksSmokeTest.s.sol:ManifoldPacksSmokeTest \
 *     --rpc-url $SHAPE_SEPOLIA_RPC_URL
 *
 * Live (deploys + exercises on Shape Sepolia):
 *   forge script script/manifoldpacks/ManifoldPacksSmokeTest.s.sol:ManifoldPacksSmokeTest \
 *     --rpc-url $SHAPE_SEPOLIA_RPC_URL --broadcast --slow
 */
contract ManifoldPacksSmokeTest is Script {
    /// @notice Canonical SeaDrop 1.0, live on Shape mainnet + Sepolia.
    address internal constant CANONICAL_SEADROP = 0x00005EA00Ac477B1030CE78506496e8C2dE24bf5;

    // Smoke-test parameters. Card-side values mirror PRODUCTION exactly so the
    // 251-variation reservation and the non-zero maxCardsSupply cap path are
    // both exercised live. Pack SeaDrop supply is the production 3943.
    uint256 internal constant NUM_VARIATIONS = 251; // production
    uint256 internal constant CARDS_PER_PACK = 4; // production
    uint256 internal constant MAX_CARDS_SUPPLY = 15772; // production (3943 packs * 4)
    uint256 internal constant MAX_SUPPLY = 3943; // production pack supply
    uint80 internal constant MINT_PRICE = 0.0069 ether;
    uint16 internal constant FEE_BPS = 250; // 2.5%
    uint16 internal constant MAX_PER_WALLET = 5;

    /// @notice A distinct recipient for the airdrop leg (not the deployer), so
    ///         the airdropped card balances are unambiguously attributable.
    address internal constant AIRDROP_RECIPIENT = 0x000000000000000000000000000000000000dEaD;

    struct Ctx {
        uint256 key;
        address wallet;
        address seaDrop;
        string name;
        ManifoldPacksSeaDropShim packs;
        ERC1155Creator cards;
    }

    function run() external {
        Ctx memory ctx;
        ctx.key = vm.envUint("TEST_WALLET_PRIVATE_KEY");
        ctx.wallet = vm.addr(ctx.key);
        ctx.seaDrop = vm.envOr("SEADROP_ADDRESS", CANONICAL_SEADROP);
        ctx.name = vm.envOr("PACKS_NAME", string("TEST"));

        console.log("=== ManifoldPacksSeaDropShim Shape Sepolia smoke test ===");
        console.log("wallet (all roles):", ctx.wallet);
        console.log("seaDrop:           ", ctx.seaDrop);
        console.log("collection name:   ", ctx.name);
        console.log("wallet ETH before: ", ctx.wallet.balance);

        vm.startBroadcast(ctx.key);

        // 1-2. Deploy the cards core and the pack collection.
        ctx.cards = new ERC1155Creator("TEST Cards", "TESTCARD");
        address[] memory allowed = new address[](1);
        allowed[0] = ctx.seaDrop;
        ctx.packs = new ManifoldPacksSeaDropShim(ctx.name, "TEST", allowed, ctx.wallet);

        // 3-4. Register the extension (admin) then reserve the card variations.
        ctx.cards.registerExtension(address(ctx.packs), "");
        ctx.packs.initializeCards(address(ctx.cards), _config());

        // Assert the production card config landed exactly as requested.
        IManifoldPacksSeaDropShim.PackConfig memory got = ctx.packs.getConfig();
        require(got.maxCardsSupply == MAX_CARDS_SUPPLY, "maxCardsSupply mismatch");
        require(got.cardsPerPack == CARDS_PER_PACK, "cardsPerPack mismatch");
        require(got.numberOfVariations == NUM_VARIATIONS, "numberOfVariations mismatch");
        console.log("CONFIG: maxCardsSupply", got.maxCardsSupply);
        console.log("CONFIG: cardsPerPack  ", got.cardsPerPack);
        console.log("CONFIG: variations    ", got.numberOfVariations);
        console.log("CONFIG: 251 card ids reserved from startingCardTokenId", ctx.packs.startingCardTokenId());

        // 5-6. Backend signer + pack supply cap.
        ctx.packs.setSigner(ctx.wallet);
        ctx.packs.setMaxSupply(MAX_SUPPLY);

        // 7-9. SeaDrop public-drop config: payout, allowed fee recipient, drop.
        ctx.packs.updateCreatorPayoutAddress(ctx.seaDrop, ctx.wallet);
        ctx.packs.updateAllowedFeeRecipient(ctx.seaDrop, ctx.wallet, true);
        ctx.packs.updatePublicDrop(ctx.seaDrop, _publicDrop());

        // 10. MINT one pack to the wallet through the canonical SeaDrop.
        ISeaDrop(ctx.seaDrop).mintPublic{value: MINT_PRICE}(
            address(ctx.packs),
            ctx.wallet, // feeRecipient (allowed above)
            address(0), // minterIfNotPayer 0 => minter = msg.sender
            1
        );

        uint256 packId = 1; // ERC721A starts at 1; first mint on a fresh contract.
        require(ctx.packs.ownerOf(packId) == ctx.wallet, "pack not minted to wallet");
        console.log("LEG mint: pack minted. packId:", packId);

        // 11-12. Sign the RipPermit off-chain, then deliverBatch (burn + cards).
        uint256[4] memory cardIds = _pickCards(ctx.packs);
        IManifoldPacksSeaDropShim.RipOrder[] memory orders = new IManifoldPacksSeaDropShim.RipOrder[](1);
        orders[0] = _buildOrder(ctx, packId, cardIds);
        ctx.packs.deliverBatch(orders);
        console.log("LEG rip: deliverBatch submitted (pack burned + 4 cards minted).");

        // 13. AIRDROP: owner mints reserved cards directly (no pack burn) to a
        //     distinct recipient, exercising the new airdrop escape hatch.
        address[] memory adTos = new address[](2);
        uint256[] memory adIds = new uint256[](2);
        uint256[] memory adAmts = new uint256[](2);
        uint256 startCard = ctx.packs.startingCardTokenId();
        adTos[0] = AIRDROP_RECIPIENT; adIds[0] = startCard;     adAmts[0] = 3;
        adTos[1] = AIRDROP_RECIPIENT; adIds[1] = startCard + 1; adAmts[1] = 2;
        ctx.packs.airdrop(adTos, adIds, adAmts);
        console.log("LEG airdrop: 3x card", startCard, "+ 2x next card to recipient.");

        vm.stopBroadcast();

        // 14. VERIFY rip + airdrop on the resulting state.
        _verify(ctx, packId, cardIds);

        require(
            IERC1155(address(ctx.cards)).balanceOf(AIRDROP_RECIPIENT, startCard) == 3,
            "airdrop card A balance != 3"
        );
        require(
            IERC1155(address(ctx.cards)).balanceOf(AIRDROP_RECIPIENT, startCard + 1) == 2,
            "airdrop card B balance != 2"
        );
        console.log("VERIFY airdrop: recipient holds 3 + 2 airdropped cards.");
        // Airdrop must NOT have touched the rip budget (still just the 4 ripped).
        require(ctx.packs.mintedCards() == CARDS_PER_PACK, "airdrop corrupted rip budget");
        console.log("VERIFY airdrop: mintedCards still", ctx.packs.mintedCards(), "(rip budget intact).");

        console.log("wallet ETH after:  ", ctx.wallet.balance);
        console.log("=== smoke test complete ===");
        console.log("cards core:", address(ctx.cards));
        console.log("packs:     ", address(ctx.packs));
    }

    function _config() internal pure returns (IManifoldPacksSeaDropShim.PackConfig memory) {
        return IManifoldPacksSeaDropShim.PackConfig({
            maxCardsSupply: MAX_CARDS_SUPPLY,
            cardsPerPack: CARDS_PER_PACK,
            numberOfVariations: NUM_VARIATIONS,
            ripStartDate: 1, // always in the past => rip open immediately
            ripEndDate: 0, // no end
            cardsLocation: "https://example.com/manifoldpacks/cards/"
        });
    }

    function _publicDrop() internal view returns (PublicDrop memory) {
        return PublicDrop({
            mintPrice: MINT_PRICE,
            startTime: uint48(1),
            endTime: uint48(block.timestamp + 365 days),
            maxTotalMintableByWallet: MAX_PER_WALLET,
            feeBps: FEE_BPS,
            restrictFeeRecipients: true
        });
    }

    function _pickCards(ManifoldPacksSeaDropShim packs) internal view returns (uint256[4] memory cardIds) {
        uint256 start = packs.startingCardTokenId();
        cardIds = [start, start + 1, start + 2, start + 3];
    }

    /**
     * @notice Reproduce the EXACT EIP-712 digest ManifoldPacksSeaDropShim verifies (OZ
     *         EIP712("ManifoldPacksSeaDropShim","1") domain — note the domain name stays
     *         "ManifoldPacksSeaDropShim" even though the ERC721 collection name is "TEST"),
     *         sign it with the wallet key, and pack the RipOrder.
     */
    function _buildOrder(Ctx memory ctx, uint256 packId, uint256[4] memory cardIds)
        internal
        view
        returns (IManifoldPacksSeaDropShim.RipOrder memory order)
    {
        uint256 deadline = block.timestamp + 1 days;
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("ManifoldPacksSeaDropShim")),
                keccak256(bytes("1")),
                block.chainid,
                address(ctx.packs)
            )
        );
        bytes32 structHash = keccak256(abi.encode(ctx.packs.RIP_TYPEHASH(), packId, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ctx.key, digest);

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

    function _verify(Ctx memory ctx, uint256 packId, uint256[4] memory cardIds) internal {
        bool burned;
        try ctx.packs.ownerOf(packId) returns (address) {
            burned = false;
        } catch {
            burned = true;
        }
        require(burned, "pack NOT burned after rip");
        console.log("VERIFY: pack burned (ownerOf reverts).");

        for (uint256 i = 0; i < 4; i++) {
            require(
                IERC1155(address(ctx.cards)).balanceOf(ctx.wallet, cardIds[i]) == 1,
                "missing card after rip"
            );
            console.log("VERIFY: holds card id", cardIds[i]);
        }
    }
}
