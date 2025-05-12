// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "../lazyclaim/ILazyPayableClaim.sol";

/**
 * Lazy Payable Claim interface
 */
interface ILazyPayableClaimV2 is ILazyPayableClaim {
    error Inactive();

    /**
     *  @notice Set the mint fees for claims
     */
    function setMintFees(uint256 mintFee, uint256 mintFeeMerkle) external;

    /**
     * @notice Set the active state of the claim, whether to allow new claims to be initialized
     */
    function setActive(bool active) external;
}
