---
title: Farcaster Frame Claims
created: 2026-07-15
updated: 2026-07-15
type: concept
package: manifold
tags: [contract, abstract, interface, claim, frame, erc1155, signature, fee, struct, pitfall]
sources: [manifold/contracts/frameclaims/FrameLazyClaim.sol, manifold/contracts/frameclaims/ERC1155FrameLazyClaim.sol, manifold/contracts/frameclaims/FramePaymaster.sol, manifold/contracts/frameclaims/IFrameLazyClaim.sol, manifold/contracts/frameclaims/IERC1155FrameLazyClaim.sol, manifold/contracts/frameclaims/IFramePaymaster.sol]
confidence: high
---

# Farcaster Frame Claims

## What it is

A **shared singleton** extension for minting ERC-1155 claims from **Farcaster Frames**. Because a Frame interaction has no on-chain signature from the user, mints are **relayed**: a trusted **signer/paymaster** authorizes and submits the mint on the user's behalf. Two contracts collaborate — `ERC1155FrameLazyClaim` (the extension holding claims) and `FramePaymaster` (the relayer that verifies a backend signature bound to a Farcaster `fid` + nonce). Instances keyed by `(creatorContractAddress, instanceId)`. A relayed variant of the [[lazy-payable-claim]] family; see [[repo-overview]].

## Contract map

| File | Role |
|------|------|
| `frameclaims/IFrameLazyClaim.sol` | Base interface: `Recipient`/`Mint` structs, sponsor/signer/mint surface, errors, events |
| `frameclaims/IERC1155FrameLazyClaim.sol` | ERC-1155 `Claim`/`ClaimParameters`, init/getters |
| `frameclaims/FrameLazyClaim.sol` | `abstract FrameLazyClaim is IFrameLazyClaim, AdminControl` — signer, funds receiver, `SPONSORED_MINT_FEE`, `MANIFOLD_FREE_MINTS` |
| `frameclaims/ERC1155FrameLazyClaim.sol` | Concrete extension: claim storage, `mint` (signer-only), `sponsorMints`, `tokenURI` |
| `frameclaims/IFramePaymaster.sol` | Paymaster interface: `MintSubmission`/`ExtensionMint`/`Mint`, `checkout`/`deliver` |
| `frameclaims/FramePaymaster.sol` | Relayer: signature + nonce verification, fans out to extension `mint` |

## Key structs (from source)

`Claim` (`IERC1155FrameLazyClaim.sol:21`): `StorageProtocol storageProtocol; string location; uint256 tokenId; address payable paymentReceiver; uint56 sponsoredMints;`

`IFrameLazyClaim.Recipient` (`:23`): `address receiver; uint256 amount; uint256 payment;`
`IFrameLazyClaim.Mint` (`:29`): `address creatorContractAddress; uint256 instanceId; Recipient[] recipients;`

`IFramePaymaster.MintSubmission` (`:22`): `ExtensionMint[] extensionMints; uint256 fid; uint256 nonce; uint256 expiration; bytes32 message; bytes signature;`
`ExtensionMint` (`:31`): `address extensionAddress; Mint[] mints;`
`IFramePaymaster.Mint` (`:36`): `address creatorContractAddress; uint256 instanceId; uint256 amount; uint256 payment;`

## External surface (traced)

**Extension (`ERC1155FrameLazyClaim.sol`):**
- `initializeClaim(address, uint256, ClaimParameters) external payable creatorAdminRequired` — `:41`
- `mint(Mint[] calldata) external payable` — `:132` (**signer-only**, `_validateSigner`)
- `sponsorMints(address, uint256, uint56) external payable creatorAdminRequired` — `:148`
- `updateTokenURIParams` / `extendTokenURI` / `getClaim` / `getClaimForToken` / `tokenURI`
- From `FrameLazyClaim.sol`: `setSigner adminRequired` (`:62`), `setFundsReceiver adminRequired` (`:69`), `updateSponsoredMintFee adminRequired` (`:48`), `updateManifoldFreeMints adminRequired` (`:55`).

