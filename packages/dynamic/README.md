# Dynamic NFTs

This package contains example extensions to create Dynamic NFTs for use with [Manifold Creator Core](https://github.com/manifoldxyz/creator-core-solidity) contracts. Manifold Creator Core contracts can be deployed via [Manifold Studio](https://studo.manifold.xyz).

Examples include:
* DynamicSVGExample.sol - Example of an on-chain dynamic SVG NFT
* TimeToken.sol - An example of an NFT that changes based on time.

## Overview

### Usage
To add an extension to a Creator Core contract, you need to approve the app by calling:

```
registerExtension(address extension, string memory baseURI)
```

baseURI can be blank if you are overriding the tokenURI functionality.

See the [developer documentation](https://docs.manifold.xyz/v/manifold-for-developers/manifold-creator-architecture/contracts/extensions) for further info about Extension Applications.


## Running the package unit tests
### Compile
```
forge build
```

### Run tests
```
forge test
```