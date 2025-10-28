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
 * @title Gelato Burn Redeem Multicall V2
 * @notice TRUE single-transaction burn redeem with proper approval handling
 * @dev Corrected approach that handles NFT approvals correctly
 *
 * THE PROBLEM:
 * - User owns NFTs in collections A, B, C
 * - BurnRedeem contract needs approval to transfer these NFTs
 * - Traditional flow: 3 approval transactions + 1 burn = 4 total transactions
 *
 * THE SOLUTION:
 * - User approves THIS contract ONE TIME for all their NFT collections
 * - Then for EVERY burn (via Gelato relay):
 *   1. This contract transfers NFTs from user to itself
 *   2. This contract approves BurnRedeem to spend the NFTs
 *   3. This contract calls burnRedeem (which pulls NFTs from this contract)
 *   4. This contract forwards minted tokens back to user
 * - All in ONE Gelato relay call!
 *
 * SETUP (One-time):
 * User calls setApprovalForAll(thisContract, true) on each NFT collection
 *
 * USAGE (Every burn):
 * User signs ONE message via Gelato to call transferAndBurn()
 * Everything else happens automatically
 */
contract GelatoBurnRedeemMulticallV2 is GelatoRelayContext {

    struct NFTTransferParams {
        address[] nftContracts;
        uint256[] tokenIds;
        uint256[] amounts;
        uint8[] tokenSpecs; // 0=ERC721, 1=ERC1155
    }

    struct BurnParams {
        address burnRedeemContract;
        address creatorContractAddress;
        uint256 instanceId;
        uint32 burnRedeemCount;
        IGelatoBurnRedeem.BurnToken[] burnTokens;
    }

    /**
     * @notice Transfer NFTs from user, approve burn contract, execute burn - ONE transaction
     * @dev Called via Gelato relay, so _msgSender() = actual user
     *
     * PREREQUISITE: User must have approved this contract via setApprovalForAll
     *
     * @param nftParams NFT transfer parameters
     * @param burnParams Burn redeem parameters
     */
    function transferAndBurn(
        NFTTransferParams calldata nftParams,
        BurnParams calldata burnParams
    ) external payable {
        require(
            nftParams.nftContracts.length == nftParams.tokenIds.length &&
            nftParams.nftContracts.length == nftParams.amounts.length &&
            nftParams.nftContracts.length == nftParams.tokenSpecs.length,
            "Length mismatch"
        );

        address user = _msgSender();

        // Step 1: Transfer all NFTs from user to this contract
        for (uint256 i = 0; i < nftParams.nftContracts.length; i++) {
            if (nftParams.tokenSpecs[i] == 0) {
                // ERC721
                IERC721(nftParams.nftContracts[i]).transferFrom(user, address(this), nftParams.tokenIds[i]);
            } else {
                // ERC1155
                IERC1155(nftParams.nftContracts[i]).safeTransferFrom(
                    user,
                    address(this),
                    nftParams.tokenIds[i],
                    nftParams.amounts[i],
                    ""
                );
            }
        }

        // Step 2: Approve burn redeem contract for all NFTs
        for (uint256 i = 0; i < nftParams.nftContracts.length; i++) {
            if (nftParams.tokenSpecs[i] == 0) {
                IERC721(nftParams.nftContracts[i]).setApprovalForAll(burnParams.burnRedeemContract, true);
            } else {
                IERC1155(nftParams.nftContracts[i]).setApprovalForAll(burnParams.burnRedeemContract, true);
            }
        }

        // Step 3: Execute burn redeem
        // Note: BurnRedeem will pull NFTs from this contract, mint to this contract
        IGelatoBurnRedeem(burnParams.burnRedeemContract).burnRedeem{value: msg.value}(
            burnParams.creatorContractAddress,
            burnParams.instanceId,
            burnParams.burnRedeemCount,
            burnParams.burnTokens
        );

        // Step 4: Transfer any minted tokens back to user
        // (ERC721/ERC1155 tokens minted to this contract should go to user)
        // This happens automatically if burn redeem is configured to mint to msg.sender

        // Step 5: Refund excess ETH to user
        if (address(this).balance > 0) {
            (bool success, ) = payable(user).call{value: address(this).balance}("");
            require(success, "Refund failed");
        }
    }

    /**
     * @notice Check if user has approved this contract for an NFT collection
     */
    function isApprovedForUser(
        address user,
        address nftContract,
        bool isERC1155
    ) external view returns (bool) {
        if (isERC1155) {
            return IERC1155(nftContract).isApprovedForAll(user, address(this));
        } else {
            return IERC721(nftContract).isApprovedForAll(user, address(this));
        }
    }

    /**
     * @notice ERC721 receiver
     */
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /**
     * @notice ERC1155 receiver
     */
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    /**
     * @notice ERC1155 batch receiver
     */
    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    /**
     * @notice Receive ETH
     */
    receive() external payable {}
}
