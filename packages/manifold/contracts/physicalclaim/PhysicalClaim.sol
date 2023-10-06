// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC721CreatorCore.sol";

import "./PhysicalClaimCore.sol";
import "./PhysicalClaimLib.sol";
import "./IPhysicalClaim.sol";
import "../libraries/IERC721CreatorCoreVersion.sol";

contract PhysicalClaim is PhysicalClaimCore, IPhysicalClaim {
    using Strings for uint256;

    constructor(address initialOwner) PhysicalClaimCore(initialOwner) {}

    function supportsInterface(bytes4 interfaceId) public view virtual override(PhysicalClaimCore, IERC165) returns (bool) {
        return interfaceId == type(IPhysicalClaim).interfaceId || super.supportsInterface(interfaceId);
    }
    
    /**
     * @dev See {IPhysicalClaim-initializePhysicalClaim}.
     */
    function initializePhysicalClaim(
        uint256 instanceId,
        PhysicalClaimParameters calldata physicalClaimParameters
    ) external  {
        // Max uint56 for instanceId
        if (instanceId == 0 || instanceId > MAX_UINT_56) {
            revert InvalidInput();
        }

        _initialize(instanceId, physicalClaimParameters);
    }

    /**
     * @dev See {IPhysicalClaim-updatePhysicalClaim}.
     */
    function updatePhysicalClaim(
        uint256 instanceId,
        PhysicalClaimParameters calldata physicalClaimParameters
    ) external {
        _update(instanceId, physicalClaimParameters);
    }

    /** 
     * Helper to mint multiple redeem tokens
     */
    function _redeem(uint256 instanceId, PhysicalClaim storage physicalClaimInstance, address to, uint32 count, bytes memory data) internal override {
        if (physicalClaimInstance.redeemAmount == 1 && count == 1) {
            ++physicalClaimInstance.redeemedCount;

            // TODO logic to redeem and make sure not over-redeemed

            emit PhysicalClaimLib.PhysicalClaimMint(instanceId, 1, data);
        } else {
            uint256 totalCount = physicalClaimInstance.redeemAmount * count;
            if (totalCount > MAX_UINT_16) {
                revert InvalidInput();
            }
            uint256 startingCount = physicalClaimInstance.redeemedCount + 1;
            physicalClaimInstance.redeemedCount += uint32(totalCount);
            for (uint256 i; i < totalCount;) {
                
                // TODO logic to redeem and make sure not over-redeemed

                unchecked { i++; }
            }
            
        }
    }
}
