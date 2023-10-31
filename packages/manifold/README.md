# Manifold Shared Contract Extensions

This package contains shared contract extensions used with [Manifold Creator Core](https://github.com/manifoldxyz/creator-core-solidity) contracts. Manifold Creator Core contracts can be deployed via [Manifold Studio](https://studo.manifold.xyz).

## Overview

These are extensions that can be installed by any Manifold Creator contract to give enhanced additional functionality.  There is a single deployed instance of these extensions, and every creator contract installs the same instance, and accesses the new functionality via that extension.

#### Manifold ERC721 Edition
Provides a more efficient way to batch mint NFTs to one or many addresses

**Goerli**
```
0x9cac159ec266E76ed7377b801f3b5d2cC7bcf40d
```

**Mainnet**
```
0xc68afc6A3B47b108Db5e48fB53a10D2D9c11b094
```

#### Manifold Lazy Claim
These are the latest Claim Page extensions.

| Network     | Spec        | Address                                    |
| ----------- | ----------- | ------------------------------------------ |
| 1 (Mainnet) | ERC721      | 0x1EB73FEE2090fB1C20105d5Ba887e3c3bA14a17E |
| 2 (Goerli)  | ERC721      | 0x074eaee8fc3e4e2b361762253f83d9a94aec6fd4 |
| 1 (Mainnet) | ERC1155     | 0xDb8d79C775452a3929b86ac5DEaB3e9d38e1c006 |
| 2 (Goerli)  | ERC1155     | 0x73CA7420625d312d1792Cea60Ced7B35D009322c |


#### Manifold Burn Redeem
These are the latest Burn Redeem extensions.

| Network     | Output Token Spec        | Address                                    |
| ----------- | ------------------------ | ------------------------------------------ |
| 1 (Mainnet) | ERC721                   | 0xd391032fec8877953C51399C7c77fBcc93eE3E2A |
| 2 (Goerli)  | ERC721                   | 0x1aebd9fb121f33c37bbc6054ca50862249a39f66 |
| 1 (Mainnet) | ERC1155                  | 0xde659726CfD166aCa4867994d396EFeF386EAD68 |
| 2 (Goerli)  | ERC1155                  | 0x193bFD86F329508351ae899A92a963d5bfC77190 |


#### OperatorFilterer
Shared extension to support OpenSea's Operator Filter Registry

contracts/manifold/operatorfilterer/OperatorFilterer.sol and referring to the following implementation addresses:

**Goerli**
```
0x851b63Bf5f575eA68A84baa5Ff9174172E4d7838   # Subscribed to OpenSea's registry
```

**Mainnet**
```
0x1dE06D2875453a272628BbB957077d18eb4A84CD  # Subscribed to OpenSea's registry
```

#### CreatorOperatorFilterer
Shared extension to support Creator Controlled operator filters

**Goerli**
```
0x1CCCeFAD6E9a3226C2A218662EdF7D465D184893
```

**Mainnet**
```
0x3E31CB740351D8650b36e8Ece95A8Efcd1fc28C2
```
### Usage

You can use install these extesnions via [Manifold Studio](https://studo.manifold.xyz) Apps.

```
registerExtension(address extension, string memory baseURI)
```

baseURI can be blank if you are overriding the tokenURI functionality.

See the [developer documentation](https://docs.manifold.xyz/v/manifold-for-developers/manifold-creator-architecture/contracts/extensions) for further info about Extension Applications.


## Running the package unit tests
### Install dependencies
```
npm install
```

### Compile
```
forge build
```

### Run tests
```
forge test
```
