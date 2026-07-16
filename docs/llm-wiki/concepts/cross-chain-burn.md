---
title: Cross-Chain Burn
created: 2026-07-15
updated: 2026-07-15
type: concept
package: manifold
tags: [contract, interface, cross-chain, burn-redeem, erc721, erc1155, signature, membership, struct, pitfall]
sources: [manifold/contracts/crossChainBurn/CrossChainBurn.sol, manifold/contracts/crossChainBurn/ICrossChainBurn.sol, manifold/contracts/crossChainBurn/Interfaces.sol]
confidence: high
---

# Cross-Chain Burn

A **shared singleton** extension that lets a user **burn tokens on this chain** and have the **redeem happen on a different network/contract**. Unlike [[burn-redeem]], this contract does **not mint** the output — it only burns the inputs, records a per-instance count, and emits a `CrossChainBurn` event carrying the target `redeemContract` + `redeemNetworkId` for an off-chain/other-chain fulfiller to honor. Authorization comes from an **off-chain signer/oracle** rather than on-chain burn-set config. See [[repo-overview]] and [[shared-libraries]]; contrast the same-chain, config-driven [[burn-redeem]] family.

## Contract map

| File | Role |
|---|---|
| `crossChainBurn/CrossChainBurn.sol` | The whole extension: signature check, burn, count, event, receivers ^[manifold/contracts/crossChainBurn/CrossChainBurn.sol] |
| `crossChainBurn/ICrossChainBurn.sol` | `BurnSubmission`/`BurnToken` structs, enums, errors, event, surface |
| `crossChainBurn/Interfaces.sol` | `Burnable721`, `OZBurnable1155`, `Manifold1155` burn shims |

