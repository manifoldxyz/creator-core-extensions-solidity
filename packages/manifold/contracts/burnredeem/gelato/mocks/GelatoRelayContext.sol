// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";

/**
 * @title GelatoRelayContext Mock
 * @notice Minimal implementation of Gelato's ERC-2771 context for testing
 * @dev This is a simplified version for testing. In production, use @gelatonetwork/relay-context
 *
 * How ERC-2771 works:
 * - Trusted forwarder appends original sender (20 bytes) to end of calldata
 * - _msgSender() extracts those last 20 bytes if called by trusted forwarder
 * - Otherwise falls back to msg.sender
 */
abstract contract GelatoRelayContext is Context {
    // Gelato's actual trusted forwarder on all networks
    address private constant _GELATO_RELAY = 0xaBcC9b596420A9E9172FD5938620E265a0f9Df92;

    /**
     * @notice Extract original sender from calldata if called by trusted forwarder
     * @dev Last 20 bytes of calldata contain the original sender address
     */
    function _msgSender() internal view virtual override returns (address sender) {
        if (msg.sender == _GELATO_RELAY && msg.data.length >= 20) {
            // Extract last 20 bytes as address
            assembly {
                sender := shr(96, calldataload(sub(calldatasize(), 20)))
            }
        } else {
            sender = msg.sender;
        }
    }

    /**
     * @notice Get msg.data without appended sender
     * @dev Removes last 20 bytes if called by trusted forwarder
     */
    function _msgData() internal view virtual override returns (bytes calldata) {
        if (msg.sender == _GELATO_RELAY && msg.data.length >= 20) {
            return msg.data[:msg.data.length - 20];
        } else {
            return msg.data;
        }
    }

    /**
     * @notice Check if caller is the trusted Gelato relay
     */
    function isTrustedForwarder(address forwarder) internal pure returns (bool) {
        return forwarder == _GELATO_RELAY;
    }
}
