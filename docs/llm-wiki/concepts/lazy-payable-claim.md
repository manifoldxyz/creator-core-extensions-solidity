---
title: Lazy Payable Claim (v1)
created: 2026-07-15
updated: 2026-07-15
type: concept
package: manifold
tags: [contract, abstract, interface, claim, erc721, erc1155, usdc, merkle, signature, delegation, membership, fee, pitfall]
sources: [manifold/contracts/lazyclaim/LazyPayableClaimCore.sol, manifold/contracts/lazyclaim/LazyPayableClaim.sol, manifold/contracts/lazyclaim/ERC721LazyPayableClaim.sol, manifold/contracts/lazyclaim/ERC721LazyPayableClaimCore.sol, manifold/contracts/lazyclaim/ERC1155LazyPayableClaim.sol, manifold/contracts/lazyclaim/ERC1155LazyPayableClaimCore.sol, manifold/contracts/lazyclaim/LazyPayableClaimUSDC.sol, manifold/contracts/lazyclaim/ERC721LazyPayableClaimUSDC.sol, manifold/contracts/lazyclaim/ERC1155LazyPayableClaimUSDC.sol, manifold/contracts/lazyclaim/ILazyPayableClaim.sol, manifold/contracts/lazyclaim/ILazyPayableClaimCore.sol, manifold/contracts/lazyclaim/IERC721LazyPayableClaim.sol, manifold/contracts/lazyclaim/IERC1155LazyPayableClaim.sol, manifold/contracts/lazyclaim/ILazyPayableClaimUSDC.sol]
confidence: high
---

# Lazy Payable Claim (v1)

## What it is

A **shared singleton extension** for selling "claim page" mints on Manifold Creator Core contracts. One instance is deployed per chain; every creator contract installs it as an extension and registers claims keyed by `(creatorContractAddress, instanceId)`. Tokens are minted lazily (on demand, buyer pays gas) rather than pre-minted. Supports public sales, merkle allowlists, and off-chain signature allowlists, with payment in ETH or an arbitrary ERC20 (plus dedicated USDC variants). See [[repo-overview]] and [[shared-libraries]]; the fee-updatable successor is [[lazy-payable-claim-v2]].

## Contract map

- `manifold/contracts/lazyclaim/LazyPayableClaimCore.sol` — abstract base: shared state (`_claims` live in the ERC721/ERC1155 core), merkle/signature/delegation validation helpers, `MEMBERSHIP_ADDRESS`, `creatorAdminRequired` modifier, delegation registry addresses.
- `manifold/contracts/lazyclaim/LazyPayableClaim.sol` — abstract: ETH fee constants (`MINT_FEE`, `MINT_FEE_MERKLE`), `withdraw`, and the ETH `_transferFunds`.
- `manifold/contracts/lazyclaim/ERC721LazyPayableClaimCore.sol` — abstract: ERC721 `Claim` storage, `initializeClaim`/`updateClaim`, `tokenURI`, `airdrop`, `_mintBatch`.
- `manifold/contracts/lazyclaim/ERC721LazyPayableClaim.sol` — concrete ERC721: `mint`/`mintBatch`/`mintProxy`/`mintSignature`.
- `manifold/contracts/lazyclaim/ERC1155LazyPayableClaimCore.sol` — abstract: ERC1155 `Claim` storage (has a `tokenId` field), init/update/tokenURI/airdrop, `_mintClaim`.
- `manifold/contracts/lazyclaim/ERC1155LazyPayableClaim.sol` — concrete ERC1155 mint functions.
- `manifold/contracts/lazyclaim/LazyPayableClaimUSDC.sol` — abstract: USDC-denominated fees + `_transferFunds` that pulls USDC via `transferFrom`.
- `manifold/contracts/lazyclaim/ERC721LazyPayableClaimUSDC.sol` / `ERC1155LazyPayableClaimUSDC.sol` — concrete USDC variants; `mint*` are **non-payable** and force `claim.erc20 == USDC_ADDRESS`.
- Interfaces: `ILazyPayableClaimCore.sol` (errors, `StorageProtocol` enum, events, view helpers), `ILazyPayableClaim.sol` (the four `mint*` signatures), `IERC721LazyPayableClaim.sol` / `IERC1155LazyPayableClaim.sol` (`ClaimParameters` + `Claim` structs), `ILazyPayableClaimUSDC.sol` (adds `InvalidUSDCAddress`).

## The Claim struct

ERC721 `Claim` (`manifold/contracts/lazyclaim/IERC721LazyPayableClaim.sol`):

```solidity
struct Claim {
    uint32 total;            // minted so far
    uint32 totalMax;         // 0 = unlimited
    uint32 walletMax;        // 0 = unlimited (non-merkle only)
    uint48 startDate;
    uint48 endDate;          // 0 = no end
    StorageProtocol storageProtocol; // INVALID/NONE/ARWEAVE/IPFS/ADDRESS
    uint8 contractVersion;
    bool identical;          // if false, append /mintOrder to URI
    bytes32 merkleRoot;      // "" = no allowlist
    string location;
    uint256 cost;            // per-mint price (excludes platform fee)
    address payable paymentReceiver;
    address erc20;           // ADDRESS_ZERO = ETH
    address signingAddress;  // set => signature minting required
}
```

