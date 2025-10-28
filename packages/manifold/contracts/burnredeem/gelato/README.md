# Gelato-Enabled Burn Redeem Contracts

Complete implementation of burn redeem contracts with Gelato Relay integration, enabling single-transaction UX for NFT burns without requiring developers to sponsor gas fees.

## 📋 Table of Contents

- [Overview](#overview)
- [Problem & Solution](#problem--solution)
- [Architecture](#architecture)
- [Getting Started](#getting-started)
- [Deployment](#deployment)
- [Frontend Integration](#frontend-integration)
- [Testing](#testing)
- [Gas Costs](#gas-costs)
- [Security Considerations](#security-considerations)
- [FAQ](#faq)

## 🎯 Overview

These contracts extend Manifold's existing burn redeem functionality with **ERC-2771 meta-transaction support** via Gelato Relay, allowing users to:

1. ✅ **Approve NFTs** (standard transaction)
2. ✅ **Sign burn message off-chain** (no gas, instant)
3. ✅ **Gelato submits transaction** (automated)
4. ✅ **User pays all gas fees** (no sponsorship burden for developers)

### Key Benefits

- **Single-Transaction UX**: After initial approval, burns feel instant
- **No Gas Sponsorship**: Users pay gas directly via `callWithSyncFeeERC2771`
- **Universal Compatibility**: Works with ANY ERC721/ERC1155 contract
- **Battle-Tested Infrastructure**: Leverages Gelato's production relay network
- **Backward Compatible**: Existing burn redeem contracts remain functional

## 🔧 Problem & Solution

### The Problem

Traditional burn redeem flow requires **2 transactions**:
```
1. User approves NFT for burn contract  → Costs gas, user waits
2. User calls burn() function           → Costs gas, user waits
```

This creates friction and poor UX.

### The Solution

With Gelato Relay using ERC-2771:
```
1. User approves NFT (one-time per collection) → Costs gas once
2. User SIGNS burn message (instant, free)     → Gelato submits
3. User pays gas via msg.value                 → Included in #2
```

Result: **Appears like a single transaction to the user!**

## 🏗️ Architecture

### Contract Hierarchy

```
GelatoBurnRedeemCore (abstract)
├── Extends GelatoRelayContext (ERC-2771 support)
├── Uses _msgSender() instead of msg.sender
└── Handles gas payment from msg.value

GelatoERC721BurnRedeem
├── Extends GelatoBurnRedeemCore
└── ERC721-specific redeem logic

GelatoERC1155BurnRedeem
├── Extends GelatoBurnRedeemCore
└── ERC1155-specific redeem logic
```

### How ERC-2771 Works

```solidity
// Traditional call
msg.sender = 0xUSER        ✅ Direct from user

// Gelato relay call (ERC-2771)
msg.sender = 0xGELATO      ❌ Relayer address
_msgSender() = 0xUSER      ✅ Original user (decoded from calldata)
```

**The Magic**: GelatoRelayContext appends the original sender to calldata. The trusted forwarder (Gelato) is the only address that can do this securely.

### Gas Payment Flow

```
┌─────────┐
│  User   │ Signs message with ETH payment
└────┬────┘
     │ eth: 1.01 ETH (burn cost: 1 ETH, estimated gas: 0.01 ETH)
     ↓
┌────────────────┐
│ Gelato Relayer │ Submits transaction, pays gas upfront
└────┬───────────┘
     │ msg.value: 1.008 ETH (after Gelato takes ~0.002 ETH fee)
     ↓
┌──────────────────────┐
│ Burn Redeem Contract │ Receives payment, executes burn
└──────────────────────┘
     │
     ├─> Burn cost (1 ETH) → Payment receiver
     └─> Remaining (0.008 ETH) → Refunded to user
```

## 🚀 Getting Started

### Prerequisites

```bash
# Install dependencies
npm install --save-dev @gelatonetwork/relay-context

# Frontend
npm install @gelatonetwork/relay-sdk ethers
```

### Installation

1. **Copy contracts to your project**:
   ```
   contracts/burnredeem/gelato/
   ├── GelatoBurnRedeemCore.sol
   ├── GelatoERC721BurnRedeem.sol
   └── GelatoERC1155BurnRedeem.sol
   ```

2. **Install Gelato relay context**:
   ```bash
   forge install gelatonetwork/relay-context
   ```

3. **Configure remappings** in `foundry.toml`:
   ```toml
   remappings = [
       "@gelatonetwork/relay-context/=lib/relay-context/contracts/"
   ]
   ```

## 📦 Deployment

### Foundry Script

```bash
# Set environment variables
export PRIVATE_KEY=your_private_key
export RPC_URL=your_rpc_url

# Deploy to network
forge script contracts/burnredeem/gelato/scripts/Deploy.s.sol:DeployGelatoBurnRedeem \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify
```

### Deploy to Multiple Networks

```bash
# Set all RPC URLs in .env
MAINNET_RPC_URL=...
POLYGON_RPC_URL=...
BASE_RPC_URL=...

# Deploy everywhere
forge script contracts/burnredeem/gelato/scripts/Deploy.s.sol:DeployToAllNetworks \
  --broadcast \
  --verify
```

### Deployed Addresses

| Network | Chain ID | GelatoERC721BurnRedeem | GelatoERC1155BurnRedeem |
|---------|----------|------------------------|-------------------------|
| Mainnet | 1 | TBD | TBD |
| Polygon | 137 | TBD | TBD |
| Base | 8453 | TBD | TBD |
| Sepolia | 11155111 | TBD | TBD |

**Gelato Trusted Forwarder**: `0xaBcC9b596420A9E9172FD5938620E265a0f9Df92` (all networks)

## 💻 Frontend Integration

### Quick Start

```typescript
import { GelatoRelay } from "@gelatonetwork/relay-sdk";
import { ethers } from "ethers";

// Initialize
const provider = new ethers.BrowserProvider(window.ethereum);
const relay = new GelatoRelay();

// Step 1: Approve NFT (one-time per collection)
const nftContract = new ethers.Contract(nftAddress, nftABI, signer);
await nftContract.setApprovalForAll(burnRedeemAddress, true);

// Step 2: Prepare burn call
const burnRedeemInterface = new ethers.Interface([
  "function burnRedeem(address,uint256,uint32,tuple(uint48,uint48,address,uint256,bytes32[])[]) payable"
]);

const callData = burnRedeemInterface.encodeFunctionData("burnRedeem", [
  creatorAddress,
  instanceId,
  burnCount,
  burnTokens
]);

// Step 3: Submit via Gelato (user pays gas)
const request = {
  chainId: await provider.getNetwork().chainId,
  target: burnRedeemAddress,
  data: callData,
  user: userAddress,
};

const response = await relay.callWithSyncFeeERC2771(
  request,
  signer,
  { gasLimit: 500000n }
);

console.log("Task ID:", response.taskId);
```

### React Hook

See `examples/frontend-integration.ts` for a complete React hook implementation:

```typescript
import { useBurnRedeem } from "./examples/frontend-integration";

function BurnButton() {
  const { burnRedeem, isLoading, error } = useBurnRedeem(
    provider,
    burnRedeemAddress,
    burnCostWei
  );

  const handleBurn = async () => {
    const taskId = await burnRedeem({
      creatorContractAddress,
      instanceId,
      burnRedeemCount: 1,
      burnTokens: [...]
    });

    console.log("Burn submitted:", taskId);
  };

  return (
    <button onClick={handleBurn} disabled={isLoading}>
      {isLoading ? "Burning..." : "Burn & Redeem"}
    </button>
  );
}
```

### Gas Estimation

```typescript
import { estimateTotalPayment } from "./examples/frontend-integration";

const totalPayment = await estimateTotalPayment(
  provider,
  burnRedeemAddress,
  burnParams,
  burnCostWei
);

console.log("User needs to send:", ethers.formatEther(totalPayment), "ETH");
// Output: "User needs to send: 1.012 ETH"
//   ├─ Burn cost: 1.0 ETH
//   ├─ Gas cost: 0.01 ETH
//   └─ Gelato fee: 0.002 ETH
```

## 🧪 Testing

### Run Tests

```bash
# Run all tests
forge test

# Run only Gelato tests
forge test --match-contract GelatoBurnRedeem

# Run with gas reporting
forge test --gas-report

# Run specific test
forge test --match-test test_MsgSenderWithGelatoRelay -vvv
```

### Test Coverage

```bash
forge coverage --report lcov
genhtml lcov.info -o coverage
open coverage/index.html
```

### Key Tests

- ✅ ERC-2771 meta-transaction support
- ✅ `_msgSender()` correctly extracts original sender
- ✅ Gas payment handling
- ✅ Batch burn operations
- ✅ Security (only trusted forwarder can relay)
- ✅ Reentrancy protection

## 💰 Gas Costs

### Typical Gas Usage

| Operation | Gas (Gwei) | Cost @ 30 gwei |
|-----------|------------|----------------|
| Approve NFT (first time) | ~50,000 | ~$0.05 |
| Single burn | ~200,000 | ~$0.20 |
| Batch burn (5 NFTs) | ~500,000 | ~$0.50 |

### Gelato Fees

Gelato charges approximately **10-20%** markup on gas costs:

- Gas cost: 0.01 ETH
- Gelato fee: ~0.002 ETH (20%)
- **Total: 0.012 ETH**

This is the price for not running your own relayer infrastructure!

### Cost Comparison

#### Without Gelato (Traditional)
```
Approve:  50,000 gas = $0.05
Burn:    200,000 gas = $0.20
─────────────────────────────
Total:   250,000 gas = $0.25

User experience: 2 transactions, ~30 seconds
```

#### With Gelato Relay
```
Approve:  50,000 gas = $0.05  (one-time)
Burn:    200,000 gas = $0.20
Gelato:   40,000 gas = $0.04  (20% fee)
─────────────────────────────
Total:   290,000 gas = $0.29

User experience: 1 signature, ~5 seconds
```

**Extra cost: $0.04** for significantly better UX!

## 🔐 Security Considerations

### ERC-2771 Security

1. **Trusted Forwarder**: Only Gelato's forwarder (`0xaBcC...Df92`) can append sender to calldata
2. **Signature Verification**: Gelato verifies user signatures off-chain before relaying
3. **Replay Protection**: Gelato tracks nonces to prevent replay attacks
4. **No Phishing Risk**: Users never send transactions directly to unknown contracts

### Contract Security

```solidity
// ✅ CORRECT: Use _msgSender() for user identity
function burnRedeem(...) external payable {
    address user = _msgSender();  // Gets actual user
    _burnTokens(user, ...);
}

// ❌ INCORRECT: Using msg.sender gets relayer address
function burnRedeem(...) external payable {
    address user = msg.sender;    // Gets Gelato relayer!
    _burnTokens(user, ...);       // WRONG USER!
}
```

### Audit Status

- ⏳ **GelatoBurnRedeemCore**: Not audited yet
- ✅ **BurnRedeemCore (base)**: Previously audited
- ✅ **Gelato Relay**: Audited by [Quantstamp, Certora]

**Recommendation**: Perform security audit before mainnet deployment.

## ❓ FAQ

### Q: Do users need ETH for gas?

**A:** Yes. With `callWithSyncFeeERC2771`, users pay gas fees from the ETH they send with their signed message. This is different from fully gasless (sponsored) transactions.

### Q: Can I make it fully gasless?

**A:** Yes, use `sponsoredCallERC2771` instead, but you'll need to fund a gas tank on Gelato. This creates a sponsorship burden.

### Q: What if a user sends too little ETH?

**A:** The transaction will revert with `InvalidPaymentAmount()`. Frontend should estimate gas and add 20% buffer.

### Q: Does this work with existing burn redeems?

**A:** No. Existing contracts use `msg.sender`. You must deploy new Gelato-enabled contracts. Old contracts remain functional.

### Q: Can users still call directly (without Gelato)?

**A:** Yes! These contracts work both ways:
- Direct call: `msg.sender` = user
- Gelato relay: `_msgSender()` = user

### Q: What about failed transactions?

**A:** Gelato will retry a few times. If it fails, the task status will show `Failed` and users don't pay gas.

### Q: How long does relay take?

**A:** Typically 3-10 seconds, depending on network congestion. Much faster than waiting for user to approve + confirm transaction.

### Q: Can I use this on any EVM chain?

**A:** Gelato Relay supports:
- ✅ Ethereum
- ✅ Polygon
- ✅ Base
- ✅ Arbitrum
- ✅ Optimism
- ✅ And more...

Check [Gelato docs](https://docs.gelato.network) for full list.

### Q: What if Gelato goes down?

**A:** Users can still call functions directly. Your contracts don't depend on Gelato; it's just a UX enhancement.

## 📚 Additional Resources

- [Gelato Relay Documentation](https://docs.gelato.network/developer-services/relay)
- [ERC-2771 Standard](https://eips.ethereum.org/EIPS/eip-2771)
- [Manifold Creator Core](https://github.com/manifoldxyz/creator-core-solidity)
- [Original Burn Redeem Contracts](../README.md)

## 🤝 Contributing

Found a bug or want to contribute? Open an issue or PR!

## 📄 License

MIT License - see LICENSE file for details

---

**Built with ❤️ for Manifold creators**
