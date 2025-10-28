## # True Single-Transaction Burn Redeem Guide

## 🎯 The Challenge

When burning NFTs from multiple collections, users face a UX nightmare:

```
❌ Traditional Flow:
1. Approve NFT Collection A  → Transaction 1, wait ~15 sec
2. Approve NFT Collection B  → Transaction 2, wait ~15 sec
3. Approve NFT Collection C  → Transaction 3, wait ~15 sec
4. Burn & Redeem            → Transaction 4, wait ~15 sec
───────────────────────────────────────────────────────
Total: 4 transactions, ~60 seconds, multiple signatures
```

**The problem gets worse** with large batch burns requiring 5, 10, or even 20+ different NFT collections!

---

## ✅ The Solution: Two Approaches

### **Approach 1: Direct Gelato Integration** (Simplest)
Best for: Single NFT collection or infrequent burns

### **Approach 2: Multicall Helper** (Most Powerful)
Best for: Multiple NFT collections or frequent burns

---

## 📖 Approach 1: Direct Gelato Integration

### How It Works

```
Setup (One-time per collection):
User approves each NFT collection → 1 transaction per collection

Every Burn After:
User signs message → Gelato submits → Done!
───────────────────────────────────────────────
Result: After setup, burns are single-signature
```

### When to Use

✅ **Use when:**
- Burning from 1-2 NFT collections
- First-time setup is acceptable
- Want simplest implementation

❌ **Don't use when:**
- Burning from 5+ collections regularly
- Setup cost is too high
- Want truly frictionless experience

### Implementation

See `examples/frontend-integration.ts`:

```typescript
// One-time setup
await nftContract.setApprovalForAll(burnRedeemAddress, true);

// Every burn (single signature!)
await relay.callWithSyncFeeERC2771(burnRequest, signer);
```

**Cost Analysis:**
- Setup: N transactions (one per NFT collection)
- Each burn after: 1 signature (~5 seconds)

---

## 🚀 Approach 2: Multicall Helper (RECOMMENDED)

### How It Works

```
Setup (One-time per collection):
User approves Multicall Helper for each NFT collection
→ 1 transaction per collection (same as Approach 1)

Every Burn After:
User signs message → Gelato submits to Multicall Helper:
  ├─ Transfer NFTs from user to helper
  ├─ Approve burn redeem contract
  ├─ Execute burn
  └─ Return minted tokens to user
───────────────────────────────────────────────
Result: After setup, burns are truly single-signature
```

### Why This Works

The multicall helper acts as an intermediary:

1. **User approves helper** (one-time)
2. **Helper transfers** user's NFTs to itself (during burn transaction)
3. **Helper approves** burn contract for those NFTs
4. **Helper calls** burn redeem
5. **Helper forwards** minted tokens back to user

**All steps 2-5 happen in ONE Gelato relay transaction!**

### Implementation

#### Contract: `GelatoBurnRedeemMulticallV2.sol`

```solidity
contract GelatoBurnRedeemMulticallV2 {
    function transferAndBurn(
        address[] calldata nftContracts,
        uint256[] calldata tokenIds,
        uint256[] calldata amounts,
        uint8[] calldata tokenSpecs,
        address burnRedeemContract,
        // ... burn parameters
    ) external payable;
}
```

#### Frontend: `single-transaction-integration.ts`

```typescript
// ONE-TIME SETUP (per NFT collection)
for (const nftContract of nftContracts) {
  await nftContract.setApprovalForAll(multicallAddress, true);
}

// EVERY BURN (single signature!)
await trueSingleTransactionBurn(
  provider,
  multicallAddress,
  burnRedeemAddress,
  burnParams,
  ethPayment
);
```

### When to Use

✅ **Use when:**
- Burning from 3+ NFT collections
- Burns happen frequently
- Want best possible UX after setup
- Building for power users

❌ **Don't use when:**
- Only burning from 1 collection
- Extra contract complexity is unwanted
- Users are one-time burners (setup cost not worth it)

---

## 📊 Comparison

| Aspect | Approach 1 (Direct) | Approach 2 (Multicall) |
|--------|---------------------|------------------------|
| **Setup Cost** | N approvals | N approvals (same) |
| **Burn UX** | 1 signature | 1 signature (same) |
| **Burn Gas** | ~200k | ~300k (+transfers) |
| **Complexity** | Low | Medium |
| **Best For** | 1-2 collections | 3+ collections |

---

## 💡 Recommended Strategy

### For Most Users

**Start with Approach 1** (Direct Integration):
- Simpler implementation
- Lower gas per burn
- Good enough for most use cases

**Upgrade to Approach 2** when:
- Users complain about setup cost
- You have 5+ collection campaigns
- Burns are frequent enough to justify setup

### For Power Users

**Go straight to Approach 2**:
- Best UX after setup
- Scales to any number of collections
- Worth the extra gas and complexity

---

## 🛠️ Implementation Examples

### Example 1: Single Collection Burn

**Collection:** CoolPunks #1234

```typescript
// Setup (once)
await coolPunks.setApprovalForAll(burnRedeemAddress, true);

// Burn (every time)
await burnWithGelatoRelay(provider, burnRedeemAddress, params, ethPayment);
```

**User Experience:**
- Setup: 1 transaction (~15 seconds)
- Burns: 1 signature (~5 seconds each)

---

### Example 2: Multi-Collection Burn with Multicall

**Collections:**
- CoolPunks #1234
- BoredApes #567
- Doodles #890

