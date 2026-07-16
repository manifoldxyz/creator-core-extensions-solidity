// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import {CXRDSPacks} from "../../contracts/cxrds/CXRDSPacks.sol";
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
 * @title  DeployCXRDSPacks
 * @author manifold.xyz
 * @notice Parameterized Forge deploy + configuration runbook for the CXRDS pack
 *         collection (`contracts/cxrds/CXRDSPacks.sol`).
 *
 *         The `run()` function ONLY deploys `CXRDSPacks` via CREATE2 with a
 *         fixed salt and prints the deployed address + owner + creator, mirroring
 *         the shim precedent (`script/seadrop/ManifoldERC1155SeaDropShim.s.sol`).
 *         The full post-deploy sequence is NOT a single atomic broadcast — it
 *         crosses trust boundaries (a cards-core ADMIN action and an owner
 *         action are performed by different wallets) — so the ordered runbook
 *         is documented below and each owner-side leg is exposed as an
 *         individually-broadcastable helper for the operator to run in order.
 *
 *         NEVER hardcode secrets — every address, URI, timestamp, and price is
 *         env-parameterized. This script only compiles under `forge build`; the
 *         real broadcast is downstream live-ops (do not broadcast from CI).
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * POST-DEPLOY RUNBOOK (ordered — each leg is a separate tx / signer)
 * ─────────────────────────────────────────────────────────────────────────────
 *   PRECONDITION: the partner's Studio-deployed ERC1155 creator-core "cards"
 *   contract (CREATOR_CONTRACT) MUST already exist on-chain. CXRDSPacks binds to
 *   it immutably at construction; register/initialize will revert otherwise.
 *
 *   0. `run()` — deploy CXRDSPacks (CREATE2 fixed salt). Broadcaster = deployer
 *      EOA (pays gas). Ownership is transferred to INITIAL_OWNER in the
 *      constructor (CREATE2-safe).
 *
 *   1. registerExtension  [CARDS-CORE ADMIN action — NOT self-callable by
 *      CXRDSPacks, and NOT part of this script's broadcast]:
 *          creator.registerExtension(address(cxrds), "")   // 2-arg overload
 *      Must be executed by an admin of the CREATOR_CONTRACT. This is the reason
 *      the sequence is a runbook and not one atomic tx — the cards-core admin
 *      and the drop owner are distinct trust roles.
 *
 *   2. initializeCards()  [CXRDSPacks OWNER]:
 *          runInitializeCards()  → cxrds.initializeCards()
 *      Reserves the 251 contiguous card variation ids on the cards core. MUST
 *      run AFTER registerExtension (step 1) — creator-core rejects
 *      mintExtensionNew from an unregistered extension.
 *
 *   3. setSigner + setRipStart + setCardsLocation  [CXRDSPacks OWNER]:
 *          runConfigureRip()  → setSigner(SIGNER) ; setRipStart(RIP_START)
 *                               ; setCardsLocation(CARDS_LOCATION)
 *
 *   4. SeaDrop drop config (3 phases) + royalty  [CXRDSPacks OWNER]:
 *          runConfigureSeaDrop()  → cxrds.multiConfigure(cfg)
 *                                   cxrds.setRoyaltyInfo(royalty)
 *      Phases (LOCKED shape): artists (1h) → allowlist (2h) → public.
 *      Price 0.0069 ETH, per-wallet cap 2, maxSupply 3943. Exact phase
 *      timestamps + allowlist merkle root are OPS inputs (env). multiConfigure
 *      pushes the PUBLIC drop stage + allowlist merkle root on-chain; the
 *      earlier artists/allowlist windows are server-signed / merkle-gated stages
 *      driven by the SeaDrop backend using the same feeBps/price — see the
 *      runbook note in `runConfigureSeaDrop`.
 *
 *   5. Two-step ownership transfer to the partner wallet  [CXRDSPacks OWNER]:
 *          runTransferOwnership()  → cxrds.transferOwnership(PARTNER_OWNER)
 *      Then, from PARTNER_OWNER:  cxrds.acceptOwnership()  (TwoStepOwnable).
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * ENV VARS
 * ─────────────────────────────────────────────────────────────────────────────
 *   Deploy (step 0):
 *     PRIVATE_KEY       (uint256) — deployer EOA. Pays gas. NOT the owner.
 *     INITIAL_OWNER     (address) — owner set via constructor _transferOwnership.
 *     PACKS_NAME        (string)  — ERC721 name.
 *     PACKS_SYMBOL      (string)  — ERC721 symbol.
 *     CREATOR_CONTRACT  (address) — partner's Studio-deployed ERC1155 cards core
 *                                   (MUST exist before register/initialize).
 *     SEADROP_ADDRESS   (address) — canonical SeaDrop, defaults to
 *                                   0x00005EA00Ac477B1030CE78506496e8C2dE24bf5.
 *   Owner legs (steps 2-5):
 *     CXRDS_PACKS       (address) — the deployed CXRDSPacks (from step 0 log).
 *     OWNER_PRIVATE_KEY (uint256) — INITIAL_OWNER's key (broadcasts owner legs).
 *     SIGNER            (address) — backend rip signer (setSigner).             [TBD-ops]
 *     RIP_START         (uint256) — earliest rip timestamp (setRipStart).       [TBD-5]
 *     CARDS_LOCATION    (string)  — card metadata folder base URI.              [TBD-3]
 *     BASE_URI          (string)  — sealed-pack image base URI.                 [TBD-3]
 *     CONTRACT_URI      (string)  — drop-page contract metadata URI.            [TBD-3]
 *     PUBLIC_START      (uint256) — public phase start timestamp.               [TBD-5]
 *     PUBLIC_END        (uint256) — public phase end timestamp.                 [TBD-5]
 *     ALLOWLIST_ROOT    (bytes32) — allowlist merkle root (allowlist phase).    [TBD-5]
 *     ALLOWLIST_URI     (string)  — allowlist metadata URI.                     [TBD-5]
 *     CREATOR_PAYOUT    (address) — SeaDrop creator payout address.             [TBD-2]
 *     FEE_RECIPIENT     (address) — SeaDrop fee recipient.                      [TBD-2]
 *     FEE_BPS           (uint256) — SeaDrop fee basis points.                   [TBD-2]
 *     ROYALTY_RECIPIENT (address) — ERC-2981 royalty receiver.                  [TBD-2]
 *     ROYALTY_BPS       (uint256) — ERC-2981 royalty basis points.             [TBD-2]
 *     PARTNER_OWNER     (address) — partner wallet to receive ownership.        [TBD-ops]
 *
 * Example (deploy):
 *   forge script script/cxrds/CXRDSPacks.s.sol:DeployCXRDSPacks \
 *     --optimizer-runs 500 --rpc-url $RPC_URL --broadcast
 *
 * Example (owner config leg 4):
 *   forge script script/cxrds/CXRDSPacks.s.sol:DeployCXRDSPacks \
 *     --sig "runConfigureSeaDrop()" --rpc-url $RPC_URL --broadcast
 */
contract DeployCXRDSPacks is Script {
    /// @notice The canonical SeaDrop deployment, live on both Shape chains.
    address internal constant CANONICAL_SEADROP = 0x00005EA00Ac477B1030CE78506496e8C2dE24bf5;

    /// @notice Locked drop economics (from the approved plan / US-013 AC).
    uint256 internal constant MINT_PRICE = 0.0069 ether;
    uint16 internal constant MAX_PER_WALLET = 2;
    uint256 internal constant MAX_SUPPLY = 3943;

    /// @notice CREATE2 fixed salt: a second deploy with identical constructor
    ///         args on the same network reverts on address collision.
    bytes32 internal constant SALT =
        0xc0de5ca1e0000000000000000000000000000000000000000000000000000001;

    // ─────────────────────────────────────────────────────────────────────
    // Step 0 — deploy
    // ─────────────────────────────────────────────────────────────────────

    function run() external {
        address creatorContract = vm.envAddress("CREATOR_CONTRACT");
        address seaDropAddress = vm.envOr("SEADROP_ADDRESS", CANONICAL_SEADROP);
        address initialOwner = vm.envAddress("INITIAL_OWNER");
        string memory packsName = vm.envString("PACKS_NAME");
        string memory packsSymbol = vm.envString("PACKS_SYMBOL");

        require(creatorContract != address(0), "CREATOR_CONTRACT not set");
        require(seaDropAddress != address(0), "SEADROP_ADDRESS not set");
        require(initialOwner != address(0), "INITIAL_OWNER not set");

        address[] memory initialAllowedSeaDrop = new address[](1);
        initialAllowedSeaDrop[0] = seaDropAddress;

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        CXRDSPacks packs = new CXRDSPacks{salt: SALT}(
            packsName,
            packsSymbol,
            initialAllowedSeaDrop,
            creatorContract,
            initialOwner
        );

        vm.stopBroadcast();

        console.log("CXRDSPacks deployed at:      ", address(packs));
        console.log("  name:                      ", packsName);
        console.log("  symbol:                    ", packsSymbol);
        console.log("  owner:                     ", packs.owner());
        console.log("  creatorContractAddress:    ", packs.creatorContractAddress());
        console.log("  allowedSeaDrop:            ", seaDropAddress);
        console.log("  MAX_PACKS:                 ", packs.MAX_PACKS());
        console.log("");
        console.log("NEXT (runbook, in order):");
        console.log("  1. CARDS-CORE ADMIN: creator.registerExtension(packs, bytes(''))");
        console.log("  2. OWNER: --sig runInitializeCards()");
        console.log("  3. OWNER: --sig runConfigureRip()");
        console.log("  4. OWNER: --sig runConfigureSeaDrop()");
        console.log("  5. OWNER: --sig runTransferOwnership(); then partner acceptOwnership()");
    }

    // ─────────────────────────────────────────────────────────────────────
    // Step 2 — initializeCards (OWNER). Requires step 1 (registerExtension,
    // a cards-core ADMIN action) to have run first.
    // ─────────────────────────────────────────────────────────────────────

    function runInitializeCards() external {
        CXRDSPacks packs = _packs();
        uint256 ownerKey = vm.envUint("OWNER_PRIVATE_KEY");

        vm.startBroadcast(ownerKey);
        packs.initializeCards();
        vm.stopBroadcast();

        console.log("initializeCards() done. startingCardTokenId:", packs.startingCardTokenId());
    }

    // ─────────────────────────────────────────────────────────────────────
    // Step 3 — signer / ripStart / cardsLocation (OWNER)
    // ─────────────────────────────────────────────────────────────────────

    function runConfigureRip() external {
        CXRDSPacks packs = _packs();
        uint256 ownerKey = vm.envUint("OWNER_PRIVATE_KEY");

        address signer = vm.envAddress("SIGNER");
        uint256 ripStart = vm.envUint("RIP_START");
        string memory cardsLocation = vm.envString("CARDS_LOCATION");
        require(signer != address(0), "SIGNER not set");

        vm.startBroadcast(ownerKey);
        packs.setSigner(signer);
        packs.setRipStart(ripStart);
        packs.setCardsLocation(cardsLocation);
        vm.stopBroadcast();

        console.log("Rip configured. signer:", packs.signer());
        console.log("  ripStart:            ", packs.ripStart());
        console.log("  cardsLocation:       ", packs.cardsLocation());
    }

    // ─────────────────────────────────────────────────────────────────────
    // Step 4 — SeaDrop 3-phase drop config + ERC-2981 royalty (OWNER)
    //
    // multiConfigure pushes the PUBLIC drop stage + allowlist merkle root
    // on-chain (the SeaDrop surface). The artists (1h) and allowlist (2h)
    // windows are server-signed / merkle-gated stages the SeaDrop backend
    // enforces off-chain using the SAME price (0.0069 ETH), feeBps, and
    // per-wallet cap (2). Exact phase timestamps + allowlist root are ops
    // inputs (env). maxSupply is the hard on-chain cap (3943).
    // ─────────────────────────────────────────────────────────────────────

    function runConfigureSeaDrop() external {
        CXRDSPacks packs = _packs();

        // All SeaDrop/royalty env reads + struct assembly happen inside the
        // helpers below so their locals never occupy this function's stack.
        // Only `packs`, `cfg`, `royalty`, and `ownerKey` are alive across the
        // broadcast, keeping the body under the legacy-pipeline stack-depth
        // limit (no --via-ir; the size-assertion test depends on the legacy
        // pipeline). Behavior is identical: same env var names, same requires,
        // same multiConfigure + setRoyaltyInfo calls, same console.log output.
        ERC721SeaDropStructsErrorsAndEvents.MultiConfigureStruct memory cfg = _buildConfig();
        ISeaDropTokenContractMetadata.RoyaltyInfo memory royalty = _buildRoyalty();

        uint256 ownerKey = vm.envUint("OWNER_PRIVATE_KEY");

        vm.startBroadcast(ownerKey);
        packs.multiConfigure(cfg);
        packs.setRoyaltyInfo(royalty);
        vm.stopBroadcast();

        console.log("SeaDrop configured. maxSupply:", packs.maxSupply());
        console.log("  price (wei):                ", MINT_PRICE);
        console.log("  per-wallet cap:             ", uint256(MAX_PER_WALLET));
        console.log("  royalty recipient:          ", royalty.royaltyAddress);
        console.log("  royalty bps:                ", uint256(royalty.royaltyBps));
    }

    /**
     * @notice Read the SeaDrop env vars, run the input requires, and assemble
     *         the `MultiConfigureStruct` for the public drop stage + allowlist
     *         root. Reads env internally (rather than taking params) so its
     *         ~10 locals stay off `runConfigureSeaDrop`'s stack — the fix for
     *         the legacy-pipeline "Stack too deep" overflow at the broadcast.
     */
    function _buildConfig()
        internal
        returns (ERC721SeaDropStructsErrorsAndEvents.MultiConfigureStruct memory cfg)
    {
        address seaDropAddress = vm.envOr("SEADROP_ADDRESS", CANONICAL_SEADROP);
        string memory baseURI = vm.envString("BASE_URI");
        string memory contractURI = vm.envString("CONTRACT_URI");
        uint256 publicStart = vm.envUint("PUBLIC_START");
        uint256 publicEnd = vm.envUint("PUBLIC_END");
        bytes32 allowListRoot = vm.envBytes32("ALLOWLIST_ROOT");
        string memory allowListURI = vm.envString("ALLOWLIST_URI");
        address creatorPayout = vm.envAddress("CREATOR_PAYOUT");
        address feeRecipient = vm.envAddress("FEE_RECIPIENT");
        uint256 feeBps = vm.envUint("FEE_BPS");

        require(creatorPayout != address(0), "CREATOR_PAYOUT not set");
        require(feeRecipient != address(0), "FEE_RECIPIENT not set");
        require(publicStart != 0 && publicEnd != 0, "public phase window not set");

        PublicDrop memory publicDrop = PublicDrop({
            mintPrice: uint80(MINT_PRICE),
            startTime: uint48(publicStart),
            endTime: uint48(publicEnd),
            maxTotalMintableByWallet: MAX_PER_WALLET,
            feeBps: uint16(feeBps),
            restrictFeeRecipients: true
        });

        AllowListData memory allowListData = AllowListData({
            merkleRoot: allowListRoot,
            publicKeyURIs: new string[](0),
            allowListURI: allowListURI
        });

        address[] memory allowedFeeRecipients = new address[](1);
        allowedFeeRecipients[0] = feeRecipient;

        cfg = ERC721SeaDropStructsErrorsAndEvents.MultiConfigureStruct({
            maxSupply: MAX_SUPPLY,
            baseURI: baseURI,
            contractURI: contractURI,
            seaDropImpl: seaDropAddress,
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

    /**
     * @notice Read the ERC-2981 royalty env vars and assemble the `RoyaltyInfo`
     *         struct. Split out of `runConfigureSeaDrop` (alongside
     *         `_buildConfig`) so the royalty locals die before the broadcast.
     */
    function _buildRoyalty()
        internal
        returns (ISeaDropTokenContractMetadata.RoyaltyInfo memory royalty)
    {
        address royaltyRecipient = vm.envAddress("ROYALTY_RECIPIENT");
        uint256 royaltyBps = vm.envUint("ROYALTY_BPS");

        royalty = ISeaDropTokenContractMetadata.RoyaltyInfo({
            royaltyAddress: royaltyRecipient,
            royaltyBps: uint96(royaltyBps)
        });
    }

    // ─────────────────────────────────────────────────────────────────────
    // Step 5 — two-step ownership transfer to the partner wallet (OWNER).
    // Partner must then call acceptOwnership() (TwoStepOwnable).
    // ─────────────────────────────────────────────────────────────────────

    function runTransferOwnership() external {
        CXRDSPacks packs = _packs();
        uint256 ownerKey = vm.envUint("OWNER_PRIVATE_KEY");
        address partner = vm.envAddress("PARTNER_OWNER");
        require(partner != address(0), "PARTNER_OWNER not set");

        vm.startBroadcast(ownerKey);
        packs.transferOwnership(partner);
        vm.stopBroadcast();

        console.log("Ownership transfer initiated to:", partner);
        console.log("Partner must call acceptOwnership() to complete (two-step).");
    }

    // ─────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────

    function _packs() internal view returns (CXRDSPacks) {
        address addr = vm.envAddress("CXRDS_PACKS");
        require(addr != address(0), "CXRDS_PACKS not set");
        return CXRDSPacks(addr);
    }
}
