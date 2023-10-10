// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "./IPhysicalClaimCore.sol";

interface IPhysicalClaim is IPhysicalClaimCore {
    /**
     * @notice initialize a new physical claim, emit initialize event
     * @param instanceId                the instanceId of the physicalClaim for the physical claim
     * @param physicalClaimParameters      the parameters which will affect the redemption behavior of the physical claim
     */
    function initializePhysicalClaim(uint256 instanceId, PhysicalClaimParameters calldata physicalClaimParameters) external;

    /**
     * @notice update an existing physical claim
     * @param instanceId                the instanceId of the physicalClaim for the physical claim
     * @param physicalClaimParameters      the parameters which will affect the redemption behavior of the physical claim
     */
    function updatePhysicalClaim(uint256 instanceId, PhysicalClaimParameters calldata physicalClaimParameters) external;
}
