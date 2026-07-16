---
title: CXRDS Packs (gasless rip — pack burn → 4 cards)
created: 2026-07-16
updated: 2026-07-16
type: concept
package: manifold
tags: [contract, interface, struct, event, error, erc721, erc1155, seadrop, burn-redeem, signature, collectible, pitfall]
sources: [manifold/contracts/cxrds/CXRDSPacks.sol, manifold/contracts/cxrds/ICXRDSPacks.sol]
confidence: high
---

# CXRDS Packs (gasless rip — pack burn → 4 cards)

A **dual-role** contract, unlike the shared-singleton extensions that dominate this repo (see [[repo-overview]]). `CXRDSPacks` is at once (a) an **`ERC721SeaDrop` "pack" collection** sold as an ordinary SeaDrop drop, and (b) a **registered extension on a *separate* stock ERC1155 creator-core "cards" contract**. Its signature mechanic — "rip" — is a burn-to-redeem in spirit (compare [[burn-redeem]]), but inverted operationally: the collector never transacts. A backend `signer` submits **collector-signed EIP-712 `RipPermit`s**; the contract verifies the permit signer is the pack's current owner, burns the pack, and mints exactly four cards to that owner. The flow is atomic and **gasless for the collector**. ^[manifold/contracts/cxrds/CXRDSPacks.sol#L45]

## Contract map

