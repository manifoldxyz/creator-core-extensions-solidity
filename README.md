# creator-core-extensions-solidity

## The Manifold Creator Core Extension Applications (Apps) Contracts

**A library of base implementations and examples Apps for use with [Manifold Creator Core](https://github.com/manifoldxyz/creator-core-solidity).**

This repo contains refrence implmentations and examples for apps that you can add to any Manifold Creator Core contract.  Examples include:
 * ERC721 Airdrop
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

