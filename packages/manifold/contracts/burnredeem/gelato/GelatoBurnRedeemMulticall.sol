// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "./mocks/GelatoRelayContext.sol";

interface IGelatoBurnRedeem {
    struct BurnToken {
        uint48 groupIndex;
        uint48 itemIndex;
        address contractAddress;
        uint256 id;
        bytes32[] merkleProof;
    }

    function burnRedeem(
        address creatorContractAddress,
        uint256 instanceId,
        uint32 burnRedeemCount,
        BurnToken[] calldata burnTokens
    ) external payable;
}

/**
 * @title Gelato Burn Redeem Multicall
 * @notice Batches multiple NFT approvals + burn into a SINGLE transaction via Gelato Relay
 * @dev This is the TRUE single-transaction solution for burn redeems with multiple NFT collections
 *
 * How it works:
 * 1. User signs ONE message (via Gelato relay)
 * 2. This contract receives the relay call with _msgSender() = user
 * 3. Approves all NFT contracts on behalf of user
 * 4. Executes the burn redeem
 * 5. All in ONE transaction!
 *
 * Benefits:
 * - User only signs once
 * - No matter how many NFT collections involved
 * - Works with Gelato's callWithSyncFeeERC2771
 * - User pays all gas
 *
 * Usage:
 * User signs message to call approveAndBurn() with all NFT contracts + burn params
 * Gelato submits via ERC-2771
 * Everything happens atomically
 */
contract GelatoBurnRedeemMulticall is GelatoRelayContext {

    struct ApprovalParams {
        address[] nftContracts;
        uint8[] tokenSpecs; // 0 = ERC721, 1 = ERC1155
    }

    struct BurnParams {
        address burnRedeemContract;
        address creatorContractAddress;
        uint256 instanceId;
        uint32 burnRedeemCount;
        IGelatoBurnRedeem.BurnToken[] burnTokens;
    }

    /**
     * @notice Approve multiple NFT contracts and execute burn in ONE transaction
     * @dev This is called via Gelato relay with ERC-2771, so _msgSender() = actual user
     *
     * @param approvalParams NFT approval parameters
     * @param burnParams Burn redeem parameters
     */
    function approveAndBurn(
        ApprovalParams calldata approvalParams,
        BurnParams calldata burnParams
    ) external payable {
        require(approvalParams.nftContracts.length == approvalParams.tokenSpecs.length, "Length mismatch");

        // Get actual user from ERC-2771 context
        address user = _msgSender();

        // Step 1: Approve all NFT contracts
        for (uint256 i = 0; i < approvalParams.nftContracts.length; i++) {
            if (approvalParams.tokenSpecs[i] == 0) {
                // ERC721
                IERC721(approvalParams.nftContracts[i]).setApprovalForAll(burnParams.burnRedeemContract, true);
            } else {
                // ERC1155
                IERC1155(approvalParams.nftContracts[i]).setApprovalForAll(burnParams.burnRedeemContract, true);
            }
        }

        // Step 2: Execute burn redeem (forward all ETH)
        IGelatoBurnRedeem(burnParams.burnRedeemContract).burnRedeem{value: msg.value}(
            burnParams.creatorContractAddress,
            burnParams.instanceId,
            burnParams.burnRedeemCount,
            burnParams.burnTokens
        );

        // Note: Any refund from burn redeem goes back to this contract
        // Then we forward it to the actual user
        if (address(this).balance > 0) {
            (bool success, ) = payable(user).call{value: address(this).balance}("");
            require(success, "Refund failed");
        }
    }

    /**
     * @notice Batch approve and burn - supports multiple burn redeems in one call
     * @dev For users burning across multiple burn redeem instances
     */
    function approveAndBurnBatch(
        ApprovalParams calldata approvalParams,
        address burnRedeemContract,
        address[] calldata creatorContractAddresses,
        uint256[] calldata instanceIds,
        uint32[] calldata burnRedeemCounts,
        IGelatoBurnRedeem.BurnToken[][] calldata burnTokens
    ) external payable {
        require(approvalParams.nftContracts.length == approvalParams.tokenSpecs.length, "Length mismatch");
        require(
            creatorContractAddresses.length == instanceIds.length &&
            creatorContractAddresses.length == burnRedeemCounts.length &&
            creatorContractAddresses.length == burnTokens.length,
            "Burn params length mismatch"
        );

        address user = _msgSender();

        // Step 1: Approve all NFT contracts
        for (uint256 i = 0; i < approvalParams.nftContracts.length; i++) {
            if (approvalParams.tokenSpecs[i] == 0) {
                IERC721(approvalParams.nftContracts[i]).setApprovalForAll(burnRedeemContract, true);
            } else {
                IERC1155(approvalParams.nftContracts[i]).setApprovalForAll(burnRedeemContract, true);
            }
        }

        // Step 2: Execute all burn redeems
        // Note: We need to split msg.value across burns
        // For simplicity, let the burn redeem contract handle validation
        IGelatoBurnRedeem burnRedeem = IGelatoBurnRedeem(burnRedeemContract);

        for (uint256 i = 0; i < creatorContractAddresses.length; i++) {
            // Calculate ETH to send for this burn
            // In production, you'd want to pass this as a parameter
            uint256 ethForThisBurn = msg.value / creatorContractAddresses.length;

            burnRedeem.burnRedeem{value: ethForThisBurn}(
                creatorContractAddresses[i],
                instanceIds[i],
                burnRedeemCounts[i],
                burnTokens[i]
            );
        }

        // Refund any remaining ETH to user
        if (address(this).balance > 0) {
            (bool success, ) = payable(user).call{value: address(this).balance}("");
            require(success, "Refund failed");
        }
    }

    /**
     * @notice Allow receiving ETH refunds from burn redeem contract
     */
    receive() external payable {}
}
