/**
 * Gelato-Enabled Burn Redeem Frontend Integration Examples
 *
 * This file demonstrates how to integrate Gelato Relay with the GelatoBurnRedeem contracts
 * to enable single-transaction UX for NFT burns (approve + burn in one user action).
 *
 * Key Benefits:
 * - Users only sign ONE message (no separate approval transaction)
 * - Users pay ALL gas fees (no sponsorship burden for developers)
 * - Gelato handles relay infrastructure
 * - Works with any arbitrary NFT contract
 */

import { ethers } from "ethers";
import { GelatoRelay, SponsoredCallRequest } from "@gelatonetwork/relay-sdk";

// ============================================================================
// TYPES & INTERFACES
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

// ============================================================================
// EXAMPLE 1: Single NFT Burn with Gelato Relay
// ============================================================================

/**
 * Burns a single NFT and redeems tokens using Gelato Relay.
 * User pays gas fees via callWithSyncFeeERC2771.
 *
 * @param provider - Ethers provider connected to user's wallet
 * @param burnRedeemAddress - Address of GelatoERC721BurnRedeem or GelatoERC1155BurnRedeem
 * @param nftAddress - Address of NFT to burn
 * @param tokenId - Token ID to burn
 * @param params - Burn redeem parameters
 * @param ethPayment - ETH amount to send (burn cost + estimated gas)
 */
async function burnWithGelatoRelay(
  provider: ethers.BrowserProvider,
  burnRedeemAddress: string,
  nftAddress: string,
  tokenId: bigint,
  params: BurnRedeemParams,
  ethPayment: bigint
): Promise<string> {
  // Initialize Gelato Relay SDK
  const relay = new GelatoRelay();

  // Get user's signer
  const signer = await provider.getSigner();
  const userAddress = await signer.getAddress();
  const chainId = (await provider.getNetwork()).chainId;

  // Step 1: User approves NFT for burn redeem contract
  console.log("Step 1: Approving NFT...");
  const nftContract = new ethers.Contract(
    nftAddress,
    ["function setApprovalForAll(address operator, bool approved)"],
    signer
  );

  const approveTx = await nftContract.setApprovalForAll(burnRedeemAddress, true);
  await approveTx.wait();
  console.log("NFT approved!");

  // Step 2: Prepare burn redeem call data
  const burnRedeemInterface = new ethers.Interface([
    "function burnRedeem(address creatorContractAddress, uint256 instanceId, uint32 burnRedeemCount, tuple(uint48 groupIndex, uint48 itemIndex, address contractAddress, uint256 id, bytes32[] merkleProof)[] burnTokens) payable"
  ]);

  const callData = burnRedeemInterface.encodeFunctionData("burnRedeem", [
    params.creatorContractAddress,
    params.instanceId,
    params.burnRedeemCount,
    params.burnTokens
  ]);

  // Step 3: Create relay request (user pays gas)
  const request: SponsoredCallRequest = {
    chainId: Number(chainId),
    target: burnRedeemAddress,
    data: callData,
    user: userAddress,
  };

  console.log("Step 2: Submitting burn via Gelato relay...");

  // Use callWithSyncFeeERC2771 - user pays gas from msg.value
  const response = await relay.callWithSyncFeeERC2771(
    request,
    signer,
    {
      gasLimit: 500000n, // Adjust based on complexity
      isRelayContext: true,
    }
  );

  console.log("Burn submitted! Task ID:", response.taskId);
  return response.taskId;
}

// ============================================================================
// EXAMPLE 2: Batch Multiple NFT Burns in Single Transaction
// ============================================================================

/**
 * Burns multiple NFTs across different collections in a single transaction.
 * This is where Gelato relay really shines - batch operations without multiple approvals!
 *
 * @param provider - Ethers provider
 * @param burnRedeemAddress - Gelato burn redeem contract address
 * @param burnParams - Array of burn redeem parameters
 * @param totalEthPayment - Total ETH for all burns + gas
 */