Inherits `ICrossChainBurn, ReentrancyGuard, AdminControl`. State is minimal: `address _signingAddress`, `mapping(uint256 => mapping(address => mapping(uint256 => bool))) _usedTokens` (per instance→contract→tokenId, for the no-burn spec), and `mapping(uint256 => uint64) _totalCount`. Signer is set in the constructor `(initialOwner, signingAddress)`. ^[manifold/contracts/crossChainBurn/CrossChainBurn.sol#L19]

## Key structs (from `ICrossChainBurn.sol`)

- **`BurnToken`** — `address contractAddress; uint256 tokenId; TokenSpec tokenSpec; BurnSpec burnSpec; uint72 amount`. Note this points at a **concrete token**, not a validation rule (no merkle/range — the signer already decided eligibility). ^[manifold/contracts/crossChainBurn/ICrossChainBurn.sol#L70]
- **`BurnSubmission`** — the signed authorization: `bytes signature; bytes32 message; uint256 instanceId; address redeemContract; uint256 redeemNetworkId; BurnToken[] burnTokens; uint64 redeemAmount; uint64 totalLimit; uint160 expiration`. ^[manifold/contracts/crossChainBurn/ICrossChainBurn.sol#L41]
- `TokenSpec { INVALID, ERC721, ERC1155, ERC721_NO_BURN }` — note the extra `ERC721_NO_BURN`. `BurnSpec { INVALID, NONE, MANIFOLD, OPENZEPPELIN }`.
- Event `CrossChainBurn(uint256 indexed instanceId, address indexed burnerAddress, address indexed redeemContract, uint256 redeemNetworkId, uint64 redeemAmount)`. ^[manifold/contracts/crossChainBurn/ICrossChainBurn.sol#L53]

## External surface

- `burnRedeem(BurnSubmission calldata submission)` `payable` — single. ^[manifold/contracts/crossChainBurn/CrossChainBurn.sol#L61]
- `burnRedeem(BurnSubmission[] calldata submissions)` `payable` — batch; per entry it **skips silently** (no revert) when `_isAvailable` is false, so partial batches succeed. ^[manifold/contracts/crossChainBurn/CrossChainBurn.sol#L71]
- `updateSigner(address)`, `withdraw(recipient, amount)`, `recover(tokenAddress, tokenId, destination)` — all `adminRequired`.
- `getTotalCount(instanceId) → uint64`.
- ERC721/ERC1155 receiver hooks for the send-in path.

Flow per submission: `_isAvailable` (supply gate) → `_validateSubmission` (signature) → `_burnTokens` → `_redeem`. ^[manifold/contracts/crossChainBurn/CrossChainBurn.sol#L61]

## Signature / authorization model

This is the heart of the design. `_validateSubmission`: ^[manifold/contracts/crossChainBurn/CrossChainBurn.sol#L86]

1. Reject if `block.timestamp > submission.expiration` (`ExpiredSignature`) or `redeemAmount == 0` (`InvalidInput`).
2. Recompute `expectedMessage = keccak256(abi.encode(instanceId, burnTokens, redeemAmount, totalLimit, expiration))`.
3. `signer = submission.message.recover(submission.signature)` (OZ `ECDSA`).
4. Revert `InvalidSignature` unless `submission.message == expectedMessage` **and** `signer == _signingAddress`.

So the trusted **Manifold signer/oracle** — which has observed the qualifying state on the *other* chain — issues an EIP-191 signature binding the exact burn set, amount, limit, and expiry. This contract trusts that signature; it performs **no on-chain proof** of cross-chain state itself. Supply is bounded by `_isAvailable`: if `totalLimit > 0` and `_totalCount[instanceId] + redeemAmount > totalLimit`, the redeem is unavailable. ^[manifold/contracts/crossChainBurn/CrossChainBurn.sol#L104]

## How tokens are burned & received

`_burn` dispatches on `tokenSpec`/`burnSpec` like [[burn-redeem]], with one extra mode: ^[manifold/contracts/crossChainBurn/CrossChainBurn.sol#L128]

- `ERC1155`: `NONE`→transfer to `0xdEaD`; `MANIFOLD`/`OPENZEPPELIN`→`burn`.
- `ERC721`: requires `amount == 1`; `NONE`→transfer to `0xdEaD`; else verify `ownerOf == from` then `Burnable721.burn`.
- **`ERC721_NO_BURN`**: does **not** destroy the token — it verifies ownership and marks `_usedTokens[instanceId][contract][tokenId] = true`, reverting if already used. This "burns" the *right to redeem* while leaving the NFT intact (for tokens that can't be burned). ^[manifold/contracts/crossChainBurn/CrossChainBurn.sol#L163]

Send-in path: `onERC721Received` / `onERC1155Received` / `onERC1155BatchReceived` `abi.decode` the full `BurnSubmission` from `data`, require a single `burnToken` (or matching length for batch), re-run availability + signature checks, verify `msg.sender`/`tokenId`/`amount` match the submission, burn from `address(this)`, then `_redeem`. ^[manifold/contracts/crossChainBurn/CrossChainBurn.sol#L230]

`_redeem` merely `_totalCount[instanceId] += redeemAmount` and emits the event — **no minting occurs here.** ^[manifold/contracts/crossChainBurn/CrossChainBurn.sol#L332]

## Fee & membership handling

Both entrypoints are `payable`, but there is **no fee/cost logic** — no `BURN_FEE`, no membership check, no `paymentReceiver`. Any ETH sent simply accumulates and is recoverable via admin `withdraw`. `IManifoldMembership` is imported but not used for gating in the read source. This is a deliberate contrast with [[burn-redeem]], whose fees fund the platform. ^[manifold/contracts/crossChainBurn/CrossChainBurn.sol#L40]

## Pitfalls

- **The redeem is off-chain/other-chain.** This contract never mints — it emits `CrossChainBurn` for an external fulfiller. If the fulfiller stalls, the user has burned inputs with nothing on-chain to show for it.
- **`ERC721_NO_BURN` uses `_usedTokens` per `instanceId`.** The same physical NFT can still be "used" in a *different* instanceId, and it is never actually consumed — design accordingly.
- **Batch mode swallows unavailable entries.** `burnRedeem(BurnSubmission[])` silently skips any submission failing `_isAvailable` (only signature-validates the available ones), so a batch can partially execute without reverting. ^[manifold/contracts/crossChainBurn/CrossChainBurn.sol#L71]
- **Trust is fully in `_signingAddress`.** A compromised or rotated signer changes who can authorize burns; there is no on-chain verification of the cross-chain claim.
- **`message` is caller-supplied and re-derived.** Security rests on the `message == expectedMessage && signer == _signingAddress` conjunction — the raw `message` field alone is not trusted.

## Open questions

- Is `expiration` (`uint160`) compared against `block.timestamp` deliberately oversized, and what replay protection exists across chains beyond `totalLimit`/`_usedTokens`? ^[manifold/contracts/crossChainBurn/CrossChainBurn.sol#L87]
- Nothing binds a submission to `msg.sender` in the signed `message`, so any address holding the burn tokens can submit a valid signature — intended?
