// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "../IRedeemSetBase.sol";

/**
 * @dev Base redemption interface
 */
interface IERC721RedeemSetBase is IRedeemSetBase {
    /**
     * @dev Get the max number of redemptions
     */
    function redemptionMax() external view returns(uint16);
    
    /**
     * @dev Get number of redemptions left
     */
    function redemptionRemaining() external view returns(uint16);

    /**
     * @dev Get the mint number of a created token id
     */
    function mintNumber(uint256 tokenId) external view returns(uint256);

    /**
     * @dev Get list of all minted tokens
     */
    function mintedTokens() external view returns(uint256[] memory);

}