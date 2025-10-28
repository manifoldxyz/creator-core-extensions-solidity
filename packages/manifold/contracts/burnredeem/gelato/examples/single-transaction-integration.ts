/**
 * TRUE Single-Transaction Burn Redeem Integration
 *
 * This file demonstrates how to use GelatoBurnRedeemMulticall to batch
 * ALL approvals + burn into a SINGLE user signature.
 *
 * Previous approach:
 * - Transaction 1: Approve NFT collection A
 * - Transaction 2: Approve NFT collection B
 * - Transaction 3: Approve NFT collection C
 * - Transaction 4: Sign burn (Gelato submits)
 * Total: 4 transactions
 *
 * New approach:
 * - User signs ONCE (Gelato submits everything)
 *   ├─ Approve NFT collection A
 *   ├─ Approve NFT collection B
 *   ├─ Approve NFT collection C
 *   └─ Execute burn
 * Total: 1 signature, feels instant to user!
 */

import { ethers } from "ethers";
import { GelatoRelay, SponsoredCallRequest } from "@gelatonetwork/relay-sdk";

// ============================================================================
// TYPES
// ============================================================================

interface BurnToken {
  groupIndex: number;
  itemIndex: number;
  contractAddress: string;
  id: bigint;
  merkleProof: string[];
}

interface BurnRedeemParams {
  creatorContractAddress: string;
  instanceId: bigint;
  burnRedeemCount: number;
  burnTokens: BurnToken[];
}

// Token spec enum: 0 = ERC721, 1 = ERC1155
enum TokenSpec {
  ERC721 = 0,
  ERC1155 = 1
}

// ============================================================================
// TRUE SINGLE-TRANSACTION BURN
// ============================================================================

/**
 * Burn NFTs with ALL approvals + burn in ONE user signature
 *
 * @param provider - Ethers provider
 * @param multicallAddress - Address of GelatoBurnRedeemMulticall contract
 * @param burnRedeemAddress - Address of GelatoBurnRedeem contract
 * @param params - Burn redeem parameters
 * @param ethPayment - Total ETH (burn cost + gas)
 * @returns Task ID from Gelato relay
 */
async function trueSingleTransactionBurn(
  provider: ethers.BrowserProvider,
  multicallAddress: string,
  burnRedeemAddress: string,
  params: BurnRedeemParams,
  ethPayment: bigint
): Promise<string> {
  const relay = new GelatoRelay();
  const signer = await provider.getSigner();
  const userAddress = await signer.getAddress();
  const chainId = (await provider.getNetwork()).chainId;

  // Step 1: Identify all unique NFT contracts and their types
  const nftContractsMap = new Map<string, TokenSpec>();

  for (const token of params.burnTokens) {
    if (!nftContractsMap.has(token.contractAddress)) {
      // Detect if ERC721 or ERC1155
      const code = await provider.getCode(token.contractAddress);
      const nftContract = new ethers.Contract(
        token.contractAddress,
        [
          "function supportsInterface(bytes4) view returns (bool)",
        ],
        provider
      );

      try {
        // ERC1155 interface ID: 0xd9b67a26
        const isERC1155 = await nftContract.supportsInterface("0xd9b67a26");
        nftContractsMap.set(
          token.contractAddress,
          isERC1155 ? TokenSpec.ERC1155 : TokenSpec.ERC721
        );
      } catch {
        // Default to ERC721 if detection fails
        nftContractsMap.set(token.contractAddress, TokenSpec.ERC721);
      }
    }
  }

  const nftContracts = Array.from(nftContractsMap.keys());
  const tokenSpecs = Array.from(nftContractsMap.values());

  console.log("NFT contracts to approve:", nftContracts);
  console.log("Token specs:", tokenSpecs);

  // Step 2: Encode the multicall function with structs
  const multicallInterface = new ethers.Interface([
    "struct ApprovalParams { address[] nftContracts; uint8[] tokenSpecs; }",
    "struct BurnParams { address burnRedeemContract; address creatorContractAddress; uint256 instanceId; uint32 burnRedeemCount; tuple(uint48 groupIndex, uint48 itemIndex, address contractAddress, uint256 id, bytes32[] merkleProof)[] burnTokens; }",
    "function approveAndBurn(tuple(address[] nftContracts, uint8[] tokenSpecs) approvalParams, tuple(address burnRedeemContract, address creatorContractAddress, uint256 instanceId, uint32 burnRedeemCount, tuple(uint48 groupIndex, uint48 itemIndex, address contractAddress, uint256 id, bytes32[] merkleProof)[] burnTokens) burnParams) payable"
  ]);

  const callData = multicallInterface.encodeFunctionData("approveAndBurn", [
    {
      nftContracts: nftContracts,
      tokenSpecs: tokenSpecs
    },
    {
      burnRedeemContract: burnRedeemAddress,
      creatorContractAddress: params.creatorContractAddress,
      instanceId: params.instanceId,
      burnRedeemCount: params.burnRedeemCount,
      burnTokens: params.burnTokens
    }
  ]);

  // Step 3: Submit via Gelato relay (ONE signature!)
  const request: SponsoredCallRequest = {
    chainId: Number(chainId),
    target: multicallAddress,
    data: callData,
    user: userAddress,
  };

  console.log("🚀 Submitting single-transaction burn via Gelato...");
  console.log("  - Approving", nftContracts.length, "NFT contracts");
  console.log("  - Burning", params.burnTokens.length, "tokens");
  console.log("  - All in ONE user signature!");

  const response = await relay.callWithSyncFeeERC2771(
    request,
    signer,
    {
      gasLimit: 1000000n, // Higher limit for multiple approvals + burn
      isRelayContext: true,
    }
  );

  console.log("✅ Success! Task ID:", response.taskId);
  console.log("User only signed ONCE!");

  return response.taskId;
}

