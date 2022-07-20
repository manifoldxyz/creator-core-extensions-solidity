# creator-core-extensions-solidity

## The Manifold Creator Core Extension Applications (Apps) Contracts

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

### Platform Extensions
These are extensions that can be installed by any Manifold Creator contract to give enhanced additional functionality.  There is a single deployed instance of these extensions, and every creator contract installs the same instance, and accesses the new functionality via that extension.

#### Manifold ERC721 Edition
Provides a more efficient way to batch mint NFTs to one or many addresses

**Rinkeby**
```
0x53963B7C101c844Ec2A9D63B40e1dc93e5ba4A35
```

**Mainnet**
```
0xc68afc6A3B47b108Db5e48fB53a10D2D9c11b094
```

#### Manifold Lazy Claim
These are ERC721 and ERC1155 Lazy Claim extensions.

**ERC721 Rinkeby**
```
0x3e625b7521fa1ec922bd561b766d80e05316d035
```

**ERC721 Mainnet**
```
0xb08Aa31Cc2B8C0582bE42D38Bb643292e0A4b9EB
```

**ERC1155 Rinkeby**
```
0x30185652e86b922110a28F952E977D6EBbb83d2D
```

**ERC1155 Mainnet**
```
0xca71c5270EFf44Eb6D813A92c0ba12577bDDf208
```

#### Manifold Frozen Metadata
These are ERC721 Frozen Metadata extensions.

**ERC721 Rinkeby**
```
0x1F4B810bf5A9C12cF32ff664144B58e02a6Cb82E
```

**ERC721 Mainnet**
```
0x5bEf5e3274e0574502F618b1d3152a06e9e45AEd
```


### Customized Lightweight Proxies
You can deploy customized lightweight Proxy implementations of the following Application Extensions by referring to their templates and deploying against the appropriate network's reference Implementations.

#### ERC721 Editions
There are two styles of editions: Prefix Editions and Numbered Editions.

##### Prefix
Prefix Editions assume that all the metadata URI will be prefixed with the same string, and the suffix for each metadata will be the edition number, starting from 1.
e.g.
  prefix = 'https://arweave.net/<HASH>'
  The URI for the first item in the edition will be 'https://arweave.net/{HASH}/1', second will be 'https://arweave.net/{HASH}/2' and so forth.

contracts/edition/ERC721PrefixEditionTemplate.sol and referring to the following implementation addresses:

**Rinkeby**
```
0x3AD50422Ac43D4F0E30AAF73A0b07A907618C548
```

**Mainnet**
```
0x...
```

##### Numbered
Numbered editions assume that all metadata is unchanging except for the Edition number.  Numbered editions are instantiated by passing the metadata as a 'uriParts' array, which is recomposed to inject the edition number (and total edition count if desired).  Good for open editions.

contracts/edition/ERC721NumberedEditionTemplate.sol and referring to the following implementation addresses:

**Rinkeby**
```
0x211AAcd0b144F1e51b2633D38d8Ac2F864dE7042
```

**Mainnet**
```
0x...
```


#### Nifty Gateway Open Editions
Numbered editions which may be used for Nifty Gateway open edition sales.

contracts/edition/nifty/NiftyGatewayERC721NumberedEditionTemplate.sol and referring to the following implementation addresses:

**Rinkeby**
```
0xFB19a709486e758DfC340F9ad1AAd2bD604cf30d
```

**Mainnet**
```
0x...
```

## Running the package unit tests

Visit the [github repo](https://github.com/manifoldxyz/creator-core-extensions-solidity) and clone the repo.  It uses the truffle framework and ganache-cli.

Install both:
```
npm install -g truffle
npm install -g ganache-cli
```

### install dependencies
npm install

### Compile
truffle compile

### Start development server
ganache-cli -l 20000000

### Deploy migrations
truffle migrate

### Run tests
truffle test

