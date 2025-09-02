# ERC1155SerendipityWithAllowlist Deployment Guide

## Overview

This guide covers the deployment and integration of the ERC1155SerendipityWithAllowlist contract, which adds merkle tree-based allowlist functionality to the Serendipity blind mint system.

## Prerequisites

- Node.js 16+ and npm installed
- Truffle or Hardhat for deployment
- Access to an Ethereum RPC endpoint
- Admin access to Creator Core contracts

## Contract Architecture

The ERC1155SerendipityWithAllowlist extends the base ERC1155Serendipity contract with:
- Merkle tree allowlist support for controlled minting
- Per-wallet limits for non-merkle claims
- Bitmap-based index tracking for gas efficiency
- Full backward compatibility with existing claims

## Deployment Steps

### 1. Compile Contracts

```bash
npm run compile
```

### 2. Deploy Contract

Using the deployment script:

```javascript
const ERC1155SerendipityWithAllowlist = artifacts.require("ERC1155SerendipityWithAllowlist");

module.exports = async function(deployer, network, accounts) {
  const owner = accounts[0]; // Or your desired owner address
  await deployer.deploy(ERC1155SerendipityWithAllowlist, owner);
  
  const instance = await ERC1155SerendipityWithAllowlist.deployed();
  console.log("Contract deployed at:", instance.address);
  
  // Set signer address for delivery phase
  await instance.setSigner(SIGNER_ADDRESS);
};
```

### 3. Register with Creator Core

```javascript
// Register the extension with your Creator Core contract
const creatorCore = await CreatorCore.at(CREATOR_CORE_ADDRESS);
await creatorCore.registerExtension(
  serendipityAddress,
  "override" // or appropriate permission string
);
```

## Creating Allowlisted Claims

### 1. Generate Merkle Tree

```javascript
const { MerkleTree } = require('merkletreejs');
const keccak256 = require('keccak256');

// Create allowlist with addresses and mint indices
const allowlist = [
  { address: '0x...', mintIndex: 0 },
  { address: '0x...', mintIndex: 1 },
  // ...
];

// Generate leaves
const leaves = allowlist.map(entry => 
  keccak256(Buffer.concat([
    Buffer.from(entry.address.slice(2), 'hex'),
    Buffer.from(entry.mintIndex.toString(16).padStart(8, '0'), 'hex')
  ]))
);

// Create tree
const tree = new MerkleTree(leaves, keccak256, { sortPairs: true });
const merkleRoot = tree.getHexRoot();
```

### 2. Initialize Claim with Merkle Root

```javascript
const claimParameters = {
  storageProtocol: 3, // IPFS
  totalMax: 1000,
  startDate: Math.floor(Date.now() / 1000),
  endDate: Math.floor(Date.now() / 1000) + 86400 * 30, // 30 days
  tokenVariations: 5,
  location: "QmXxx...", // IPFS hash
  paymentReceiver: "0x...",
  cost: ethers.utils.parseEther("0.1"),
  erc20: "0x0000000000000000000000000000000000000000", // ETH payments
  merkleRoot: merkleRoot, // NEW: Add merkle root
  walletMax: 0 // 0 for merkle claims, or set limit for public claims
};

await serendipity.initializeClaim(
  creatorCoreAddress,
  instanceId,
  claimParameters
);
```

## Frontend Integration

### 1. Generate Merkle Proof for User

```javascript
function getMerkleProof(userAddress, mintIndex, tree) {
  const leaf = keccak256(Buffer.concat([
    Buffer.from(userAddress.slice(2), 'hex'),
    Buffer.from(mintIndex.toString(16).padStart(8, '0'), 'hex')
  ]));
  
  return tree.getHexProof(leaf);
}
```

### 2. Check if Index is Available

```javascript
const isAvailable = await serendipity.checkMintIndex(
  creatorCoreAddress,
  instanceId,
  mintIndex
);

if (isAvailable) {
  console.log("Index has already been minted");
}
```

