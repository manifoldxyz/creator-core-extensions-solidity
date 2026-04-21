// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

/// @author: manifold.xyz

import {AllowListData, PublicDrop} from "./SeaDropStructs.sol";

/**
 * @notice Pass-through subset of stock SeaDrop v1 (deployed at
 *         0x00005EA00Ac477B1030CE78506496e8C2dE24bf5) that
 *         ManifoldERC1155SeaDropShim forwards admin config to.
 * @dev Intentionally narrow: only the setters the shim proxies during
 *      initialize / multiConfigure / admin pass-through calls. The structs
 *      live in SeaDropStructs.sol so both the shim and this interface
 *      encode arguments identically to the deployed SeaDrop ABI.
 *      Token-gated drop and signed-mint setters are omitted (non-goals).
 */
interface ISeaDrop {
    function updatePublicDrop(PublicDrop calldata publicDrop) external;

    function updateAllowList(AllowListData calldata allowListData) external;

    function updateCreatorPayoutAddress(address payoutAddress) external;

    function updateAllowedFeeRecipient(address feeRecipient, bool allowed) external;

    function updateDropURI(string calldata dropURI) external;

    function updatePayer(address payer, bool allowed) external;
}