// ============================================================================
// BATCH MULTIPLE BURN REDEEMS (SINGLE SIGNATURE)
// ============================================================================

/**
 * Burn across multiple burn redeem instances with ONE signature
 *
 * Example: User wants to burn NFTs for 3 different campaigns at once
 *
 * @param provider - Ethers provider
 * @param multicallAddress - Multicall contract address
 * @param burnRedeemAddress - Burn redeem contract address
 * @param batchParams - Array of burn redeem parameters
 * @param totalEthPayment - Total ETH for all burns + gas
 */
async function batchBurnSingleSignature(
  provider: ethers.BrowserProvider,
  multicallAddress: string,
  burnRedeemAddress: string,
  batchParams: BurnRedeemParams[],
  totalEthPayment: bigint
): Promise<string> {
  const relay = new GelatoRelay();
  const signer = await provider.getSigner();
  const userAddress = await signer.getAddress();
  const chainId = (await provider.getNetwork()).chainId;

  // Collect all unique NFT contracts across ALL burns
  const nftContractsMap = new Map<string, TokenSpec>();

  for (const params of batchParams) {
    for (const token of params.burnTokens) {
      if (!nftContractsMap.has(token.contractAddress)) {
        const nftContract = new ethers.Contract(
          token.contractAddress,
          ["function supportsInterface(bytes4) view returns (bool)"],
          provider
        );

        try {
          const isERC1155 = await nftContract.supportsInterface("0xd9b67a26");
          nftContractsMap.set(
            token.contractAddress,
            isERC1155 ? TokenSpec.ERC1155 : TokenSpec.ERC721
          );
        } catch {
          nftContractsMap.set(token.contractAddress, TokenSpec.ERC721);
        }
      }
    }
  }

  const nftContracts = Array.from(nftContractsMap.keys());
  const tokenSpecs = Array.from(nftContractsMap.values());

  // Prepare batch parameters
  const creatorAddresses = batchParams.map(p => p.creatorContractAddress);
  const instanceIds = batchParams.map(p => p.instanceId);
  const counts = batchParams.map(p => p.burnRedeemCount);
  const allBurnTokens = batchParams.map(p => p.burnTokens);

  // Encode batch call with structs
  const multicallInterface = new ethers.Interface([
    "struct ApprovalParams { address[] nftContracts; uint8[] tokenSpecs; }",
    "function approveAndBurnBatch(tuple(address[] nftContracts, uint8[] tokenSpecs) approvalParams, address burnRedeemContract, address[] creatorContractAddresses, uint256[] instanceIds, uint32[] burnRedeemCounts, tuple(uint48 groupIndex, uint48 itemIndex, address contractAddress, uint256 id, bytes32[] merkleProof)[][] burnTokens) payable"
  ]);

  const callData = multicallInterface.encodeFunctionData("approveAndBurnBatch", [
    {
      nftContracts: nftContracts,
      tokenSpecs: tokenSpecs
    },
    burnRedeemAddress,
    creatorAddresses,
    instanceIds,
    counts,
    allBurnTokens
  ]);

  // Submit via Gelato
  const request: SponsoredCallRequest = {
    chainId: Number(chainId),
    target: multicallAddress,
    data: callData,
    user: userAddress,
  };

  console.log("🚀 Submitting batch burn via Gelato...");
  console.log("  - Approving", nftContracts.length, "NFT contracts");
  console.log("  - Executing", batchParams.length, "burn redeems");
  console.log("  - All in ONE user signature!");

  const response = await relay.callWithSyncFeeERC2771(
    request,
    signer,
    {
      gasLimit: 2000000n, // Even higher for batch
      isRelayContext: true,
    }
  );

  console.log("✅ Batch burn submitted! Task ID:", response.taskId);

  return response.taskId;
}

// ============================================================================
// REACT HOOK FOR SINGLE-TRANSACTION BURNS
// ============================================================================

import { useState, useCallback } from "react";

interface UseSingleTransactionBurnReturn {
  burn: (params: BurnRedeemParams) => Promise<string>;
  batchBurn: (params: BurnRedeemParams[]) => Promise<string>;
  isLoading: boolean;
  error: Error | null;
  taskId: string | null;
}