### 3. Mint with Merkle Proof

```javascript
const proof = getMerkleProof(userAddress, mintIndex, tree);
const mintCount = 1;
const cost = await serendipity.getClaim(creatorCoreAddress, instanceId);
const totalCost = cost.cost.add(MINT_FEE).mul(mintCount);

await serendipity.mintReserve(
  creatorCoreAddress,
  instanceId,
  mintCount,
  proof,
  mintIndex,
  { value: totalCost }
);
```

### 4. Batch Minting with Multiple Proofs

```javascript
const indices = [0, 1, 2];
const proofs = indices.map(index => getMerkleProof(userAddress, index, tree));
const mintCounts = [1, 1, 1];

await serendipity.mintReserve(
  creatorCoreAddress,
  instanceId,
  indices,
  proofs,
  mintCounts,
  { value: totalCost }
);
```

## Public Minting (No Allowlist)

For claims without merkle roots (public minting):

```javascript
const claimParameters = {
  // ... other parameters
  merkleRoot: "0x0000000000000000000000000000000000000000000000000000000000000000",
  walletMax: 5 // Limit per wallet
};

// Users can mint without proofs
await serendipity.mintReserve(
  creatorCoreAddress,
  instanceId,
  mintCount,
  { value: totalCost }
);
```

## Delivery Phase

The delivery phase remains unchanged from the original Serendipity:

```javascript
// Admin delivers randomized variations
const mints = [
  {
    creatorContractAddress: creatorCoreAddress,
    instanceId: instanceId,
    variationMints: [
      { variationIndex: 1, recipient: user1, amount: 1 },
      { variationIndex: 3, recipient: user2, amount: 1 },
      // ...
    ]
  }
];

await serendipity.deliverMints(mints);
```

## Migration from Existing Claims

Existing claims without merkle roots continue to work without modification. To add allowlist functionality to new claims:

1. Deploy the new ERC1155SerendipityWithAllowlist contract
2. Register it with Creator Core
3. Create new claims with merkle roots
4. Existing claims on the old contract remain functional

## Gas Considerations

- Merkle proof validation adds ~20,000-30,000 gas per mint
- Bitmap storage is highly efficient (256 indices per storage slot)
- Batch minting is more gas-efficient for multiple mints
- Public minting (no merkle) has minimal overhead

## Security Best Practices

1. **Merkle Tree Generation**:
   - Always sort pairs when creating trees
   - Use consistent leaf encoding
   - Store merkle trees securely for proof generation

2. **Frontend Security**:
   - Validate proofs client-side before submission
   - Check mint availability before attempting
   - Handle failed transactions gracefully

3. **Admin Operations**:
   - Secure signer private keys
   - Use multi-sig for owner functions
   - Monitor for unusual minting patterns

## Troubleshooting

### Common Issues

1. **"Invalid merkle proof"**
   - Ensure leaf construction matches contract
   - Verify tree uses keccak256 and sorts pairs
   - Check address and index encoding

2. **"Mint index already used"**
   - Use checkMintIndex before attempting
   - Each index can only be used once per claim

3. **"Too many requested"**
   - Check walletMax limits
   - Verify total supply not exceeded

## API Reference

### Key Functions

- `initializeClaim()` - Create new claim with optional merkle root
- `mintReserve()` - Reserve mints with merkle proof
- `checkMintIndex()` - Check if index is available
- `checkMintIndices()` - Batch check multiple indices
- `getTotalMints()` - Get wallet mint count (non-merkle)
- `deliverMints()` - Admin delivers variations

### Events

- `SerendipityClaimInitialized` - New claim created
- `SerendipityMintReserved` - Mints reserved
- `SerendipityClaimUpdated` - Claim parameters updated

## Support

For issues or questions:
- Review test files in `/test/gacha/`
- Check existing implementations in `/contracts/gachaclaims/`
- Consult the main Serendipity documentation