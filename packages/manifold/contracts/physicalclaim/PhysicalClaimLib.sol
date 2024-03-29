// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "./IPhysicalClaimCore.sol";

/**
 * @title Physical Claim Lib
 * @author manifold.xyz
 * @notice Library for Physical Claim shared extensions.
 */
library PhysicalClaimLib {

    event PhysicalClaimInitialized(uint256 indexed instanceId, address initializer);
    event PhysicalClaimUpdated(uint256 indexed instanceId);
    event PhysicalClaimRedemption(uint256 indexed instanceId, uint8 indexed variation, uint32 count, bytes data);
    event PhysicalClaimTokenConsumed(uint256 indexed instanceId, uint256 tokenId, address contractAddress);

    error PhysicalClaimAlreadyInitialized();
    error InvalidBurnItem();
    error InvalidBurnToken();
    error InvalidMerkleProof();
    error InvalidStorageProtocol();
    error InvalidPaymentReceiver();
    error InvalidDates();
    error InvalidInput();

    /**
     * Initialiazes a burn redeem with base parameters
     */
    function initialize(
        uint256 instanceId,
        IPhysicalClaimCore.PhysicalClaim storage physicalClaimInstance,
        IPhysicalClaimCore.PhysicalClaimParameters calldata physicalClaimParameters
    ) public {
        _validateParameters(physicalClaimParameters);

        // Create the physical claim
        _setParameters(physicalClaimInstance, physicalClaimParameters);
        _setBurnGroups(physicalClaimInstance, physicalClaimParameters.burnSet);

        emit PhysicalClaimInitialized(instanceId, msg.sender);
    }

    /**
     * Updates a physical claim with base parameters
     */
    function update(
        uint256 instanceId,
        IPhysicalClaimCore.PhysicalClaim storage physicalClaimInstance,
        IPhysicalClaimCore.PhysicalClaimParameters calldata physicalClaimParameters
    ) public {
        _validateParameters(physicalClaimParameters);

        // Overwrite the existing burnRedeem
        _setParameters(physicalClaimInstance, physicalClaimParameters);
        _setBurnGroups(physicalClaimInstance, physicalClaimParameters.burnSet);
        syncTotalSupply(physicalClaimInstance);
        emit PhysicalClaimUpdated(instanceId);
    }

    /**
     * Helper to update total supply if redeemedCount exceeds totalSupply after airdrop or instance update.
     */
    function syncTotalSupply(IPhysicalClaimCore.PhysicalClaim storage physicalClaimInstance) public {
        if (
            physicalClaimInstance.totalSupply != 0 &&
            physicalClaimInstance.redeemedCount > physicalClaimInstance.totalSupply
        ) {
            physicalClaimInstance.totalSupply = physicalClaimInstance.redeemedCount;
        }
    }

    /*
     * Helper to validate burn item
     */
    function validateBurnItem(IPhysicalClaimCore.BurnItem memory burnItem, address contractAddress, uint256 tokenId, bytes32[] memory merkleProof) public pure {
        if (burnItem.validationType == IPhysicalClaimCore.ValidationType.ANY) {
            return;
        }
        if (contractAddress != burnItem.contractAddress) {
            revert InvalidBurnToken();
        }
        if (burnItem.validationType == IPhysicalClaimCore.ValidationType.CONTRACT) {
            return;
        } else if (burnItem.validationType == IPhysicalClaimCore.ValidationType.RANGE) {
            if (tokenId < burnItem.minTokenId || tokenId > burnItem.maxTokenId) {
                revert IPhysicalClaimCore.InvalidToken(tokenId);
            }
            return;
        } else if (burnItem.validationType == IPhysicalClaimCore.ValidationType.MERKLE_TREE) {
            bytes32 leaf = keccak256(abi.encodePacked(tokenId));
            if (!MerkleProof.verify(merkleProof, burnItem.merkleRoot, leaf)) {
                revert InvalidMerkleProof();
            }
            return;
        }
        revert InvalidBurnItem();
    }

    /**
     * Helper to validate the parameters for a physical claim
     */
    function _validateParameters(IPhysicalClaimCore.PhysicalClaimParameters calldata physicalClaimParameters) internal pure {
        if (physicalClaimParameters.paymentReceiver == address(0)) {
            revert InvalidPaymentReceiver();
        }
        if (physicalClaimParameters.endDate != 0 && physicalClaimParameters.startDate >= physicalClaimParameters.endDate) {
            revert InvalidDates();
        }
        if (physicalClaimParameters.variationLimits.length == 0) {
            revert InvalidInput();
        }
    }

    /**
     * Helper to set top level properties for a physical claim
     */
    function _setParameters(IPhysicalClaimCore.PhysicalClaim storage physicalClaimInstance, IPhysicalClaimCore.PhysicalClaimParameters calldata physicalClaimParameters) private {
        physicalClaimInstance.startDate = physicalClaimParameters.startDate;
        physicalClaimInstance.endDate = physicalClaimParameters.endDate;
        physicalClaimInstance.totalSupply = physicalClaimParameters.totalSupply;
        physicalClaimInstance.paymentReceiver = physicalClaimParameters.paymentReceiver;
        physicalClaimInstance.signer = physicalClaimParameters.signer;

        uint8[] memory currentVariationIds = physicalClaimInstance.variationIds;
        for (uint256 i; i < currentVariationIds.length;) {
            physicalClaimInstance.variations[currentVariationIds[i]].active = false;
            unchecked { ++i; }
        }
        physicalClaimInstance.variationIds = new uint8[](physicalClaimParameters.variationLimits.length);
        for (uint256 i; i < physicalClaimParameters.variationLimits.length;) {
            IPhysicalClaimCore.VariationLimit memory variationLimit = physicalClaimParameters.variationLimits[i];
            IPhysicalClaimCore.VariationState storage variationState = physicalClaimInstance.variations[variationLimit.id];
            variationState.active = true;
            physicalClaimInstance.variationIds[i] = variationLimit.id;
            // Set the totalSupply. If params specify 0, we use 0, otherwise it's the max of the current redeemCount and the param's totalSupply
            variationState.totalSupply = variationLimit.totalSupply == 0 ? 0 : (variationState.redeemedCount > variationLimit.totalSupply ? variationState.redeemedCount : variationLimit.totalSupply);
            unchecked { ++i; }
        }
    }

    /**
     * Helper to set the burn groups for a physical claim
     */
    function _setBurnGroups(IPhysicalClaimCore.PhysicalClaim storage physicalClaimInstance, IPhysicalClaimCore.BurnGroup[] calldata burnGroups) private {
        delete physicalClaimInstance.burnSet;
        for (uint256 i; i < burnGroups.length;) {
            physicalClaimInstance.burnSet.push();
            IPhysicalClaimCore.BurnGroup storage burnGroup = physicalClaimInstance.burnSet[i];
            if (burnGroups[i].requiredCount == 0 || burnGroups[i].requiredCount > burnGroups[i].items.length) {
                revert InvalidInput();
            }
            burnGroup.requiredCount = burnGroups[i].requiredCount;
            for (uint256 j; j < burnGroups[i].items.length;) {
                // IPhysicalClaimCore.BurnItem memory burnItem = burnGroups[i].items[j];
                // uint256 amount = burnItem.amount;
                burnGroup.items.push(burnGroups[i].items[j]);
                unchecked { ++j; }
            }
            unchecked { ++i; }
        }
    }

}