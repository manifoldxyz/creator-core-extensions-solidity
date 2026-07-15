---
title: Operator Filterer Extensions
created: 2026-07-15
updated: 2026-07-15
type: concept
package: manifold
tags: [contract, abstract, operator-filter, erc721, erc1155, admin, pitfall]
sources: [manifold/contracts/operatorfilterer/CreatorOperatorFilterer.sol, manifold/contracts/operatorfilterer/OperatorFilterer.sol, manifold/contracts/operatorfilterer/nofilterer/ERC721NoFilterer.sol, manifold/contracts/operatorfilterer/nofilterer/ERC1155NoFilterer.sol]
confidence: high
---

# Operator Filterer Extensions

## What it is

Shared extensions that plug into the creator core's per-transfer
`approveTransfer` hook to **block transfers initiated by disallowed marketplace
operators** — Manifold's take on OpenSea's operator-filter-registry royalty
enforcement. Two enforcement models ship: a registry-backed subscription model
(`OperatorFilterer`) and a creator-configurable on-contract blocklist
(`CreatorOperatorFilterer`). A third, no-op "NoFilterer" family exists to
explicitly opt out. See [[repo-overview]].

## Contract map

| File | Role |
|------|------|
| `operatorfilterer/OperatorFilterer.sol` | Registry-subscription filterer; queries external `IOperatorFilterRegistry` |
| `operatorfilterer/CreatorOperatorFilterer.sol` | Creator-controlled on-chain blocklist (addresses + code hashes) |
| `operatorfilterer/nofilterer/ERC721NoFilterer.sol` | `abstract` — ERC721 approveTransfer that always returns `true` |
| `operatorfilterer/nofilterer/ERC1155NoFilterer.sol` | `abstract` — ERC1155 approveTransfer that always returns `true` |

## External surface (traced)

Both filterers implement the dual ERC721/ERC1155 `approveTransfer` hooks and
advertise both `IERC721CreatorExtensionApproveTransfer` /
`IERC1155CreatorExtensionApproveTransfer` in `supportsInterface`:

- `approveTransfer(address operator, address from, address, uint256[] , uint256[]) → bool` (ERC1155)
- `approveTransfer(address operator, address from, address, uint256) → bool` (ERC721)

Both delegate to internal `isOperatorAllowed(operator, from)`.

**`OperatorFilterer.sol`** additionally has:
- immutables `OPERATOR_FILTER_REGISTRY`, `SUBSCRIPTION`
- `constructor(address operatorFilterRegistry, address subscription)` which calls `registerAndSubscribe(address(this), SUBSCRIPTION)` on the registry.

**`CreatorOperatorFilterer.sol`** additionally has admin-gated config
(`creatorAdminRequired`: `require(IAdminControl(creator).isAdmin(msg.sender), "Wallet is not an admin")`):
- `configureBlockedOperators(address creator, address[] operators, bool[] blocked)`
- `configureBlockedOperatorHashes(address creator, bytes32[] hashes, bool[] blocked)`
- `configureBlockedOperatorsAndHashes(...)` — calls both
- views `getBlockedOperators(creator)`, `getBlockedOperatorHashes(creator)`
- events `OperatorUpdated`, `CodeHashUpdated`; errors `OperatorNotAllowed`, `CodeHashFiltered`
- storage: `EnumerableSet.AddressSet` per creator + `EnumerableSet.Bytes32Set` of blocked code hashes.

## Enforcement mechanism

Both models veto in `isOperatorAllowed`, called from the `approveTransfer` hook
the creator core invokes on each transfer. The `from != operator` guard means a
holder moving their **own** token is never blocked; only third-party operators
are filtered.

**Registry model** (`operatorfilterer/OperatorFilterer.sol` lines 52–59):
```
if (from != operator) {
  if (!IOperatorFilterRegistry(OPERATOR_FILTER_REGISTRY)
        .isOperatorAllowed(address(this), operator))
      revert OperatorNotAllowed(operator);
}
```
The blocklist is external and shared via the subscription set in the constructor.

**Creator model** (`operatorfilterer/CreatorOperatorFilterer.sol` lines 130–144):
checks the per-creator (`msg.sender`) `EnumerableSet` of blocked operators; if
the operator has code, also checks its `codehash` against the filtered-hash set,
reverting `OperatorNotAllowed` / `CodeHashFiltered`. Enforcement data lives
**on this contract**, keyed by the calling creator — no external registry.

Note: the registry model **reverts** on a blocked operator; the creator model
also reverts. Neither returns `false` in the blocked path — they throw custom
errors, which propagate up through the creator core transfer.

## Filterer vs no-filterer distinction

`nofilterer/ERC721NoFilterer.sol` and `ERC1155NoFilterer.sol` are `abstract`
mix-ins whose `approveTransfer(...) external pure returns (bool)` **always
returns `true`** and which advertise the ApproveTransfer interface. They are
inherited by opt-out extension variants (e.g. the frozen-metadata `*NoFilterer`
builds in [[metadata-frozen]]) so a creator with approve-transfer checking on
can install an extension that performs **no** marketplace filtering. Contrast
with [[soulbound]], which uses the same hook to block by transfer semantics
rather than by operator.

## Pitfalls

- **`msg.sender` is the creator contract.** `CreatorOperatorFilterer` keys all
  blocklists by `msg.sender` (the calling creator), so blocklists are per-creator
  even though the extension is a single shared deployment.
- **Registry availability.** `OperatorFilterer` depends on an external
  `IOperatorFilterRegistry`; if that registry is deprecated/removed on-chain, its
  `isOperatorAllowed` behavior — and thus transfers — can change outside the
  creator's control. The creator model avoids this dependency.
- **Own-transfer bypass is intentional** (`from == operator` skips checks) — do
  not treat this as a soulbound guarantee; use [[soulbound]] for that.
- Blocked paths revert (custom errors), they do not silently return `false`;
  callers integrating these must expect reverts, not boolean vetoes.

## Open questions

- Which registry/subscription addresses are wired at deployment for
  `OperatorFilterer` (constructor args) — see deploy scripts / [[shared-libraries]].
- Whether a creator can hold both an operator filterer and soulbound on the same
  approve-transfer slot simultaneously, or only one at a time.
