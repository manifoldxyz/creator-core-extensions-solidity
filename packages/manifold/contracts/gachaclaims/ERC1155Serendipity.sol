// SPDX-License-Identifier: MIT
// solhint-disable reason-string
pragma solidity ^0.8.0;

import "./ERC1155SerendipityCore.sol";
import "./Serendipity.sol";
import "./ISerendipityCore.sol";

/**
 * @title Serendipity Lazy Payable Claim - ERC-1155
 * @author manifold.xyz
 * @notice ERC1155 Serendipity with ETH payment
 */
contract ERC1155Serendipity is ERC1155SerendipityCore, Serendipity {
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1155SerendipityCore, AdminControl) returns (bool) {
        return ERC1155SerendipityCore.supportsInterface(interfaceId);
    }

    constructor(address initialOwner) Serendipity(initialOwner) {}

    /**
     * See {ISerendipity-mintReserve}.
     */
    function mintReserve(address creatorContractAddress, uint256 instanceId, uint32 mintCount) external payable override {
        (Claim storage claim, uint32 amountToReserve) = _validateMintReserve(creatorContractAddress, instanceId, mintCount);

        // Validate ETH payment
        if (msg.value != (claim.cost + MINT_FEE) * mintCount) revert ISerendipityCore.InvalidPayment();

        // Update state
        _updateMintReserve(creatorContractAddress, instanceId, claim, amountToReserve);

        // Send funds to payment receiver
        if (claim.cost > 0) {
            _sendFunds(claim.paymentReceiver, claim.cost * amountToReserve);
        }

        // Refund any overpayment if we reserved less than requested
        if (amountToReserve != mintCount) {
            uint256 refundAmount = (claim.cost + MINT_FEE) * (mintCount - amountToReserve);
            _sendFunds(payable(msg.sender), refundAmount);
        }
        emit SerendipityMintReserved(creatorContractAddress, instanceId, msg.sender, amountToReserve);
    }
}