**Paymaster (`FramePaymaster.sol`):**
- `checkout(MintSubmission calldata) external payable` — `:63` (user-facing relay entry)
- `deliver(address extensionAddress, Mint[] calldata) external` — `:55` (**signer-only** direct delivery)
- `setSigner adminRequired` (`:47`), `withdraw adminRequired` (`:39`)

## The distinctive mechanic: paymaster authorization

The extension's `mint` **only accepts calls from `_signer`** (`ERC1155FrameLazyClaim.sol:133` → `_validateSigner`). Two authorized paths reach it:

1. **`FramePaymaster.checkout`** — the collector (or a relayer) submits a `MintSubmission`. `_validateCheckout` (`FramePaymaster.sol:96`) enforces:
   - `block.timestamp <= expiration` else `ExpiredSignature` (`:97`).
   - Recomputes `expectedMessage = keccak256(abi.encodePacked(abi.encode(extensionMints, fid, expiration, nonce, msg.value)))` and requires `submission.message == expectedMessage` **and** `message.recover(signature) == _signer` (`:99-101`). Payment (`msg.value`) is bound into the signed message.
   - **Nonce replay protection keyed by `(fid, nonce)`**: `_usedNonces[fid][nonce]` must be false, then set true (`:102-103`).
   Checkout then loops extensions, builds `Recipient{ receiver: msg.sender, ... }`, and calls `extension.mint{value: extensionPayment}(mints)` (`:89`). The paymaster must itself be set as the extension's signer for this to succeed.
2. **`FramePaymaster.deliver`** — backend-only (`msg.sender == _signer`) direct call that forwards to `extension.mint` with pre-built recipients, used when Manifold sponsors/relays the mint entirely off the user's payment.

Inside the extension, `_mintClaim` (`:160`) sums `recipients[].payment`, requires `paymentReceived >= totalPayment`, mints via `mintExtensionExisting`, and forwards `totalPayment` to `claim.paymentReceiver`.

## Fee & membership handling

- **Sponsored mints:** `MANIFOLD_FREE_MINTS = 5` are free; beyond that each sponsored mint costs `SPONSORED_MINT_FEE = 0.0001 ETH` (`FrameLazyClaim.sol:27-28`). Charged at `initializeClaim` (`:53-54`) and `sponsorMints` (`:149`), forwarded to `_fundsReceiver`.
- A claim is **either** paid (`paymentReceiver` set) **or** sponsored (`sponsoredMints > 0`) — never both (`ERC1155FrameLazyClaim.sol:51`).
- Per-mint collector payment flows to `claim.paymentReceiver`; no merkle allowlist or delegation.

## Pitfalls

- **Signer = single point of trust.** The extension mints for anyone the signer authorizes; the paymaster's ECDSA check is the only gate on `checkout`. Compromise the backend key and arbitrary mints are possible.
- `message.recover(signature)` is applied to the **raw `bytes32`** with no EIP-191 (`\x19Ethereum Signed Message`) prefix — backend signing must match exactly.
- `msg.value` is folded into the signed message, so any payment mismatch invalidates the signature (good), but also means the exact value must be known at signing time.
- The paymaster must be registered as the extension's `_signer` (`setSigner`) for `checkout` to work; otherwise `checkout` reverts on the extension's `_validateSigner`.
- `tokenURI` returns `prefix + location` with **no token index** (single token per claim; `Claim.tokenId`).

## Open questions

- Absence of an EIP-191/EIP-712 prefix on the checkout signature — intentional (backend-controlled) but reduces interoperability with standard wallet signers.
- `fid` is recorded/emitted but not otherwise bound to the receiver on-chain; Farcaster identity ↔ wallet mapping is a backend concern.

See also: [[deck-claims]], [[gacha-serendipity]], [[shared-libraries]].
