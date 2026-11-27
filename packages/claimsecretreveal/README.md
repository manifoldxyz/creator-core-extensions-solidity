# Claim Secret Reveal

`ERC721ClaimSecretReveal` is a `tokenURI` source for ERC721 lazy claims (`StorageProtocol.ADDRESS`). Every token shows one cover until a creator contract admin reveals a secret committed at deploy (`COMMIT = sha256(secret)`). After that, each token's `animation_url` is `<renderer>?payload=<base64 JSON>` with a hash, the edition number (mint order) and a key `HMAC-SHA256(secret, keyPrefix + edition)`, which an off-chain renderer checks before drawing the token.

Design and rules: [SPEC.md](./SPEC.md).

## Requirements

- An ERC721 lazy claim on an extension that supports `StorageProtocol.ADDRESS` (the current lazy claim release; the previous one does not).
- Claim `totalMax` no higher than `SUPPLY`.

## Setup

```bash
git submodule update --init lib/forge-std
npm install
forge build
```

The claim contracts are imported from `../manifold` through `remappings.txt`.

## Test

```bash
forge test --no-match-contract Fork                    # unit tests
SEPOLIA_RPC_URL=<rpc> forge test --match-contract Fork # against the live Sepolia claim extensions
```

## Deploy

```bash
CREATOR_CONTRACT=<creator contract> COMMIT=<0x sha256 of the secret> SUPPLY=<editions> KEY_PREFIX=<prefix> \
NAME=<token name> DESCRIPTION=<description> IMAGE_URI=<cover image> ANIMATION_URI=<renderer> \
  forge script script/DeployERC721ClaimSecretReveal.s.sol --rpc-url <rpc> --account <keystore> --broadcast
```

Then point an ERC721 claim at the deployed address:

- In Studio: create an Edition on an ERC-721 contract, artwork type Onchain, with the deployed address as the art contract.
- Or for an existing claim: set `CLAIM=<claim extension> INSTANCE_ID=<instance id>` when running the script and send the `updateTokenURIParams` calldata it prints from a creator contract admin wallet. The `location` argument must be the 20 raw bytes of the deployed address. Block explorer forms send the `0x...` text instead, which the claim rejects.

After the claim closes, a creator contract admin calls `reveal(secret)` with the 32-byte secret.
