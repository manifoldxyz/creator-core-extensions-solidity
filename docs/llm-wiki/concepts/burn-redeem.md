---
title: Burn Redeem (v1 + V2 updatable-fee)
created: 2026-07-15
updated: 2026-07-15
type: concept
package: manifold
tags: [contract, abstract, interface, library, burn-redeem, erc721, erc1155, merkle, membership, fee, version-v2, struct, pitfall]
sources: [manifold/contracts/burnredeem/BurnRedeemCore.sol, manifold/contracts/burnredeem/BurnRedeemLib.sol, manifold/contracts/burnredeem/IBurnRedeemCore.sol, manifold/contracts/burnredeem/ERC721BurnRedeem.sol, manifold/contracts/burnredeem/ERC1155BurnRedeem.sol, manifold/contracts/burnredeem/Interfaces.sol, manifold/contracts/burnredeemUpdatableFee/BurnRedeemCoreV2.sol, manifold/contracts/burnredeemUpdatableFee/IBurnRedeemCoreV2.sol]
confidence: high
---

# Burn Redeem (v1 + V2 updatable-fee)

A **shared singleton** extension: one deployed contract that any Manifold creator installs. A burn-redeem instance is keyed by `(creatorContractAddress, instanceId)` in `mapping(address => mapping(uint256 => BurnRedeem)) _burnRedeems`. Holders **burn N input tokens** matching a configured burn-set to **mint a redeem output** on the creator contract. See [[repo-overview]] and the primitives in [[shared-libraries]]. Compare with [[lazy-payable-claim]] (mint-by-allowlist, no burn) and the older, separate [[redeem-package]] implementation.

## Contract map

| File | Role |
|---|---|
| `burnredeem/BurnRedeemCore.sol` | Abstract base: burn/receive/fee logic, storage, receivers ^[manifold/contracts/burnredeem/BurnRedeemCore.sol] |
| `burnredeem/BurnRedeemLib.sol` | Library: init/update, param validation, `validateBurnItem`, events ^[manifold/contracts/burnredeem/BurnRedeemLib.sol] |
| `burnredeem/ERC721BurnRedeem.sol` | Concrete: mints ERC721 redeem tokens (`mintExtension`) ^[manifold/contracts/burnredeem/ERC721BurnRedeem.sol] |
| `burnredeem/ERC1155BurnRedeem.sol` | Concrete: mints one shared ERC1155 redeem token id ^[manifold/contracts/burnredeem/ERC1155BurnRedeem.sol] |
| `burnredeem/IBurnRedeemCore.sol` | Structs, enums, errors, external surface |
| `burnredeem/Interfaces.sol` | `Burnable721`, `OZBurnable1155`, `Manifold1155` burn shims |
| `burnredeemUpdatableFee/*V2.sol` | V2 fork — mutable fees + global `active` flag (see delta) |

