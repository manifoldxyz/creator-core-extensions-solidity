# creator-core-extensions-solidity

## The Manifold Creator Core Extension Applications (Apps) Contracts

**A library of base implementations and examples Apps for use with [Manifold Creator Core](https://github.com/manifoldxyz/creator-core-solidity).**

This repo contains refrence implmentations and examples for apps that you can add to any Manifold Creator Core contract.  Examples include:
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

See the [Manifold Creator Core repo](https://github.com/manifoldxyz/creator-core-solidity) for further info about Extension Applications.

### Customized Lightweight Proxies
You can deploy customized lightweight Proxy implementations of the following Application Extensions by referring to their templates and deploying against the appropriate network's reference Implementations.

#### ERC721 Editions
There are two styles of editions: Prefix Editions and Numbered Editions.

##### Prefix
Prefix Editions assume that all the metadata URI will be prefixed with the same string, and the suffix for each metadata will be the edition number, starting from 1.
e.g.
  prefix = 'https://arweave.net/<HASH>'
  The URI for the first item in the edition will be 'https://arweave.net/<HASH>/1', second will be 'https://arweave.net/<HASH>/2' and so forth.

contracts/edition/ERC721PrefixEditionTemplate.sol and referring to the following implementation addresses:

**Rinkeby**
```
0x
```

**Mainnet**
```
0x...
```

##### Numbered
Numbered editions assume that all metadata is unchanging except for the Edition number.  Numbered editions are instantiated by passing the metadata as a 'uriParts' array, which is recomposed to inject the edition number (and total edition count if desired).

contracts/edition/ERC721NumberedEditionTemplate.sol and referring to the following implementation addresses:

**Rinkeby**
```
0x
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
0x
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
ganache-cli

### Deploy migrations
truffle migrate

### Run tests
truffle test