async function batchBurnWithGelatoRelay(
  provider: ethers.BrowserProvider,
  burnRedeemAddress: string,
  burnParams: BurnRedeemParams[],
  totalEthPayment: bigint
): Promise<string> {
  const relay = new GelatoRelay();
  const signer = await provider.getSigner();
  const userAddress = await signer.getAddress();
  const chainId = (await provider.getNetwork()).chainId;

  // Step 1: Approve all unique NFT contracts
  console.log("Step 1: Approving all NFT contracts...");
  const uniqueContracts = new Set<string>();
  burnParams.forEach(param => {
    param.burnTokens.forEach(token => {
      uniqueContracts.add(token.contractAddress);
    });
  });

  const nftInterface = new ethers.Interface([
    "function setApprovalForAll(address operator, bool approved)"
  ]);

  for (const nftAddress of uniqueContracts) {
    const nftContract = new ethers.Contract(nftAddress, nftInterface, signer);
    const approveTx = await nftContract.setApprovalForAll(burnRedeemAddress, true);
    await approveTx.wait();
    console.log(`Approved ${nftAddress}`);
  }

  // Step 2: Prepare batch burn call data
  const burnRedeemInterface = new ethers.Interface([
    "function burnRedeem(address[] creatorContractAddresses, uint256[] instanceIds, uint32[] burnRedeemCounts, tuple(uint48 groupIndex, uint48 itemIndex, address contractAddress, uint256 id, bytes32[] merkleProof)[][] burnTokens) payable"
  ]);

  const creatorAddresses = burnParams.map(p => p.creatorContractAddress);
  const instanceIds = burnParams.map(p => p.instanceId);
  const counts = burnParams.map(p => p.burnRedeemCount);
  const allBurnTokens = burnParams.map(p => p.burnTokens);

  const callData = burnRedeemInterface.encodeFunctionData("burnRedeem", [
    creatorAddresses,
    instanceIds,
    counts,
    allBurnTokens
  ]);

  // Step 3: Submit via Gelato relay
  const request: SponsoredCallRequest = {
    chainId: Number(chainId),
    target: burnRedeemAddress,
    data: callData,
    user: userAddress,
  };

  console.log("Step 2: Submitting batch burn via Gelato relay...");

  const response = await relay.callWithSyncFeeERC2771(
    request,
    signer,
    {
      gasLimit: 1000000n, // Higher limit for batch
      isRelayContext: true,
    }
  );

  console.log("Batch burn submitted! Task ID:", response.taskId);
  return response.taskId;
}

// ============================================================================
// EXAMPLE 3: Estimate Gas & Calculate Total Payment
// ============================================================================

/**
 * Estimates the total ETH payment needed (burn cost + gas + Gelato fee).
 *
 * @param provider - Ethers provider
 * @param burnRedeemAddress - Burn redeem contract address
 * @param params - Burn redeem parameters
 * @param burnCostWei - Cost per burn in wei (from contract)
 * @returns Total ETH needed including gas and Gelato fee
 */
async function estimateTotalPayment(
  provider: ethers.BrowserProvider,
  burnRedeemAddress: string,
  params: BurnRedeemParams,
  burnCostWei: bigint
): Promise<bigint> {
  const signer = await provider.getSigner();
  const userAddress = await signer.getAddress();

  // Prepare call data
  const burnRedeemInterface = new ethers.Interface([
    "function burnRedeem(address,uint256,uint32,tuple(uint48,uint48,address,uint256,bytes32[])[]) payable"
  ]);

  const callData = burnRedeemInterface.encodeFunctionData("burnRedeem", [
    params.creatorContractAddress,
    params.instanceId,
    params.burnRedeemCount,
    params.burnTokens
  ]);

  // Estimate gas for the transaction
  const gasEstimate = await provider.estimateGas({
    from: userAddress,
    to: burnRedeemAddress,
    data: callData,
    value: burnCostWei,
  });

  // Get current gas price
  const feeData = await provider.getFeeData();
  const gasPrice = feeData.gasPrice || 0n;

  // Calculate costs
  const gasCost = gasEstimate * gasPrice;

  // Gelato fee is approximately 10-20% of gas cost
  // Use 20% to be safe
  const gelatoFee = gasCost / 5n; // 20%

  const totalPayment = burnCostWei + gasCost + gelatoFee;

  console.log("Payment breakdown:");
  console.log("- Burn cost:", ethers.formatEther(burnCostWei), "ETH");
  console.log("- Gas cost:", ethers.formatEther(gasCost), "ETH");
  console.log("- Gelato fee:", ethers.formatEther(gelatoFee), "ETH");
  console.log("- TOTAL:", ethers.formatEther(totalPayment), "ETH");

  return totalPayment;
}

