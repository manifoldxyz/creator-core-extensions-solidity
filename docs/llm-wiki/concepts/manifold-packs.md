---
title: ManifoldPacksSeaDropShim (gasless rip — pack burn → cards)
created: 2026-07-16
updated: 2026-07-18
type: concept
package: manifold
tags: [contract, interface, struct, event, error, erc721, erc1155, seadrop, burn-redeem, signature, eip1271, config, collectible, pitfall]
sources: [manifold/contracts/manifoldpacks/ManifoldPacksSeaDropShim.sol, manifold/contracts/manifoldpacks/IManifoldPacksSeaDropShim.sol]
confidence: high
---

# ManifoldPacksSeaDropShim Packs (gasless rip — pack burn → cards)

A **dual-role** contract, unlike the shared-singleton extensions that dominate this repo (see [[repo-overview]]). `ManifoldPacksSeaDropShim` is at once (a) an **`ERC721SeaDrop` "pack" collection** sold as an ordinary SeaDrop drop, and (b) a **registered extension on a *separate* stock ERC1155 creator-core "cards" contract**. Its signature mechanic — "rip" — is a burn-to-redeem in spirit (compare [[burn-redeem]]), but inverted operationally: the collector never transacts. A backend `signer` submits **collector-signed EIP-712 `RipPermit`s**; the contract verifies the permit against the pack's current owner (EOA via ECDSA **or** smart-contract wallet via **EIP-1271**, through OpenZeppelin `SignatureChecker`), burns the pack, and mints that pack's cards to the owner. The flow is atomic and **gasless for the collector**. ^[manifold/contracts/manifoldpacks/ManifoldPacksSeaDropShim.sol#L45]

## Contract map

| File | Role |
|---|---|
| `manifoldpacks/ManifoldPacksSeaDropShim.sol` | The dual-role contract: `ERC721SeaDrop, EIP712, ICreatorExtensionTokenURI, IManifoldPacksSeaDropShim`. Holds pack supply, the rip flow, the owner-updatable `PackConfig`, and the card tokenURI surface ^[manifold/contracts/manifoldpacks/ManifoldPacksSeaDropShim.sol#L45] |
| `manifoldpacks/IManifoldPacksSeaDropShim.sol` | Interface: `PackConfig` + `RipOrder` structs, events (`Ripped`, `CardsInitialized`, `ConfigUpdated`, `RipSignatureRequirementUpdated`), and the full custom-error taxonomy ^[manifold/contracts/manifoldpacks/IManifoldPacksSeaDropShim.sol#L26] |

Constant (`ManifoldPacksSeaDropShim.sol`): `RIP_TYPEHASH = keccak256("RipPermit(uint256 packId,uint256 deadline)")`; `MAX_UINT_8 = 255` (the variation cap). **The card-side params are NOT constants** — `cardsPerPack`, `numberOfVariations`, `maxCardsSupply`, the rip window, and `cardsLocation` all live in the owner-updatable `PackConfig` (see below), mirroring the Serendipity claim initialize/update ideology ([[gacha-serendipity]]). There is **no `MAX_PACKS` constant** — the pack cap is SeaDrop's own `maxSupply`. ^[manifold/contracts/manifoldpacks/ManifoldPacksSeaDropShim.sol#L67]

State: `creatorContractAddress` (the ERC1155 cards core — **set once at `initializeCards`**, zero until then, NOT a constructor immutable), `startingCardTokenId` (first reserved card id, `0` until `initializeCards`), `signer`, `mintedCards` (running total of card units minted, for the supply cap), `ripSignatureRequired` (the break-glass switch, `internal`, defaults `true` — no external getter; the per-rip `signatureVerified` event flag records state off-chain), and the internal `_config` (read via `getConfig()`). ^[manifold/contracts/manifoldpacks/ManifoldPacksSeaDropShim.sol#L74]

## The `PackConfig` struct — owner-updatable card params

```solidity
struct PackConfig {
    uint256 maxCardsSupply;      // 0 == unlimited; cannot be set below mintedCards
    uint256 cardsPerPack;        // sum(RipOrder.amounts) must equal this; > 0
    uint256 numberOfVariations;  // contiguous ids reserved on the cards core; > 0, <= 255; raise-only
    uint256 ripStartDate;        // inclusive lower rip gate
    uint256 ripEndDate;          // 0 == no end; else must be > ripStartDate
    string  cardsLocation;       // folder-pattern base URI for card metadata (ignored when tokenURIExtension set)
    address tokenURIExtension;    // 0 == use cardsLocation folder pattern; else delegate tokenURI to this ICreatorExtensionTokenURI
}
```
^[manifold/contracts/manifoldpacks/IManifoldPacksSeaDropShim.sol#L51]

Set once at `initializeCards(cardsCreator, config)` and mutated via `updateConfig(config)` (both `onlyOwner`). `numberOfVariations` is **fixed at init** — `updateConfig` reverts `CannotChangeVariations` if it differs (mirrors Serendipity's `CannotChangeTokenVariations`); `cardsPerPack`, the rip window, `cardsLocation`, and `tokenURIExtension` stay freely updatable; `maxCardsSupply` can't drop below `mintedCards`. This replaces the old `CARDS_PER_PACK` / `NUM_CARD_DESIGNS` constants and the standalone `setRipStart` / `setCardsLocation` setters (all removed). **The cards-core address is a parameter of `initializeCards`, not the constructor** — the pack contract can be deployed before the cards core exists. ^[manifold/contracts/manifoldpacks/ManifoldPacksSeaDropShim.sol#L145]

## The `RipOrder` struct (`IManifoldPacksSeaDropShim.sol`)

```solidity
struct RipOrder {
    uint256   packId;    // ERC721 pack tokenId to rip (burn); also the replay lock
    uint256[] cardIds;   // card variation ids to mint — bound to the committed leaf
    uint256[] amounts;   // per-cardIds unit counts; sum MUST equal config.cardsPerPack
    uint256   deadline;  // unix ts after which the order reverts PermitExpired
    bytes     signature; // collector's sig over the typed payload (ECDSA OR EIP-1271 blob)
    bytes32   salt;      // per-pack CSPRNG salt in the committed leaf (surprise-until-burn)
    bytes32[] proof;     // Merkle proof of the pack's committed (packId,cardIds,amounts,salt) leaf
}
```
^[manifold/contracts/manifoldpacks/IManifoldPacksSeaDropShim.sol#L92]

The signed EIP-712 payload is only `RipPermit(uint256 packId, uint256 deadline)` — **`cardIds`/`amounts` are not part of the collector's signature**, but they are **NO LONGER free backend choice**: they are bound to the frozen `contentsRoot` via `salt`+`proof` (see the Contents commitment section). On-chain they are still also validated by the range check + `sum(amounts) == cardsPerPack`. `cardIds`/`amounts` are **dynamic arrays** (a pack may contain **duplicate variations** — e.g. `cardIds=[A,B,C]`, `amounts=[2,1,1]` for a 4-card pack). ^[manifold/contracts/manifoldpacks/IManifoldPacksSeaDropShim.sol#L60]

## Contents commitment (the F1 fix — Merkle delivery check)

`deliverBatch` gates each rip on a **Merkle-root contents commitment**, closing the finding that a compromised `signer` could deliver arbitrary in-range cards. Each pack's exact contents are committed as a leaf `keccak256(abi.encode(packId, cardIds, amounts, salt))`; the order carries the `salt`+`proof`, and the contract computes the leaf from the SAME `order.packId`/`cardIds`/`amounts`/`salt` and requires `MerkleProof.verify(order.proof, contentsRoot, leaf)` → else `ContentsMismatch`. If `contentsRoot == bytes32(0)`, `deliverBatch` reverts `ContentsNotSeeded` (the contract refuses to rip until a commitment exists). ^[manifold/contracts/manifoldpacks/ManifoldPacksSeaDropShim.sol#L318]

- **`abi.encode` (NOT `encodePacked`) is load-bearing.** It is canonical/injective over the typed tuple; `encodePacked` would open the adjacent-dynamic-array boundary-shift collision between `cardIds` and `amounts`. Do not "optimize" it.
- **`packId` is inside the leaf.** The same `order.packId` field feeds `ownerOf`, the permit digest, the leaf, and `_burn` — so pack X's committed cards cannot be delivered against pack Y (cross-pack swap → `ContentsMismatch`).
- **Hash convention.** Leaves are **single-hashed**; internal nodes use OZ `MerkleProof`'s sorted-pair commutative `_hashPair`. Off-chain tree builders must match (the test suite uses murky's `Merkle`, whose `hashLeafPairs` sorts ascending — same convention; `test_happyPath_realProof` proves a real murky proof verifies on-chain, the anti-bricking check).
- **`salt`** blinds each leaf so a pack's contents can't be brute-forced from the sibling-leaf hashes that every burn's proof publishes (surprise-until-burn). Salt loss = that pack can never rip; salt leak = surprise lost, integrity intact.

**`seedContents(bytes32 root_) external onlyOwner`** sets/updates the root (reverts `CardsNotInitialized` before init — the sheet must use real post-init card ids), emits `ContentsSeeded`. **TRUST MODEL (deliberate):** the root binds the **`signer`**, not the **`owner`**. There is intentionally **NO `_totalMinted()==0` lock** — the owner may re-seed at any time (to correct a bad sheet / late card swap in a live drop), a trusted-owner power in the same class as `airdrop`/break-glass/metadata. Consequence: a compromised **signer** can only ever deliver each pack's committed cards or revert (cannot substitute/over-mint/misdeliver); a compromised **owner** can re-commit — accepted, monitorable via the `ContentsSeeded` event. Note: changing `cardsPerPack` without re-seeding bricks rips (committed `amounts` sums no longer match) until a matching re-seed — an operational responsibility, not a contract invariant. ^[manifold/contracts/manifoldpacks/ManifoldPacksSeaDropShim.sol#L225]

## External surface

- **`deliverBatch(RipOrder[] calldata orders) external nonReentrant`** — the only rip entrypoint. Callable **only by `signer`**, **only within `[ripStartDate, ripEndDate]`**. Iterates orders; per order verifies the permit (when required), burns the pack, mints the cards, emits `Ripped`. Atomic: any single failure reverts the whole batch. ^[manifold/contracts/manifoldpacks/ManifoldPacksSeaDropShim.sol#L265]
- **`initializeCards(address cardsCreator, PackConfig calldata config) external onlyOwner`** — one-time. Sets `creatorContractAddress` (reverts `InvalidCardsCreator` on zero), validates the config, calls `mintExtensionNew` with a `numberOfVariations`-length **zeros** amounts array (register-without-minting), records `startingCardTokenId = ids[0]` and stores the config. Reverts `CardsAlreadyInitialized` if already initialized. ^[manifold/contracts/manifoldpacks/ManifoldPacksSeaDropShim.sol#L145]
- **`updateConfig(PackConfig calldata config) external onlyOwner`** — Serendipity-style update: `numberOfVariations` is **fixed** (reverts `CannotChangeVariations` if changed); `maxCardsSupply` cannot drop below `mintedCards`; `cardsPerPack`, the rip window, and `cardsLocation` are freely updatable. ^[manifold/contracts/manifoldpacks/ManifoldPacksSeaDropShim.sol#L176]
- **`setSigner(address) / setRipSignatureRequired(bool) external onlyOwner`** — signer rotation; the break-glass switch (see below). ^[manifold/contracts/manifoldpacks/ManifoldPacksSeaDropShim.sol#L224]
- **`updateTransfersPaused(bool) external onlyOwner`** — pause/unpause SECONDARY pack transfers (owner "stop trading" switch). While paused, `transferFrom`/`safeTransferFrom` between non-zero addresses, `approve`, and `setApprovalForAll` revert `TransfersPaused`; **mint and the rip burn are never blocked**. Adapts OpenSea's `ERC721SeaDropPausable` with two deliberate divergences: **defaults to `false`/unpaused** (upstream defaults paused, which would brick the intentional sealed-pack secondary market on deploy) and the pause is **scoped to secondary moves** via the `_beforeTokenTransfers` `from != 0 && to != 0` guard (upstream reverts on any `from != 0`, blocking burns too). Emits `TransfersPausedChanged`. ^[manifold/contracts/manifoldpacks/ManifoldPacksSeaDropShim.sol#L247]
- **`airdrop(address[] calldata recipients, uint256[] calldata cardIds, uint256[] calldata amounts) external onlyOwner nonReentrant`** — owner escape hatch that mints reserved card variations **directly**, bypassing the pack-burn rip flow (corrections, giveaways, partner allocations). Parallel arrays: `recipients[i]` gets `amounts[i]` of `cardIds[i]`; all three lengths must be equal and non-zero, every `cardIds[i]` must be in the reserved range (else `InvalidCardIds`), reverts `CardsNotInitialized` before init and `InvalidAirdrop` on empty/mismatched arrays. Emits `Airdropped`. **Deliberately independent of the rip budget** — does NOT touch `mintedCards` / `config.maxCardsSupply` (those govern rip output = packs × cardsPerPack; coupling an airdrop in could starve unripped packs of cap headroom and make them un-rippable). No rip-window gate. Diverges from the reference lazy-claim `airdrop`, which counts toward the claim total and auto-raises the max. ^[manifold/contracts/manifoldpacks/ManifoldPacksSeaDropShim.sol#L298]
- **`getConfig() external view returns (PackConfig)`** — read the current card config. ^[manifold/contracts/manifoldpacks/ManifoldPacksSeaDropShim.sol#L215]
- **`tokenURI(address creator, uint256 tokenId) external view override returns (string)`** — the **card** (`ICreatorExtensionTokenURI`) surface delegated by the cards core. When `config.tokenURIExtension` is set (non-zero) it delegates verbatim to `ICreatorExtensionTokenURI(tokenURIExtension).tokenURI(creator, tokenId)` (mirrors lazy-claim's `StorageProtocol.ADDRESS` delegation — points metadata at an on-chain renderer / resolver without redeploying); otherwise it serves folder-pattern `cardsLocation + (tokenId - startingCardTokenId + 1)`, so the first reserved variation maps to `.../1`. **The pack (ERC721A/SeaDrop) `tokenURI` is NOT overridden** — packs use stock `ERC721ContractMetadata`/SeaDrop metadata. ^[manifold/contracts/manifoldpacks/ManifoldPacksSeaDropShim.sol#L347]
- `supportsInterface` adds `type(ICreatorExtensionTokenURI).interfaceId` on top of the ERC721SeaDrop surface. ^[manifold/contracts/manifoldpacks/ManifoldPacksSeaDropShim.sol#L363]

## The RipPermit consent model (no nonces — the burn IS the lock)

Per order in `deliverBatch`: ^[manifold/contracts/manifoldpacks/ManifoldPacksSeaDropShim.sol#L280]

1. `PermitExpired` if `block.timestamp > order.deadline`.
2. `address packOwner = ownerOf(order.packId)` — a burned/nonexistent pack **reverts ERC721A's `OwnerQueryForNonexistentToken`** (the replay lock).
3. **If `ripSignatureRequired`** (default): `SignatureChecker.isValidSignatureNow(packOwner, digest, order.signature)` where `digest = _hashTypedDataV4(keccak256(abi.encode(RIP_TYPEHASH, packId, deadline)))`. `false` → `InvalidPermit`. This validates **both** EOA ECDSA signatures **and** EIP-1271 contract-wallet signatures. ^[manifold/contracts/manifoldpacks/ManifoldPacksSeaDropShim.sol#L291]
4. Validate `cardIds`/`amounts`: matched non-empty lengths, every id in `[startingCardTokenId, startingCardTokenId + numberOfVariations)`, and `sum(amounts) == cardsPerPack` → else `InvalidCardAmounts` / `InvalidCardIds`.
5. **Contents commitment:** `MerkleProof.verify(order.proof, contentsRoot, keccak256(abi.encode(packId, cardIds, amounts, salt)))` → else `ContentsMismatch`. (The whole batch also reverts `ContentsNotSeeded` up front if `contentsRoot == bytes32(0)`.)
6. Enforce `mintedCards + sum <= maxCardsSupply` (when the cap is non-zero) → else `MaxCardsSupplyExceeded`; bump `mintedCards`.
7. `_burn(packId)`, then `mintExtensionExisting(to=[packOwner], cardIds, amounts)`; emit `Ripped(packId, packOwner, cardIds, amounts, ripSignatureRequired)`.

**There are NO nonces and no burn-credit ledger.** Replay is structural: a used permit's pack is burned, so `ownerOf` reverts and it can never be redeemed twice. ^[manifold/contracts/manifoldpacks/ManifoldPacksSeaDropShim.sol#L285]

## Break-glass signature off-switch + per-rip flag

`ripSignatureRequired` (public bool, defaults **true**) is togglable by the owner via `setRipSignatureRequired(bool)`. When **false**, `deliverBatch` **skips permit verification entirely** — the trusted `signer` alone authorizes the burn (it still burns `ownerOf(packId)`'s pack and mints to that owner). This is a **break-glass** mode: with it off, a compromised signer key can rip any pack. The `Ripped` event carries a **`signatureVerified` bool** (= the value of `ripSignatureRequired` at rip time) so off-chain consumers can tell which rips were signature-verified vs signer-authorized. ^[manifold/contracts/manifoldpacks/ManifoldPacksSeaDropShim.sol#L240]

## Error taxonomy (verbatim from `IManifoldPacksSeaDropShim.sol`)

| Error | Reverts when |
|---|---|
| `OnlySigner()` | `deliverBatch` called by any address other than `signer` ^[manifold/contracts/manifoldpacks/IManifoldPacksSeaDropShim.sol#L159] |
| `RipNotStarted()` | called before `config.ripStartDate` ^[manifold/contracts/manifoldpacks/IManifoldPacksSeaDropShim.sol#L164] |
| `RipEnded()` | called after a non-zero `config.ripEndDate` ^[manifold/contracts/manifoldpacks/IManifoldPacksSeaDropShim.sol#L170] |
| `PermitExpired()` | an order's `deadline` has passed ^[manifold/contracts/manifoldpacks/IManifoldPacksSeaDropShim.sol#L176] |
| `InvalidPermit()` | `ripSignatureRequired` and the signature fails `SignatureChecker` against the owner — **one error** for malformed, forged, non-owner, and stale-after-transfer (replaces the old `InvalidSignature`/`PermitSignerNotOwner` split) ^[manifold/contracts/manifoldpacks/IManifoldPacksSeaDropShim.sol#L188] |
| `InvalidCardAmounts()` | `cardIds`/`amounts` lengths differ or are zero, or `sum(amounts) != cardsPerPack` ^[manifold/contracts/manifoldpacks/IManifoldPacksSeaDropShim.sol#L195] |
| `InvalidCardIds()` | any card id outside `[startingCardTokenId, startingCardTokenId + numberOfVariations)` ^[manifold/contracts/manifoldpacks/IManifoldPacksSeaDropShim.sol#L202] |
| `MaxCardsSupplyExceeded()` | a rip would push `mintedCards` past a non-zero `maxCardsSupply` ^[manifold/contracts/manifoldpacks/IManifoldPacksSeaDropShim.sol#L208] |
| `InvalidConfig()` | `numberOfVariations == 0` or `> 255`, or `cardsPerPack == 0` ^[manifold/contracts/manifoldpacks/IManifoldPacksSeaDropShim.sol#L214] |
| `InvalidDate()` | `ripEndDate != 0 && ripStartDate >= ripEndDate` ^[manifold/contracts/manifoldpacks/IManifoldPacksSeaDropShim.sol#L221] |
| `CannotChangeVariations()` | `updateConfig` changes `numberOfVariations` (fixed at init) ^[manifold/contracts/manifoldpacks/IManifoldPacksSeaDropShim.sol#L228] |
| `InvalidCardsCreator()` | `initializeCards` given a zero cards-core address ^[manifold/contracts/manifoldpacks/IManifoldPacksSeaDropShim.sol#L234] |
| `CannotLowerMaxBeyondMinted()` | `updateConfig` sets `maxCardsSupply` below `mintedCards` ^[manifold/contracts/manifoldpacks/IManifoldPacksSeaDropShim.sol#L241] |
| `CardsAlreadyInitialized()` / `CardsNotInitialized()` | double `initializeCards`, or `updateConfig`/`seedContents` before init ^[manifold/contracts/manifoldpacks/IManifoldPacksSeaDropShim.sol#L251] |
| `ContentsNotSeeded()` | `deliverBatch` called while `contentsRoot == bytes32(0)` ^[manifold/contracts/manifoldpacks/IManifoldPacksSeaDropShim.sol#L296] |
| `ContentsMismatch()` | an order's `(cardIds, amounts, salt)` do not hash to a committed leaf for `packId` (Merkle proof fails) ^[manifold/contracts/manifoldpacks/IManifoldPacksSeaDropShim.sol#L305] |
| `TransfersPaused()` | a secondary transfer (`from != 0 && to != 0`), `approve`, or `setApprovalForAll` while `transfersPaused` is true — NEVER on mint or the rip burn ^[manifold/contracts/manifoldpacks/IManifoldPacksSeaDropShim.sol#L307] |

Pinned `deliverBatch` error order: `OnlySigner → RipNotStarted → RipEnded → ContentsNotSeeded → PermitExpired → [ownerOf revert] → InvalidPermit → InvalidCardAmounts → InvalidCardIds → ContentsMismatch → MaxCardsSupplyExceeded`. ^[manifold/contracts/manifoldpacks/ManifoldPacksSeaDropShim.sol#L260]

## Pitfalls

- **`CardsAlreadyInitialized` is named to dodge an inherited collision.** Deliberately NOT `AlreadyInitialized`, because `ConstructorInitializable.AlreadyInitialized()` already exists up the ERC721SeaDrop chain. ^[manifold/contracts/manifoldpacks/IManifoldPacksSeaDropShim.sol#L247]
- **Signature verification is `SignatureChecker`, not raw `ecrecover`.** This is USDC/EIP-2612-grade (rejects malleable/`address(0)` results) **and** transparently supports EIP-1271, so **Safe/smart-contract-wallet holders CAN rip** — the earlier "EOA-only" limitation is gone. ^[manifold/contracts/manifoldpacks/ManifoldPacksSeaDropShim.sol#L295]
- **`registerExtension` is a cards-core ADMIN action, not self-callable.** The 2-arg `registerExtension(extension, "")` overload is performed by the cards-core admin and sequenced by the deploy runbook (before `initializeCards`). ^[manifold/contracts/manifoldpacks/ManifoldPacksSeaDropShim.sol#L38]
- **`initializeCards` reserves ids by minting *zero* amounts.** The amounts array is all zeros — `mintExtensionNew` registers new tokenIds without minting units; units are minted on demand at rip time. ^[manifold/contracts/manifoldpacks/ManifoldPacksSeaDropShim.sol#L152]
- **`numberOfVariations` is capped at 255.** The uint8 variation cap (`MAX_UINT_8`) is enforced at init and on raise — raising past 255 reverts `InvalidConfig`. ^[manifold/contracts/manifoldpacks/ManifoldPacksSeaDropShim.sol#L207]
- **`startingCardTokenId == 0` is the uninitialized sentinel.** Creator-core ids start at 1, so `0` safely doubles as "not yet initialized". ^[manifold/contracts/manifoldpacks/ManifoldPacksSeaDropShim.sol#L67]
- **Merkle leaf/tree hash convention must match OZ, or every rip bricks.** Leaves are single-hashed `keccak256(abi.encode(packId, cardIds, amounts, salt))`; internal nodes use OZ `MerkleProof`'s sorted-pair `_hashPair`. An off-chain builder that double-hashes leaves (OZ `StandardMerkleTree` default) or hashes pairs unsorted will produce proofs that ALL revert `ContentsMismatch`. End-to-end test one real proof against the deployed verifier before mint (the in-suite `test_happyPath_realProof` does this with murky). ^[manifold/contracts/manifoldpacks/ManifoldPacksSeaDropShim.sol#L318]
- **The contents root is owner-mutable (no pre-mint lock).** `seedContents` has no `_totalMinted()==0` gate — the owner can re-seed any time. This binds the *signer* (can't substitute contents), NOT the *owner* (already trusted). Changing `cardsPerPack` without a matching re-seed bricks all rips until re-seeded. ^[manifold/contracts/manifoldpacks/ManifoldPacksSeaDropShim.sol#L225]
- **The transfer pause is SECONDARY-only and defaults OFF — do not model it on upstream `ERC721SeaDropPausable`.** Two divergences from OpenSea's contract are load-bearing: (1) `transfersPaused` defaults to `false` (upstream defaults `true`, which would brick sealed-pack secondary trading the instant you deploy), and (2) `_beforeTokenTransfers` gates on `from != 0 && to != 0` (upstream reverts on any `from != 0`). Without the `to != 0` carve-out an active pause would revert the rip's `_burn` and brick every collector's rip. Mint and rip must always flow; only wallet-to-wallet moves are pausable. ^[manifold/contracts/manifoldpacks/ManifoldPacksSeaDropShim.sol#L505]

## Open questions

- SeaDrop mint economics (price, per-wallet caps, phases) are configured through the inherited `ERC721SeaDrop` drop parameters, not in this file. `getMintStats` reads the real ERC721A counters.

Related: [[repo-overview]], [[burn-redeem]], [[gacha-serendipity]], [[collectible]], [[shared-libraries]]
