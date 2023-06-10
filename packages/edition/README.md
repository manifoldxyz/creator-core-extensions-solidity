# Editions

This package contains base extension implementations for creating editioned NFTs (numbered) for use with [Manifold Creator Core](https://github.com/manifoldxyz/creator-core-solidity) contracts. Manifold Creator Core contracts can be deployed via [Manifold Studio](https://studo.manifold.xyz).

## Proxy Platform Extensions
You can deploy customized lightweight Proxy implementations of the following Application Extensions by referring to their templates and deploying against the appropriate network's reference Implementations.

### ERC721 Editions
There are two styles of editions: Prefix Editions and Numbered Editions.

#### Prefix
Prefix Editions assume that all the metadata URI will be prefixed with the same string, and the suffix for each metadata will be the edition number, starting from 1.
e.g.
  prefix = 'https://arweave.net/<HASH>'
  The URI for the first item in the edition will be 'https://arweave.net/{HASH}/1', second will be 'https://arweave.net/{HASH}/2' and so forth.

contracts/ERC721PrefixEditionTemplate.sol and referring to the following implementation addresses:

**Goerli**
```
0x...
```

**Mainnet**
```
0x...
```

#### Numbered
Numbered editions assume that all metadata is unchanging except for the Edition number.  Numbered editions are instantiated by passing the metadata as a 'uriParts' array, which is recomposed to inject the edition number (and total edition count if desired).  Good for open editions.

contracts/ERC721NumberedEditionTemplate.sol and referring to the following implementation addresses:

**Goerli**
```
0x...
```

**Mainnet**
```
0x...
```

### Nifty Gateway Open Editions
Numbered editions which may be used for Nifty Gateway open edition sales.

contracts/nifty/NiftyGatewayERC721NumberedEditionTemplate.sol and referring to the following implementation addresses:

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
