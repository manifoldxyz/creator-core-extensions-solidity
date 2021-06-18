// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "./IERC1155RedeemBase.sol";

/**
 * @dev Claim redemption interface
 */
interface IERC1155ClaimRedeem is IERC1155RedeemBase {

    /**
     * @dev Initialize the redemption app.  Must be called.
     */
    function initialize(string calldata uri) external;

    /**
     * @dev Change the uri of the extension token
     */
    function updateURI(string calldata uri) external;

}