| File | Role |
|---|---|
| `cxrds/CXRDSPacks.sol` | The dual-role contract: `ERC721SeaDrop, EIP712, ICreatorExtensionTokenURI, ICXRDSPacks`. Holds pack supply, the rip flow, card init, and both tokenURI surfaces ^[manifold/contracts/cxrds/CXRDSPacks.sol#L45] |
| `cxrds/ICXRDSPacks.sol` | Interface: `RipOrder` struct, events (`Ripped`, `SignerUpdated`, `RipStartUpdated`, `CardsLocationUpdated`), and the full custom-error taxonomy ^[manifold/contracts/cxrds/ICXRDSPacks.sol#L18] |

Key constants (`CXRDSPacks.sol`): `MAX_PACKS = 3943` (SeaDrop max supply), `CARDS_PER_PACK = 4`, `NUM_CARD_DESIGNS = 251` (contiguous card variation ids reserved on the cards core), `RIP_TYPEHASH = keccak256("RipPermit(uint256 packId,uint256 deadline)")`. ^[manifold/contracts/cxrds/CXRDSPacks.sol#L47]

State: `creatorContractAddress` (immutable — the ERC1155 cards core), `startingCardTokenId` (first reserved card id, `0` until `initializeCards`), `signer`, `ripStart`, `cardsLocation`. ^[manifold/contracts/cxrds/CXRDSPacks.sol#L62]

## The `RipOrder` struct (`ICXRDSPacks.sol`)

```solidity
struct RipOrder {
    uint256 packId;        // ERC721 pack tokenId to rip (burn); also the replay lock
    uint256[4] cardIds;    // four ERC1155 card variation ids to mint — relay data, NOT signed
    uint256 deadline;      // unix ts after which the order reverts PermitExpired
    uint8 v; bytes32 r; bytes32 s;  // collector's ecrecover signature over the typed payload
}
```
^[manifold/contracts/cxrds/ICXRDSPacks.sol#L44]

The signed EIP-712 payload is only `RipPermit(uint256 packId, uint256 deadline)` — **`cardIds` are chosen by the backend and validated on-chain (range check), not signed**; they are relay data, not part of the collector's authorization. `cardIds` is a **fixed-length `[4]`** so the "wrong count" case cannot exist at runtime — it is a compile-time guarantee. ^[manifold/contracts/cxrds/ICXRDSPacks.sol#L22]

## External surface

- **`deliverBatch(RipOrder[] calldata orders) external nonReentrant`** — the only rip entrypoint. Callable **only by `signer`**, **only after `ripStart`**. Iterates orders; per order verifies the permit, burns the pack, mints 4 cards, emits `Ripped`. Atomic: any single failure reverts the whole batch. ^[manifold/contracts/cxrds/CXRDSPacks.sol#L180]
- **`initializeCards() external onlyOwner`** — one-time. Calls `IERC1155CreatorCore(creatorContractAddress).mintExtensionNew(to, amounts, uris)` with a 251-length **zeros** amounts array (register-without-minting) and an empty uris array, then records `startingCardTokenId = ids[0]`. Reverts `CardsAlreadyInitialized` if `startingCardTokenId != 0`. ^[manifold/contracts/cxrds/CXRDSPacks.sol#L117]
- **`tokenURI(uint256 tokenId) public view override returns (string)`** — the **pack** (ERC721A/SeaDrop) surface: returns `_baseURI()` verbatim for every existing pack (one shared sealed-pack image); reverts `URIQueryForNonexistentToken` otherwise. ^[manifold/contracts/cxrds/CXRDSPacks.sol#L250]
- **`tokenURI(address, uint256 tokenId) external view override returns (string)`** — the **card** (`ICreatorExtensionTokenURI`) surface delegated by the cards core: folder-pattern `cardsLocation + (tokenId - startingCardTokenId + 1)`, so the first reserved variation maps to `.../1`. ^[manifold/contracts/cxrds/CXRDSPacks.sol#L270]
- Admin setters (`onlyOwner`): `setSigner`, `setRipStart`, `setCardsLocation` — each emits its paired event. ^[manifold/contracts/cxrds/CXRDSPacks.sol#L137]
- `supportsInterface` adds `type(ICreatorExtensionTokenURI).interfaceId` on top of the ERC721SeaDrop surface. ^[manifold/contracts/cxrds/CXRDSPacks.sol#L286]

## The EIP-712 RipPermit consent model (no nonces — the burn IS the lock)

A single atomic `deliverBatch` call, per order: ^[manifold/contracts/cxrds/CXRDSPacks.sol#L180]

1. `_hashTypedDataV4(keccak256(abi.encode(RIP_TYPEHASH, order.packId, order.deadline)))` builds the digest; `recovered = ecrecover(digest, v, r, s)`. If `recovered == address(0)` → `InvalidSignature` (malformed sig only). ^[manifold/contracts/cxrds/CXRDSPacks.sol#L193]
2. `address owner = ownerOf(order.packId)` — for a burned/nonexistent pack this **reverts ERC721A's `OwnerQueryForNonexistentToken`**. If `recovered != owner` → `PermitSignerNotOwner`. ^[manifold/contracts/cxrds/CXRDSPacks.sol#L203]
3. Range-check all four `cardIds` against `[startingCardTokenId, startingCardTokenId + NUM_CARD_DESIGNS)` → else `InvalidCardIds`. ^[manifold/contracts/cxrds/CXRDSPacks.sol#L207]
4. `_burn(order.packId)`, then `mintExtensionExisting(to=[owner], tokenIds=cardIds, amounts=[1,1,1,1])` on the cards core; emit `Ripped`. ^[manifold/contracts/cxrds/CXRDSPacks.sol#L218]

**There are NO nonces and no burn-credit ledger.** Replay/idempotency is enforced *structurally*: a used permit's pack has been burned, so its `ownerOf(packId)` reverts and the permit can never be redeemed a second time. The burn itself is the replay lock — the standard nonce mapping other signature families use (compare [[collectible]], which binds each ECDSA sig to `(msg.sender, nonce)`) is deliberately absent here. ^[manifold/contracts/cxrds/CXRDSPacks.sol#L167]

## Error taxonomy (verbatim from `ICXRDSPacks.sol`)

| Error | Reverts when |
|---|---|
| `OnlySigner()` | `deliverBatch` called by any address other than the configured `signer` ^[manifold/contracts/cxrds/ICXRDSPacks.sol#L89] |
| `RipNotStarted()` | `deliverBatch` called before `ripStart` ^[manifold/contracts/cxrds/ICXRDSPacks.sol#L94] |
| `PermitExpired()` | an order's `deadline` has passed (`block.timestamp > deadline`) ^[manifold/contracts/cxrds/ICXRDSPacks.sol#L100] |
| `InvalidSignature()` | **only** when `ecrecover` returns `address(0)` (malformed `v` / out-of-range `s`). A well-formed sig recovering to the wrong address does NOT hit this ^[manifold/contracts/cxrds/ICXRDSPacks.sol#L110] |
| `PermitSignerNotOwner()` | recovered signer is not the pack's current owner — covers every "well-formed sig, wrong signer" case (forgery, non-owner, stale after transfer) ^[manifold/contracts/cxrds/ICXRDSPacks.sol#L121] |
| `InvalidCardIds()` | any of the four `cardIds` is outside `[startingCardTokenId, startingCardTokenId + NUM_CARD_DESIGNS)` ^[manifold/contracts/cxrds/ICXRDSPacks.sol#L128] |
| `CardsAlreadyInitialized()` | `initializeCards()` called more than once (`startingCardTokenId` already set) ^[manifold/contracts/cxrds/ICXRDSPacks.sol#L138] |

Pinned error order for `deliverBatch` (matters for tests): `OnlySigner → RipNotStarted → PermitExpired → InvalidSignature → [ownerOf revert] → PermitSignerNotOwner → InvalidCardIds`. ^[manifold/contracts/cxrds/CXRDSPacks.sol#L172]

## Pitfalls

- **`CardsAlreadyInitialized` is named to dodge an inherited collision.** It is deliberately NOT called `AlreadyInitialized`, because `ConstructorInitializable.AlreadyInitialized()` already exists up the ERC721SeaDrop inheritance chain — a same-named error would collide. ^[manifold/contracts/cxrds/ICXRDSPacks.sol#L134]
- **OZ `EIP712` is imported from node_modules, not `lib/openzeppelin-contracts`.** The import is `@openzeppelin/contracts/utils/cryptography/EIP712.sol`, and `packages/manifold/remappings.txt` only remaps the *un-scoped* `openzeppelin-contracts/=lib/openzeppelin-contracts/` — there is **no remapping for the `@openzeppelin/contracts/` prefix**, so it resolves through node_modules' `@openzeppelin/contracts`, a different copy from the Foundry submodule under `lib/`. Don't assume the two are the same version. ^[manifold/contracts/cxrds/CXRDSPacks.sol#L5]
- **EIP-1271 / Safe smart-wallet holders cannot rip in v1.** Signature verification is `ecrecover`-only (`CXRDSPacks.sol:196`); a contract wallet has no EOA key to recover, so its permits can never satisfy `recovered == owner`. This is an accepted **non-goal** for v1, not a bug. ^[manifold/contracts/cxrds/CXRDSPacks.sol#L196]
- **`registerExtension` is a cards-core ADMIN action, not self-callable.** Registering this contract as an extension on the cards core is the **2-arg `registerExtension(extension, "")`** overload, performed by the cards-core admin and sequenced by the deploy runbook (step 2, before `initializeCards`). `CXRDSPacks` never calls it on itself. ^[manifold/contracts/cxrds/CXRDSPacks.sol#L38]
- **`initializeCards` reserves ids by minting *zero* amounts.** The 251-length amounts array is all zeros — `mintExtensionNew` registers 251 new tokenIds without minting any units, then card units are minted on demand at rip time via `mintExtensionExisting`. ^[manifold/contracts/cxrds/CXRDSPacks.sol#L122]
- **`startingCardTokenId == 0` is the uninitialized sentinel.** Creator-core token ids start at 1, so `0` safely doubles as "not yet initialized" — but every card range/URI computation is meaningless until `initializeCards` runs. ^[manifold/contracts/cxrds/CXRDSPacks.sol#L64]

## Open questions

- SeaDrop mint economics (price, per-wallet caps, phases) are configured through the inherited `ERC721SeaDrop` / SeaDrop drop parameters, not in this file — not covered here. `getMintStats` reads the real ERC721A counters (per the contract NatSpec) but the SeaDrop base was not read this run.
- Whether the cards core's `mintExtensionNew`/`mintExtensionExisting` enforce their own admin/extension checks (they should, as this contract must be a registered extension) was inferred from the creator-core model, not read from creator-core source this run.

Related: [[repo-overview]], [[burn-redeem]], [[collectible]], [[shared-libraries]]