The ERC1155 `Claim` (`manifold/contracts/lazyclaim/IERC1155LazyPayableClaim.sol`) is the same minus `contractVersion`/`identical` and **adds `uint256 tokenId`** (the shared 1155 token id). `ClaimParameters` is the init/update payload (same fields minus `total`, `contractVersion`, `tokenId`).

## External surface

Callers hit the four mint functions declared in `manifold/contracts/lazyclaim/ILazyPayableClaim.sol`, implemented in `ERC721LazyPayableClaim.sol` / `ERC1155LazyPayableClaim.sol`:

```solidity
function mint(address creatorContractAddress, uint256 instanceId, uint32 mintIndex,
    bytes32[] calldata merkleProof, address mintFor) external payable;
function mintBatch(address creatorContractAddress, uint256 instanceId, uint16 mintCount,
    uint32[] calldata mintIndices, bytes32[][] calldata merkleProofs, address mintFor) external payable;
function mintProxy(address creatorContractAddress, uint256 instanceId, uint16 mintCount,
    uint32[] calldata mintIndices, bytes32[][] calldata merkleProofs, address mintFor) external payable;
function mintSignature(address creatorContractAddress, uint256 instanceId, uint16 mintCount,
    bytes calldata signature, bytes32 message, bytes32 nonce, address mintFor, uint256 expiration) external payable;
```

Admin surface (`manifold/contracts/lazyclaim/ERC721LazyPayableClaimCore.sol`, guarded by `creatorAdminRequired`): `initializeClaim`, `updateClaim`, `updateTokenURIParams`, `extendTokenURI`, `airdrop`. Views: `getClaim`, `getClaimForToken`, `checkMintIndex(es)`, `getTotalMints`. Owner-only: `setMembershipAddress`, `withdraw`. USDC variants (`ERC721LazyPayableClaimUSDC.sol`) declare the same four `mint*` but **without `payable`** (fee & cost both flow in USDC via `transferFrom`).

## Fee & membership handling

Platform fee is a flat constant added on top of `cost`, in `LazyPayableClaim._transferFunds` (`manifold/contracts/lazyclaim/LazyPayableClaim.sol`): `MINT_FEE = 0.0005 ETH`, `MINT_FEE_MERKLE = 0.00069 ETH` — merkle mints pay the higher fee. USDC variant uses `MINT_FEE = 1_000000` / `MINT_FEE_MERKLE = 1_330000` (6-decimal USDC). The fee is **waived** only when `MEMBERSHIP_ADDRESS` is set, `allowMembership` is true, and `IManifoldMembership(MEMBERSHIP_ADDRESS).isActiveMember(msg.sender)` returns true. `mintProxy`/`mintSignature` pass `allowMembership = false`, so the fee is never waived there. `cost` (creator revenue) is forwarded to `paymentReceiver`; the platform fee accrues to the extension contract and is pulled out with `withdraw`.

## Merkle / signature / delegation mechanics

- **Merkle** (`_checkMerkleAndUpdate` in `LazyPayableClaimCore.sol`): leaf = `keccak256(abi.encodePacked(mintFor, mintIndex))`. Consumed indices are tracked as a bitmask (`_claimMintIndices`, `mintIndex >> 8` bucket, `1 << (mintIndex & 0xFF)`), so each index is single-use.
- **Delegation**: if `mintFor != msg.sender` on a merkle mint, the caller must be a delegate of `mintFor` per `IDelegationRegistryV2.checkDelegateForContract` OR the legacy `IDelegationRegistry` (see [[shared-libraries]]).
- **Signature** (`_checkSignatureAndUpdate`): message = `keccak256(abi.encodePacked(creatorContractAddress, instanceId, nonce, mintFor, expiration, mintCount))`, recovered via ECDSA against `claim.signingAddress`; `nonce` is single-use (`_usedMessages`) and `expiration` is enforced.

## Pitfalls

- **A `signingAddress` claim can ONLY be minted via `mintSignature`.** `mint`/`mintBatch`/`mintProxy` all revert `MustUseSignatureMinting` when `signingAddress != address(0)` (`ERC721LazyPayableClaim.sol:40`).
- **`walletMax` and `merkleRoot` are mutually exclusive** — `initializeClaim` rejects both being set. `walletMax` limits only apply to non-merkle claims.
- **`updateClaim` cannot change the payment token** — `erc20` mismatch reverts `CannotChangePaymentToken` (`ERC721LazyPayableClaimCore.sol:128`).
- **ETH fees are hardcoded constants** in v1 — the whole reason [[lazy-payable-claim-v2]] exists is to make them settable.
- **`mintProxy`/`mintSignature` never waive the platform fee** (membership ignored).
- ERC721 `totalMax` is also bounded by `MAX_UINT_24`; overflow reverts `TooManyRequested`.

## Open questions

- Full `ERC1155LazyPayableClaimCore._mintClaim` / `initializeClaim` body (tokenId assignment via `mintExtensionNew`) not fully transcribed here — a reference dump of the 1155 core is warranted.
- `IERC721LazyPayableClaimMetadata` / `IERC1155LazyPayableClaimMetadata` (the `StorageProtocol.ADDRESS` external URI resolver) are referenced but not documented on this page.
