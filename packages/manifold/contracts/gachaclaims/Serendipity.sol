// SPDX-License-Identifier: MIT
// solhint-disable reason-string
pragma solidity ^0.8.0;

import "./ISerendipity.sol";
import "./SerendipityCore.sol";

/**
 * @title Serendipity Lazy Claim
 * @author manifold.xyz
 * @notice ETH payment version of Serendipity
 */
abstract contract Serendipity is SerendipityCore, ISerendipity {
    uint256 public constant MINT_FEE = 500000000000000;

    constructor(address initialOwner) SerendipityCore(initialOwner) {}

    /**
     * See {ISerendipityCore-withdraw}.
     */
    function withdraw(address payable receiver, uint256 amount) external override adminRequired {
        (bool sent, ) = receiver.call{ value: amount }("");
        if (!sent) revert ISerendipityCore.FailedToTransfer();
    }

    function _sendFunds(address payable recipient, uint256 amount) internal {
        if (recipient == ADDRESS_ZERO) revert FailedToTransfer();
        (bool sent, ) = recipient.call{ value: amount }("");
        if (!sent) revert FailedToTransfer();
    }

    function _transferFundsETH(
        uint256 cost,
        address payable recipient,
        uint32 mintCount
    ) internal {
        uint256 expectedPayment = (cost + MINT_FEE) * mintCount;
        if (msg.value != expectedPayment) revert ISerendipityCore.InvalidPayment();

        if (cost > 0) {
            _sendFunds(recipient, cost * mintCount);
        }
    }

    function _refundExcessETH(
        uint256 cost,
        uint32 mintCount,
        uint32 actualMintCount
    ) internal {
        if (actualMintCount != mintCount) {
            uint256 refundAmount = (cost + MINT_FEE) * (mintCount - actualMintCount);
            _sendFunds(payable(msg.sender), refundAmount);
        }
    }
}
