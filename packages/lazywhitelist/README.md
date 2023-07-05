# Lazy Mint With Whitelist

This package contains base extension implementations for creating lazy mint NFTs with whitelist for use with [Manifold Creator Core](https://github.com/manifoldxyz/creator-core-solidity) contracts. Manifold Creator Core contracts can be deployed via [Manifold Studio](https://studo.manifold.xyz).

## Proxy Platform Extensions
You can deploy customized lightweight Proxy implementations of the following Application Extensions by referring to their templates and deploying against the appropriate network's reference Implementations.

### ERC721 Lazy Whitelist
contracts/ERC721LazyMintWhitelistTemplate.sol and referring to the following implementation addresses:

**Goerli**
```
0x...
```

**Mainnet**
```
0x...
```

### Usage
To add an extension to a Creator Core contract, you need to approve the app by calling:

```
registerExtension(address extension, string memory baseURI)
```

baseURI can be blank if you are overriding the tokenURI functionality.

See the [developer documentation](https://docs.manifold.xyz/v/manifold-for-developers/manifold-creator-architecture/contracts/extensions) for further info about Extension Applications.


## Running the package unit tests

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
