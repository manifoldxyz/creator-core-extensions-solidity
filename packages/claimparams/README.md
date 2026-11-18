# Claim Params

`ERC721ClaimParams` mints through one ERC721 lazy claim instance and stores a fixed number of bytes ("params") for each token in the same transaction. The claim points its `tokenURI` at this contract (`StorageProtocol.ADDRESS`), which returns JSON with a static `image` and an `animation_url` of `<renderer>?params=0x<hex>&mintOrder=<n>`. An off-chain renderer draws the token from those params.

Design and rules: [SPEC.md](./SPEC.md).

## Requirements

- An ERC721 lazy claim on an extension that supports `StorageProtocol.ADDRESS` (the current lazy claim release; the previous one does not).
- The claim is priced in ETH, has no signing address, and is on a v3+ creator contract. The deploy script checks these.

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
CLAIM=<claim extension> CREATOR_CONTRACT=<creator contract> INSTANCE_ID=<instance id> PARAMS_LENGTH=<bytes> \
  forge script script/DeployERC721ClaimParams.s.sol --rpc-url <rpc> --account <keystore> --broadcast
```

Then, from a creator contract admin wallet:

1. `setRenderer((name, description, imageURI, animationURI))` on the deployed contract.
2. Send the `updateTokenURIParams` calldata the script prints to the claim extension. The `location` argument must be the 20 raw bytes of the deployed address. Block explorer forms send the `0x...` text instead, which the claim rejects.
3. `lockRenderer()` once the renderer is final.
