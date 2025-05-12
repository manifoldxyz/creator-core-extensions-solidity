// SPDX-License-Identifier: MIT
// solhint-disable reason-string
pragma solidity ^0.8.0;

import "./ILazyPayableClaimUSDC.sol";
import "./LazyPayableClaimCore.sol";

/**
 * @title Lazy Payable Claim for USDSC
 * @author manifold.xyz
 * @notice Lazy payable claim with optional whitelist
 */
abstract contract LazyPayableClaimUSDC is LazyPayableClaimCore, ILazyPayableClaimUSDC {
    // USDC MINT FEES
    uint256 public constant MINT_FEE = 1000000;
    uint256 public constant MINT_FEE_MERKLE = 1330000;
    // solhint-disable-next-line
    address public immutable USDC_ADDRESS;

    constructor(address initialOwner, address usdcAddress, address delegationRegistry, address delegationRegistryV2)
        LazyPayableClaimCore(initialOwner, delegationRegistry, delegationRegistryV2)
    {
        USDC_ADDRESS = usdcAddress;
    }

    /**
     * See {ILazyPayableClaim-withdraw}.
     */
    function withdraw(address payable receiver, uint256 amount) external override adminRequired {
        require(IERC20(USDC_ADDRESS).transfer(receiver, amount), "Failed to transfer USDC");
    }

    function _transferFunds(
        address erc20,
        uint256 cost,
        address payable recipient,
        uint16 mintCount,
        bool merkle,
        bool allowMembership
    ) internal {
        if (USDC_ADDRESS == ADDRESS_ZERO) {
            revert ILazyPayableClaimCore.InvalidInstance();
        }
        if (erc20 != USDC_ADDRESS) {
            revert ILazyPayableClaimCore.InvalidInstance();
        }

        uint256 payableCost = cost;
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

        require(IERC20(erc20).transferFrom(msg.sender, address(this), payableCost), "Insufficient funds");
        IERC20(erc20).transfer(recipient, cost);
    }
}
