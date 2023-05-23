# The Manifold Creator Core Extension Applications (Apps) Contracts

**A library of base implementations and examples Apps for use with [Manifold Creator Core](https://github.com/manifoldxyz/creator-core-solidity).**

This repo contains reference implementations and examples for apps that you can add to any Manifold Creator Core contract.  Examples include:
 * Platform level extensions (for examples, see contracts/manifold, which are singular extensions that can be installed by every contract to enable new functionality)
 * ERC721 Editions
 * ERC721 Enumerable subcollection
 * Dynamic NFTs
 * Redemption mechanics (claim or burn and redeem)

## Overview

### Installation

```console
$ npm install @manifoldxyz/creator-core-extensions-solidity
```

### Usage

Once installed, you can use the contracts in the library by importing and extending them.  To add an app to a Creator Core contract, you need to approve the app by calling:

```
registerExtension(address extension, string memory baseURI)
```

baseURI can be blank if you are overriding the tokenURI functionality.

See the [developer documentation](https://docs.manifold.xyz/v/manifold-for-developers/manifold-creator-architecture/contracts/extensions) for further info about Extension Applications.

## Non-Proxy Platform Extensions
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
| 1 (Mainnet) | ERC721      | 0x074eaee8fc3e4e2b361762253f83d9a94aec6fd4 |
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

## Proxy Platform Extensions
You can deploy customized lightweight Proxy implementations of the following Application Extensions by referring to their templates and deploying against the appropriate network's reference Implementations.

#### ERC721 Editions
There are two styles of editions: Prefix Editions and Numbered Editions.

##### Prefix
Prefix Editions assume that all the metadata URI will be prefixed with the same string, and the suffix for each metadata will be the edition number, starting from 1.
e.g.
  prefix = 'https://arweave.net/<HASH>'
  The URI for the first item in the edition will be 'https://arweave.net/{HASH}/1', second will be 'https://arweave.net/{HASH}/2' and so forth.

contracts/edition/ERC721PrefixEditionTemplate.sol and referring to the following implementation addresses:

**Goerli**
```
0x...
```

**Mainnet**
```
0x...
```

##### Numbered
Numbered editions assume that all metadata is unchanging except for the Edition number.  Numbered editions are instantiated by passing the metadata as a 'uriParts' array, which is recomposed to inject the edition number (and total edition count if desired).  Good for open editions.

contracts/edition/ERC721NumberedEditionTemplate.sol and referring to the following implementation addresses:

**Goerli**
```
0x...
```

**Mainnet**
```
0x...
```


#### Nifty Gateway Open Editions
Numbered editions which may be used for Nifty Gateway open edition sales.

contracts/edition/nifty/NiftyGatewayERC721NumberedEditionTemplate.sol and referring to the following implementation addresses:

**Goerli**
```
0x...
```

**Mainnet**
```
0x...
```

#### Collectible ERC721 Shared Contract

**Goerli**
```
0x546B820779ceC2337380cE15E2Ff62BDb96ABa4E
```

**Mainnet**
```
0xDb707aF289d5a63Bd72E6761f0E91B414485D42A
```


## Running the package unit tests

Visit the [github repo](https://github.com/manifoldxyz/creator-core-extensions-solidity) and clone the repo.  It uses the truffle framework and ganache-cli.

Install both:
```
yarn global add truffle
yarn global add ganache-cli
```

Then:
```
### install dependencies
yarn

### Compile
truffle compile

### Start development server
ganache-cli -l 20000000

### Deploy migrations
truffle migrate

### Run tests
truffle test
```