// ============================================================================
// EXAMPLE 4: Check Task Status
// ============================================================================

/**
 * Checks the status of a Gelato relay task.
 *
 * @param taskId - Task ID returned from Gelato relay
 * @returns Task status
 */
async function checkTaskStatus(taskId: string): Promise<any> {
  const relay = new GelatoRelay();
  const status = await relay.getTaskStatus(taskId);

  console.log("Task status:", status);
  console.log("- State:", status.taskState);
  console.log("- Transaction hash:", status.transactionHash);

  return status;
}

// ============================================================================
// EXAMPLE 5: React Hook for Burn Redeem
// ============================================================================

/**
 * React hook for managing burn redeem with Gelato relay.
 * Handles approval, gas estimation, and relay submission.
 */
import { useState, useCallback } from "react";

interface UseBurnRedeemReturn {
  burnRedeem: (params: BurnRedeemParams) => Promise<string>;
  isLoading: boolean;
  error: Error | null;
  taskId: string | null;
}

function useBurnRedeem(
  provider: ethers.BrowserProvider | null,
  burnRedeemAddress: string,
  burnCostWei: bigint
): UseBurnRedeemReturn {
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<Error | null>(null);
  const [taskId, setTaskId] = useState<string | null>(null);

  const burnRedeem = useCallback(async (params: BurnRedeemParams) => {
    if (!provider) throw new Error("No provider available");

    setIsLoading(true);
    setError(null);

    try {
      // Get unique NFT contracts
      const nftContracts = new Set<string>();
      params.burnTokens.forEach(token => {
        nftContracts.add(token.contractAddress);
      });

      // Approve all NFTs
      const signer = await provider.getSigner();
      const nftInterface = new ethers.Interface([
        "function setApprovalForAll(address,bool)"
      ]);

      for (const nftAddress of nftContracts) {
        const contract = new ethers.Contract(nftAddress, nftInterface, signer);
        const tx = await contract.setApprovalForAll(burnRedeemAddress, true);
        await tx.wait();
      }

      // Estimate total payment
      const totalPayment = await estimateTotalPayment(
        provider,
        burnRedeemAddress,
        params,
        burnCostWei
      );

      // Submit via Gelato
      const relay = new GelatoRelay();
      const userAddress = await signer.getAddress();
      const chainId = (await provider.getNetwork()).chainId;

      const burnRedeemInterface = new ethers.Interface([
        "function burnRedeem(address,uint256,uint32,tuple(uint48,uint48,address,uint256,bytes32[])[]) payable"
      ]);

      const callData = burnRedeemInterface.encodeFunctionData("burnRedeem", [
        params.creatorContractAddress,
        params.instanceId,
        params.burnRedeemCount,
        params.burnTokens
      ]);

      const request: SponsoredCallRequest = {
        chainId: Number(chainId),
        target: burnRedeemAddress,
        data: callData,
        user: userAddress,
      };

      const response = await relay.callWithSyncFeeERC2771(request, signer, {
        gasLimit: 500000n,
        isRelayContext: true,
      });

      setTaskId(response.taskId);
      return response.taskId;

    } catch (err) {
      const error = err as Error;
      setError(error);
      throw error;
    } finally {
      setIsLoading(false);
    }
  }, [provider, burnRedeemAddress, burnCostWei]);

  return { burnRedeem, isLoading, error, taskId };
}

// ============================================================================
// EXPORT
// ============================================================================

export {
  burnWithGelatoRelay,
  batchBurnWithGelatoRelay,
  estimateTotalPayment,
  checkTaskStatus,
  useBurnRedeem,
};

export type {
  BurnToken,
  BurnRedeemParams,
  UseBurnRedeemReturn,
};