Base inherits `ERC165, AdminControl, ReentrancyGuard, IBurnRedeemCore, ICreatorExtensionTokenURI`. Config is admin-gated: `_validateAdmin` requires `IAdminControl(creator).isAdmin(msg.sender)` — the caller must be admin on the **creator** contract, not this extension. ^[manifold/contracts/burnredeem/BurnRedeemCore.sol#L101]

## Key structs (from `IBurnRedeemCore.sol`)

- **`BurnItem`** — what is burnable: `ValidationType validationType; address contractAddress; TokenSpec tokenSpec; BurnSpec burnSpec; uint72 amount; uint256 minTokenId; uint256 maxTokenId; bytes32 merkleRoot`. ^[manifold/contracts/burnredeem/IBurnRedeemCore.sol#L59]
  - `ValidationType { INVALID, CONTRACT, RANGE, MERKLE_TREE, ANY }` — allowlist by whole contract, by id-range, by merkle tree of ids, or ANY token from anywhere.
  - `TokenSpec { INVALID, ERC721, ERC1155 }`; `BurnSpec { NONE, MANIFOLD, OPENZEPPELIN }` selects how the burn is performed.
- **`BurnGroup`** — `uint256 requiredCount; BurnItem[] items`. Each group is an "M-of-N" requirement: `requiredCount` items from `items` must be supplied.
- **`BurnRedeem`** (stored) — `paymentReceiver, storageProtocol, redeemedCount, redeemAmount, totalSupply, contractVersion, startDate, endDate, cost, location, burnSet`. `burnSet` is a `BurnGroup[]`; **every group** must be satisfied per redeem. ^[manifold/contracts/burnredeem/IBurnRedeemCore.sol#L105]
- **`BurnToken`** (call input) — pointer into the config: `uint48 groupIndex; uint48 itemIndex; address contractAddress; uint256 id; bytes32[] merkleProof`. The caller pre-resolves which `BurnItem` each burned token satisfies.

`storageProtocol == INVALID` is the "does-not-exist" sentinel — `_getBurnRedeem` reverts `BurnRedeemDoesNotExist` on it, and init refuses to overwrite a non-INVALID slot. ^[manifold/contracts/burnredeem/BurnRedeemLib.sol#L77]

## External surface

- `initializeBurnRedeem(creator, instanceId, params, identicalTokenURI)` (721) / `(creator, instanceId, params)` (1155). 721 caps `instanceId` at `MAX_UINT_56`; 1155 mints a placeholder token id (amount 0) at init to reserve the redeem id. ^[manifold/contracts/burnredeem/ERC1155BurnRedeem.sol#L41]
- `updateBurnRedeem(...)`, `updateTokenURI/updateURI(...)`.
- `burnRedeem(creator, instanceId, burnRedeemCount, BurnToken[])` `payable` — main entry. Batch overload takes parallel arrays; `burnRedeemWithData(..., bytes data)` adds event data. ^[manifold/contracts/burnredeem/BurnRedeemCore.sol#L160]
- `airdrop(creator, instanceId, recipients[], amounts[])` — admin mints without burning.
- `recoverERC721`, `withdraw`, `setMembershipAddress` (all `adminRequired`).

`_burnRedeem` clamps count to available supply (`_getAvailableBurnRedeemCount`), computes fee, forwards `cost` to `paymentReceiver`, then `_burnTokens` then `_redeem`. Overpayment is refunded to the caller. ^[manifold/contracts/burnredeem/BurnRedeemCore.sol#L227]

## How tokens are received & validated

Two paths converge on `BurnRedeemLib.validateBurnItem` (checks contract match, RANGE bounds, or `MerkleProof.verify(keccak256(abi.encodePacked(tokenId)))`; `ANY` short-circuits): ^[manifold/contracts/burnredeem/BurnRedeemLib.sol#L131]

1. **Approve-then-call**: `burnRedeem(...)` iterates `burnTokens`, validates each against `burnSet[groupIndex].items[itemIndex]`, burns, and tallies per-group counts — reverting `InvalidBurnAmount` unless every `groupCounts[i] == requiredCount * burnRedeemCount`. ^[manifold/contracts/burnredeem/BurnRedeemCore.sol#L485]
2. **Safe-transfer callback**: `onERC721Received` / `onERC1155Received` / `onERC1155BatchReceived` decode target `(creator, instanceId, ...)` from `data` (`abi.decode`, requires `data.length % 32 == 0`). This "send-in" path is **restricted**: it only works when `cost == 0`, the burnSet is a single group with `requiredCount == 1`, and the sender is an active member (`_validateReceivedInput`) — because a bare transfer carries no ETH for fee/cost. ^[manifold/contracts/burnredeem/BurnRedeemCore.sol#L466]

`_burn` dispatches on `burnSpec`: `NONE` → `safeTransferFrom` to `0xdEaD`; `MANIFOLD` → `Manifold1155.burn` / `Burnable721.burn`; `OPENZEPPELIN` → OZ `burn`. For 721 with a burn function it verifies `ownerOf == from` first (721 `burn` has no `from`). ^[manifold/contracts/burnredeem/BurnRedeemCore.sol#L545]

## Fee & membership handling

Two flat platform fees on top of the creator's `cost`: `BURN_FEE = 0.00069 ETH`, `MULTI_BURN_FEE = 0.00099 ETH` (applied when `burnTokens.length > 1`). Fees are **waived for active Manifold members** — `_isActiveMember` calls `IManifoldMembership.isActiveMember(sender)` on `manifoldMembershipContract` (see [[shared-libraries]]). `cost` goes to the instance `paymentReceiver`; accumulated fees stay in the contract for admin `withdraw`. ^[manifold/contracts/burnredeem/BurnRedeemCore.sol#L67]

## v1 vs V2 delta (`burnredeemUpdatableFee/`)

V2 is a near-verbatim fork of v1 with two additions: ^[manifold/contracts/burnredeemUpdatableFee/BurnRedeemCoreV2.sol#L67]

1. **Updatable fees** — `BURN_FEE` / `MULTI_BURN_FEE` become **mutable public state** (not `constant`), set via `setBurnFees(uint256 burnFee, uint256 multiBurnFee)` (`adminRequired`). Everything about how the fee is charged is otherwise identical. ^[manifold/contracts/burnredeemUpdatableFee/BurnRedeemCoreV2.sol#L285]
2. **Global kill switch** — new `bool public active = true` + `setActive(bool)`; `_initialize` reverts `Inactive()` when `!active` (blocks *new* instances only; existing burns keep working). New error `Inactive()` in `IBurnRedeemCoreV2`. ^[manifold/contracts/burnredeemUpdatableFee/BurnRedeemCoreV2.sol#L117]

Struct/enum/receiver/validation logic is unchanged between versions.

## Pitfalls

- **V2 fees default to 0.** The V2 constructor does not set `BURN_FEE`/`MULTI_BURN_FEE`; until an admin calls `setBurnFees`, both are `0` and the platform collects nothing. ^[manifold/contracts/burnredeemUpdatableFee/BurnRedeemCoreV2.sol#L85]
- **Send-in path is member-only + free-only.** Transferring an NFT directly (marketplace "burn" flows) silently fails via `InvalidInput` unless cost is 0, single-item single-group, and the sender is an active member.
- **`admin` means creator-contract admin.** `_validateAdmin` checks the creator, not this extension — installing without admin rights blocks initialization.
- **`totalSupply % redeemAmount` and `redeemedCount % redeemAmount` must be 0** on update, else `InvalidRedeemAmount`. ^[manifold/contracts/burnredeem/BurnRedeemLib.sol#L105]
- **`BurnItem` amount rule**: ERC1155 must have `amount > 0`, ERC721 must have `amount == 0`, or `_setBurnGroups` reverts. ^[manifold/contracts/burnredeem/BurnRedeemLib.sol#L203]

## Open questions

- How does the 721 `contractVersion >= 3` tokenData packing (`uint56(instanceId) << 24 | count`) interact with pre-v3 creator cores that fall back to the `_redeemTokens` map? ^[manifold/contracts/burnredeem/ERC721BurnRedeem.sol#L95]
- Is `MULTI_BURN_FEE` keyed on `burnTokens.length` alone (not `burnRedeemCount`)? Yes per source — worth confirming intended UX.