/**
 * React hook for true single-transaction burns
 *
 * Usage:
 * ```typescript
 * const { burn, isLoading } = useSingleTransactionBurn(
 *   provider,
 *   multicallAddress,
 *   burnRedeemAddress,
 *   burnCostWei
 * );
 *
 * await burn({ creatorContractAddress, instanceId, ... });
 * // User only signs ONCE!
 * ```
 */
function useSingleTransactionBurn(
  provider: ethers.BrowserProvider | null,
  multicallAddress: string,
  burnRedeemAddress: string,
  burnCostWei: bigint
): UseSingleTransactionBurnReturn {
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<Error | null>(null);
  const [taskId, setTaskId] = useState<string | null>(null);

  const burn = useCallback(async (params: BurnRedeemParams) => {
    if (!provider) throw new Error("No provider");

    setIsLoading(true);
    setError(null);

    try {
      // Estimate total payment
      const gasEstimate = 300000n; // Approximate for approvals + burn
      const feeData = await provider.getFeeData();
      const gasPrice = feeData.gasPrice || 0n;
      const gasCost = gasEstimate * gasPrice;
      const gelatoFee = gasCost / 5n; // 20%

      const totalPayment = burnCostWei + gasCost + gelatoFee;

      // Execute single-transaction burn
      const tid = await trueSingleTransactionBurn(
        provider,
        multicallAddress,
        burnRedeemAddress,
        params,
        totalPayment
      );

      setTaskId(tid);
      return tid;

    } catch (err) {
      const error = err as Error;
      setError(error);
      throw error;
    } finally {
      setIsLoading(false);
    }
  }, [provider, multicallAddress, burnRedeemAddress, burnCostWei]);

  const batchBurn = useCallback(async (params: BurnRedeemParams[]) => {
    if (!provider) throw new Error("No provider");

    setIsLoading(true);
    setError(null);

    try {
      // Estimate for batch
      const gasEstimate = 500000n * BigInt(params.length);
      const feeData = await provider.getFeeData();
      const gasPrice = feeData.gasPrice || 0n;
      const gasCost = gasEstimate * gasPrice;
      const gelatoFee = gasCost / 5n;

      const totalBurnCost = burnCostWei * BigInt(params.length);
      const totalPayment = totalBurnCost + gasCost + gelatoFee;

      const tid = await batchBurnSingleSignature(
        provider,
        multicallAddress,
        burnRedeemAddress,
        params,
        totalPayment
      );

      setTaskId(tid);
      return tid;

    } catch (err) {
      const error = err as Error;
      setError(error);
      throw error;
    } finally {
      setIsLoading(false);
    }
  }, [provider, multicallAddress, burnRedeemAddress, burnCostWei]);

  return { burn, batchBurn, isLoading, error, taskId };
}

// ============================================================================
// COMPARISON: OLD VS NEW APPROACH
// ============================================================================

/**
 * Visual comparison of transaction flows
 */

// ❌ OLD APPROACH (Multiple transactions)
async function oldApproach_MultipleTransactions(
  provider: ethers.BrowserProvider,
  nftContracts: string[],
  burnRedeemAddress: string,
  burnParams: BurnRedeemParams
) {
  const signer = await provider.getSigner();

  // Transaction 1: Approve NFT A
  const nft1 = new ethers.Contract(nftContracts[0], [...], signer);
  await (await nft1.setApprovalForAll(burnRedeemAddress, true)).wait();

  // Transaction 2: Approve NFT B
  const nft2 = new ethers.Contract(nftContracts[1], [...], signer);
  await (await nft2.setApprovalForAll(burnRedeemAddress, true)).wait();

  // Transaction 3: Approve NFT C
  const nft3 = new ethers.Contract(nftContracts[2], [...], signer);
  await (await nft3.setApprovalForAll(burnRedeemAddress, true)).wait();

  // Transaction 4: Burn (via Gelato)
  // ... sign burn message

  // Total: 4 user interactions, ~60 seconds
}

// ✅ NEW APPROACH (Single signature)
async function newApproach_SingleSignature(
  provider: ethers.BrowserProvider,
  multicallAddress: string,
  burnRedeemAddress: string,
  burnParams: BurnRedeemParams
) {
  // User signs ONCE
  await trueSingleTransactionBurn(
    provider,
    multicallAddress,
    burnRedeemAddress,
    burnParams,
    totalPayment
  );

  // Gelato executes:
  // - Approve NFT A ✓
  // - Approve NFT B ✓
  // - Approve NFT C ✓
  // - Execute burn ✓

  // Total: 1 user signature, ~5-10 seconds
}

// ============================================================================
// EXPORTS
// ============================================================================

export {
  trueSingleTransactionBurn,
  batchBurnSingleSignature,
  useSingleTransactionBurn,
  TokenSpec,
};

export type {
  BurnToken,
  BurnRedeemParams,
  UseSingleTransactionBurnReturn,
};