```typescript
// Setup (once per collection)
await coolPunks.setApprovalForAll(multicallAddress, true);
await boredApes.setApprovalForAll(multicallAddress, true);
await doodles.setApprovalForAll(multicallAddress, true);

// Burn all in ONE signature!
await trueSingleTransactionBurn(
  provider,
  multicallAddress,
  burnRedeemAddress,
  {
    burnTokens: [
      { contractAddress: coolPunksAddress, id: 1234, ... },
      { contractAddress: boredApesAddress, id: 567, ... },
      { contractAddress: doodlesAddress, id: 890, ... },
    ]
  },
  ethPayment
);
```

**User Experience:**
- Setup: 3 transactions (~45 seconds one-time)
- Burns: 1 signature (~5 seconds each)
- **Future burns of these collections: No additional setup!**

---

## 🎮 Advanced: Batch Multiple Campaigns

Burn across different campaigns in ONE signature:

```typescript
await batchBurnSingleSignature(
  provider,
  multicallAddress,
  burnRedeemAddress,
  [
    { instanceId: 1, burnTokens: [...] },  // Campaign 1
    { instanceId: 2, burnTokens: [...] },  // Campaign 2
    { instanceId: 3, burnTokens: [...] },  // Campaign 3
  ],
  totalEthPayment
);
```

**User signs once, burns for 3 campaigns simultaneously!**

---

## 💰 Cost Analysis

### Setup Costs (Both Approaches)

| Action | Gas | Cost @ 30 gwei |
|--------|-----|----------------|
| Approve 1 NFT collection | ~50,000 | $0.05 |
| Approve 5 NFT collections | ~250,000 | $0.25 |
| Approve 10 NFT collections | ~500,000 | $0.50 |

**This is the same for both approaches!**

### Per-Burn Costs

#### Approach 1 (Direct):
| Operation | Gas | Cost |
|-----------|-----|------|
| Burn | 200,000 | $0.20 |
| Gelato fee (20%) | 40,000 | $0.04 |
| **Total** | **240,000** | **$0.24** |

#### Approach 2 (Multicall):
| Operation | Gas | Cost |
|-----------|-----|------|
| Transfer NFTs to helper | 50,000 | $0.05 |
| Approve burn contract | 50,000 | $0.05 |
| Burn | 200,000 | $0.20 |
| Gelato fee (20%) | 60,000 | $0.06 |
| **Total** | **360,000** | **$0.36** |

**Multicall costs ~$0.12 more per burn** but provides superior batching.

---

## 🔐 Security Considerations

### Approach 1 (Direct)
- ✅ No intermediary contracts
- ✅ Direct interaction with burn redeem
- ✅ Simpler attack surface

### Approach 2 (Multicall)
- ⚠️ Multicall contract holds approval
- ✅ ERC-2771 ensures user control
- ✅ No custody of tokens (transfers immediately)
- ⚠️ Requires auditing multicall logic

**Recommendation:** Audit multicall contract before production use.

---

## 🎯 Decision Matrix

### Choose Approach 1 (Direct) if:
- [ ] Burning from 1-2 collections
- [ ] Users are one-time burners
- [ ] Want simplest code
- [ ] Lower per-burn gas is critical

### Choose Approach 2 (Multicall) if:
- [ ] Burning from 3+ collections
- [ ] Users burn frequently
- [ ] Setup cost is acceptable
- [ ] Want best post-setup UX

---

## 📚 File Reference

| File | Description |
|------|-------------|
| `GelatoBurnRedeemCore.sol` | Base contract with ERC-2771 |
| `GelatoERC721BurnRedeem.sol` | ERC721 implementation |
| `examples/frontend-integration.ts` | Approach 1 (Direct) |
| `GelatoBurnRedeemMulticallV2.sol` | Multicall helper |
| `examples/single-transaction-integration.ts` | Approach 2 (Multicall) |

---

## 🚦 Quick Start

### For Approach 1 (Simpler):
1. Deploy `GelatoERC721BurnRedeem`
2. Use `frontend-integration.ts` examples
3. Have users approve burn contract
4. Burns are single-signature!

### For Approach 2 (Power Users):
1. Deploy `GelatoERC721BurnRedeem`
2. Deploy `GelatoBurnRedeemMulticallV2`
3. Use `single-transaction-integration.ts` examples
4. Have users approve multicall helper
5. Burns are single-signature with batching!

---

## ❓ FAQ

### Q: Do users ever need to approve again after setup?
**A:** No! Once they approve the helper (Approach 2) or burn contract (Approach 1), all future burns from those collections are single-signature.

### Q: What if I add a new NFT collection to the burn requirements?
**A:** Users need one more approval transaction for the new collection. Then it's single-signature again.

### Q: Can I mix both approaches?
**A:** Yes! Use Approach 1 for simple burns, Approach 2 for complex batches.

### Q: Which approach does less gas in the long run?
**A:**
- **Approach 1** if burning once per setup
- **Approach 2** if burning 3+ times per setup (batching savings offset higher per-burn cost)

### Q: Is Gelato required?
**A:** For single-signature UX, yes. Without Gelato, users still need to approve separately (2+ transactions).

---

## 🎉 Conclusion

Both approaches achieve **single-signature burns** after setup. The difference is:

- **Approach 1**: Simple, direct, lower gas per burn
- **Approach 2**: Complex, batching, better for power users

**For most projects, start with Approach 1 and upgrade to Approach 2 if needed!**
