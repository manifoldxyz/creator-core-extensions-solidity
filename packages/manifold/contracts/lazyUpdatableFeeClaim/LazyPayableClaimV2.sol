// SPDX-License-Identifier: MIT
// solhint-disable reason-string
pragma solidity ^0.8.0;

import "../lazyclaim/LazyPayableClaimCore.sol";
import "./ILazyPayableClaimV2.sol";

/**
 * @title Lazy Payable Claim
 * @author manifold.xyz
 * @notice Lazy payable claim with optional whitelist
 */
abstract contract LazyPayableClaimV2 is LazyPayableClaimCore, ILazyPayableClaimV2 {
    // solhint-disable-next-line
    uint256 public MINT_FEE;
    // solhint-disable-next-line
    uint256 public MINT_FEE_MERKLE;
    bool public active = true;

    constructor(address initialOwner, address delegationRegistry, address delegationRegistryV2)
        LazyPayableClaimCore(initialOwner, delegationRegistry, delegationRegistryV2)
    {}

    /**
     * See {ILazyPayableClaim-withdraw}.
     */
    function withdraw(address payable receiver, uint256 amount) external override adminRequired {
        (bool sent,) = receiver.call{value: amount}("");
        if (!sent) revert ILazyPayableClaimCore.FailedToTransfer();
    }

    /**
     * See {ILazyPayableClaimV2-setMintFees}.
     */
    function setMintFees(uint256 _mintFee, uint256 _mintFeeMerkle) external override adminRequired {
        MINT_FEE = _mintFee;
        MINT_FEE_MERKLE = _mintFeeMerkle;
    }

    /**
     * See {ILazyPayableClaimV2-setActive}.
     */
    function setActive(bool _active) external override adminRequired {
        active = _active;
    }

    function _transferFunds(
        address erc20,
        uint256 cost,
        address payable recipient,
        uint16 mintCount,
        bool merkle,
        bool allowMembership
    ) internal {
        uint256 payableCost;
        if (erc20 != ADDRESS_ZERO) {
            require(IERC20(erc20).transferFrom(msg.sender, recipient, cost * mintCount), "Insufficient funds");
        } else {
            payableCost = cost;
        }

        /**
         * Add mint fee if:
         * 1. Not allowing memberships OR
         * 2. No membership address set OR
         * 3. Not an active member
         */
        if (
            MEMBERSHIP_ADDRESS == ADDRESS_ZERO || !allowMembership
                || !IManifoldMembership(MEMBERSHIP_ADDRESS).isActiveMember(msg.sender)
        ) {
            payableCost += merkle ? MINT_FEE_MERKLE : MINT_FEE;
        }
        if (mintCount > 1) {
            payableCost *= mintCount;
            cost *= mintCount;
        }

        // Check price
        require(msg.value >= payableCost, "Invalid amount");
        if (erc20 == ADDRESS_ZERO && cost != 0) {
            // solhint-disable-next-line
            (bool sent,) = recipient.call{value: cost}("");
            if (!sent) revert ILazyPayableClaimCore.FailedToTransfer();
        }
    }
}
