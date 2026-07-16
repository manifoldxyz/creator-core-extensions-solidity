---
title: Physical Claim
created: 2026-07-15
updated: 2026-07-15
type: concept
package: manifold
tags: [contract, interface, physical, burn-redeem, erc721, erc1155, signature, membership, fee, struct, pitfall]
sources: [manifold/contracts/physicalclaim/PhysicalClaim.sol, manifold/contracts/physicalclaim/IPhysicalClaim.sol, manifold/contracts/physicalclaim/Interfaces.sol]
confidence: high
---

# Physical Claim

## What it is

A **burn-to-redeem-a-physical-item** extension. The redeemer burns one or more NFTs, and — instead of minting a new on-chain token — the contract simply emits a `Redeem` event and increments counters. The physical fulfillment happens off-chain; the event + signed submission are the on-chain receipt. Every redemption is authorized by an **off-chain ECDSA signature** over the full submission, so limits, price, and eligibility are server-controlled rather than stored per-instance. Related to `[[burn-redeem]]` but the "output" is a real-world good, not an NFT.

## Contract map

| File (relative to `packages/`) | Role |
|---|---|
| `manifold/contracts/physicalclaim/PhysicalClaim.sol` | The contract: `burnRedeem` (single + batch), token-receiver hooks, burn dispatch, signature/nonce/limit validation, fee logic. Extends `AdminControl` + `ReentrancyGuard`. |
| `manifold/contracts/physicalclaim/IPhysicalClaim.sol` | Interface: `BurnSubmission`/`BurnToken` structs, `TokenSpec`/`BurnSpec` enums, errors, `Redeem` event. |
| `manifold/contracts/physicalclaim/Interfaces.sol` | Minimal burn interfaces: `Burnable721`, `OZBurnable1155`, `Manifold1155`. |

## Key structs & enums (`physicalclaim/IPhysicalClaim.sol`)

- `BurnSubmission { bytes signature; bytes32 message; uint256 instanceId; BurnToken[] burnTokens; uint8 variation; uint64 variationLimit; uint64 totalLimit; address erc20; uint256 price; address payable fundsRecipient; uint160 expiration; bytes32 nonce; }`
- `BurnToken { address contractAddress; uint256 tokenId; TokenSpec tokenSpec; BurnSpec burnSpec; uint72 amount; }`
- `enum TokenSpec { INVALID, ERC721, ERC1155, ERC721_NO_BURN }`
- `enum BurnSpec { INVALID, NONE, MANIFOLD, OPENZEPPELIN }`

## External surface

`physicalclaim/PhysicalClaim.sol`:
- `burnRedeem(BurnSubmission submission)` — `payable`, `nonReentrant`
- `burnRedeem(BurnSubmission[] submissions)` — `payable`, `nonReentrant`; skips sold-out entries and refunds unused `msg.value`
- `onERC721Received / onERC1155Received / onERC1155BatchReceived` — receiver-hook burn path (submission ABI-encoded in `data`)
- `withdraw(address payable, uint256)` · `setMembershipAddress(address)` · `updateSigner(address)`
- `recover(address tokenAddress, uint256 tokenId, address destination)` — rescue a mistakenly-sent ERC721
- `getVariationCounts(uint256 instanceId, uint8[] variations) → uint64[]`
- `getTotalCount(uint256 instanceId) → uint64`
- `constructor(address initialOwner, address signingAddress)`

## Distinctive mechanic

**Signature over the whole submission.** `_validateSubmission` recomputes `keccak256(abi.encode(instanceId, burnTokens, variation, variationLimit, totalLimit, erc20, price, fundsRecipient, expiration, nonce))`, requires `submission.message` to equal it, requires `message.recover(signature) == _signingAddress`, checks `block.timestamp <= expiration`, and consumes the per-instance `nonce`. All economic terms are signed — the contract stores no per-instance config, only counters. There is **no `initialize` step**; the signer is the single source of truth (one global `_signingAddress`, updatable via `updateSigner`).

**Four burn modes** (`_burn`, dispatched by `TokenSpec` × `BurnSpec`):
- `ERC1155` → `MANIFOLD` (`Manifold1155.burn`), `OPENZEPPELIN` (`OZBurnable1155.burn`), or `NONE` (transfer to `0xdEaD`).
- `ERC721` → `MANIFOLD`/`OPENZEPPELIN` (`Burnable721.burn` after owner check), or `NONE` (transfer to `0xdEaD`).
- `ERC721_NO_BURN` → **not burned at all**: token is verified as owned and marked in `_usedTokens[instanceId][contract][tokenId]` so it can't be reused. Useful for tokens that must survive.

**Two entry paths:** direct `burnRedeem` (approve-then-call, supports ETH/ERC20 price + fee), or `safeTransferFrom` into the contract with the submission in `data` — but the transfer path only works when there is no ETH price and the sender is an active member (`_validateCanReceive`), since a bare transfer carries no payment.

**Variation & total caps** are enforced against the *signed* `variationLimit`/`totalLimit` via `_isVariationAvailable`; batch calls silently skip unavailable variations rather than reverting the whole batch.

## Fee / membership handling

`BURN_FEE = 690000000000000` (single-token) and `MULTI_BURN_FEE = 990000000000000` for submissions with >1 burn token. In `_redeem`, non-members pay `price (if native) + fee`; active members (`IManifoldMembership.isActiveMember`) pay neither the fee nor need it bundled. Native price is forwarded to `fundsRecipient`; ERC20 price uses `transferFrom(redeemer, fundsRecipient, price)`. Admin sweeps accrued fees via `withdraw`.

## Pitfalls

- **No on-chain instance config** — `instanceId` is just a namespace for nonces/counters/used-tokens. A bad or malicious signer can authorize arbitrary terms; security rests entirely on `_signingAddress`.
- Nonces are unique **per instanceId**, not global; the same `nonce` value can be legitimately reused across different instances.
- `ERC721_NO_BURN` tokens are consumed logically (marked used) but stay in the owner's wallet — double-submitting the same token reverts `InvalidToken`.
- Receiver-hook path rejects any submission with a native `price != 0` or a non-member sender (`_validateCanReceive`), and requires exactly one `burnToken` for the single-token hooks.
- Batch `burnRedeem` uses a running `msgValue` and refunds the remainder; if a submission is skipped as sold-out, its funds are not consumed. Under/over-payment across the batch is reconciled at the end.
- ERC721 `MANIFOLD`/`OPENZEPPELIN` burns verify `ownerOf == from` because 721 `burn(tokenId)` has no `from` param — a spoofed owner reverts `TransferFailure`.
- `recover` only handles ERC721; ERC1155 sent without the burn `data` cannot be rescued the same way.

## Open questions

- Is there an ERC1155/ERC721 *output* variant elsewhere, or is physical-only fulfillment the whole point of this family?
- `expiration` is `uint160` in the struct but compared against `block.timestamp` — the wide type seems deliberate; is it a packing artifact?

## See also

- `[[repo-overview]]` — where physical claim sits among extensions.
- `[[burn-redeem]]` — the NFT-output sibling of this burn mechanic.
- `[[shared-libraries]]` — `IManifoldMembership` fee-waiver plumbing.
