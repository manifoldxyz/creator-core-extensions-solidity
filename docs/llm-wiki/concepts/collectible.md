---
title: Collectible
created: 2026-07-15
updated: 2026-07-15
type: concept
package: manifold
tags: [contract, abstract, interface, collectible, erc721, signature, membership, fee, struct, pitfall]
sources: [manifold/contracts/collectible/CollectibleCore.sol, manifold/contracts/collectible/ERC721Collectible.sol, manifold/contracts/collectible/ICollectibleCore.sol, manifold/contracts/collectible/IERC721Collectible.sol]
confidence: high
---

# Collectible

## What it is

A **signature-gated paid drop** extension — a "Collection Drop" in the source. Unlike `[[lazy-payable-claim]]` (merkle allowlists), Collectible authorizes each mint with a **server-signed ECDSA message** bound to `msg.sender` and a one-time `nonce`. It supports a timed sale window with an optional **presale interval** (separate presale price/limits), an admin-only **premint** phase before activation, and an earlier free **claim** window. Shared singleton; instances keyed by `(creatorContractAddress, instanceId)`.

## Contract map

| File (relative to `packages/`) | Role |
|---|---|
| `manifold/contracts/collectible/CollectibleCore.sol` | `abstract` base: init, activation, signature/nonce validation, fee & membership, withdraw. Extends `AdminControl`. |
| `manifold/contracts/collectible/ERC721Collectible.sol` | Concrete ERC721: `premint`, `claim`, `purchase`, `_mint`, tokenURI, transfer-lock hook. |
| `manifold/contracts/collectible/ICollectibleCore.sol` | Core interface: `CollectibleInstance`/`CollectibleState`/param structs, events. |
| `manifold/contracts/collectible/IERC721Collectible.sol` | ERC721 interface + `Unveil` event. |

## Key structs (`collectible/ICollectibleCore.sol`)

- `ActivationParameters { uint48 startTime; duration; presaleInterval; claimStartTime; claimEndTime; }`
- `InitializationParameters { bool useDynamicPresalePurchaseLimit; uint16 transactionLimit, purchaseMax, purchaseLimit, presalePurchaseLimit; uint256 purchasePrice, presalePurchasePrice; address signingAddress; address payable paymentReceiver; }`
- `UpdateInitializationParameters { ... same minus signingAddress/paymentReceiver }`
- `CollectibleInstance` — full stored state (flags, limits, `purchaseCount`, timestamps, prices, `baseURI`, `paymentReceiver`).
- `CollectibleState` — read model exposing `purchaseRemaining`.

## External surface

Core (`collectible/CollectibleCore.sol`):
- `activate(address creatorContractAddress, uint256 instanceId, ActivationParameters)`
- `deactivate(address creatorContractAddress, uint256 instanceId)`
- `getCollectible(address creatorContractAddress, uint256 index) → CollectibleInstance`
- `updateInitializationParameters(address, uint256, UpdateInitializationParameters)`
- `updatePaymentReceiver(address, uint256, address payable)`
- `setMembershipAddress(address)` · `withdraw(address payable, uint256)` · `nonceUsed(address, uint256, bytes32) → bool`

ERC721 (`collectible/ERC721Collectible.sol`):
- `initializeCollectible(address, uint256, InitializationParameters)`
- `premint(address, uint256, uint16 amount)` **and** overloaded `premint(address, uint256, address[] addresses)`
- `claim(address, uint256, uint16 amount, bytes32 message, bytes signature, bytes32 nonce)` — `payable`
- `purchase(address, uint256, uint16 amount, bytes32 message, bytes signature, bytes32 nonce)` — `payable`
- `setTokenURIPrefix(address, uint256, string)` · `setTransferLocked(address, uint256, bool)`
- `state(address, uint256) → CollectibleState` · `purchaseRemaining(address, uint256) → uint16`
- `tokenURI(address, uint256)` · `setApproveTransfer(address, bool)` · `approveTransfer(address, address, address, uint256)`

## Distinctive mechanic

**Signed message binds sender + nonce.** `_validatePurchaseRequest` recomputes `keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n52", msg.sender, nonce))` (52 bytes) and requires `message.recover(signature) == signingAddress`. The **with-amount** variant (`\n54`, appends `uint16 amount`) is used for dynamic presale limits. Nonces are single-use per `(creator, instanceId)`.

**Three minting doors:**
- `premint` — admin-only, **before** `isActive`; seeds tokens with no payment.
- `claim` — signature-gated free mint inside `[claimStartTime, claimEndTime]`; caller pays only the Manifold fee (`msg.value == _getManifoldFee(amount)`).
- `purchase` — signature-gated paid mint after `startTime`; branches on presale (`_isPresale`) vs regular price and enforces `transactionLimit`/`purchaseLimit`/`presalePurchaseLimit`.

**Presale window:** `_isPresale` is true while `block.timestamp - startTime < presaleInterval`. `useDynamicPresalePurchaseLimit` switches presale to the amount-signed message path and skips static per-address counting.

**Transfer lock:** `setTransferLocked` + the `approveTransfer` hook can freeze secondary transfers until the sale ends (mints from `address(0)` always pass).

## Fee / membership handling

`MINT_FEE = 690000000000000` wei (0.00069 ETH). `_getManifoldFee(numTokens)` returns `0` for active members else `MINT_FEE * numTokens`; membership checked via `IManifoldMembership.isActiveMember` at `manifoldMembershipContract`. `purchase` forwards `priceWithoutFee` to `paymentReceiver` and retains the fee (withdrawn by admin via `withdraw`).

## Pitfalls

- `purchaseMax != 0` doubles as the "initialized" sentinel (`_getInstance` reverts otherwise) — a zero max is impossible by design.
- `activate` requires `startTime > block.timestamp`, `presaleInterval <= duration`, and `claimStartTime <= claimEndTime <= startTime`; misordered windows revert.
- `updateInitializationParameters` only works while **inactive** and cannot change `signingAddress`/`paymentReceiver` (use `updatePaymentReceiver`).
- Fee-only `claim` requires `msg.value` to equal exactly the fee — sending price too reverts.
- Signature messages are `msg.sender`-bound: a signed payload cannot be relayed by another address.
- For creator versions **< 3**, mint order is tracked in `_tokenIdToTokenClaimMap`; v3+ packs it into `tokenData` — tokenURI resolution handles both.

## Open questions

- No `IERC1155Collectible` present — is the ERC1155 variant intentionally absent from this family?
- `endTime`/`presalePurchasePrice` are stored but the sale upper-bound is not enforced in `purchase` beyond `purchaseRemaining`; is end-time gating handled off-chain?

## See also

- `[[repo-overview]]` — family placement.
- `[[lazy-payable-claim]]` — the merkle-based paid claim alternative.
- `[[shared-libraries]]` — `IManifoldMembership` fee-waiver plumbing.
