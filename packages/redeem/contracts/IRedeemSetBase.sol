// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/libraries-solidity/contracts/access/IAdminControl.sol";

/**
 * @dev Base redemption interface
 */
interface IRedeemSetBase is IAdminControl {

    event RedeemSetApprovedTokenRange(address tokenAddress, uint256 minTokenId, uint256 maxTokenId);
    
    struct RedemptionItem {
        address tokenAddress;
        uint256 minTokenId;
        uint256 maxTokenId;
    }

    /**
     * @dev Get the attributes of the complete set needed for redemption
     */
    function getRedemptionSet() external view returns(RedemptionItem[] memory);

}