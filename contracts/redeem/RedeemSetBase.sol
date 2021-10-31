// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";

import "./IRedeemSetBase.sol";

/**
 * @dev Burn NFT's to receive another lazy minted NFT (set)
 */
abstract contract RedeemSetBase is AdminControl, IRedeemSetBase {
    // approved specific tokens
    RedemptionItem[] private _redemptionSet;

    function configureRedemptionSet(RedemptionItem[] memory redemptionSet) internal {
      for (uint i = 0; i < redemptionSet.length; i++) {
          RedemptionItem memory redemptionItem = redemptionSet[i];
          require(redemptionItem.minTokenId <= redemptionItem.maxTokenId, "Redeem: min must be less or equal to max");
          _redemptionSet.push(redemptionItem);
          emit RedeemSetApprovedTokenRange(redemptionItem.tokenAddress, redemptionItem.minTokenId, redemptionItem.maxTokenId);
        }
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(AdminControl, IERC165) returns (bool) {
        return interfaceId == type(IRedeemSetBase).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IRedeemSetBase-getRedemptionSet}
     */
    function getRedemptionSet() external override view returns(RedemptionItem[] memory) {
        return _redemptionSet;
    }

    /**
     * @dev Check to see if we have a complete redemption set
     */
    function _validateCompleteSet(address[] memory contracts, uint256[] memory tokenIds) internal view virtual returns (bool) {
       require(_redemptionSet.length == tokenIds.length, "Incorrect number of NFTs being redeemed");
       // Check complete set
       bool[] memory completions = new bool[](_redemptionSet.length);
       for (uint i = 0; i < contracts.length; i++) {
           for (uint j = 0; j < _redemptionSet.length; j++) {
               RedemptionItem memory redemptionItem = _redemptionSet[j];
               if (contracts[i] == redemptionItem.tokenAddress && tokenIds[i] >= redemptionItem.minTokenId && tokenIds[i] <= redemptionItem.maxTokenId) {
                   // Found redemption token
                   completions[j] = true;
                   break;
               }
           }
       }
       for (uint i = 0; i < completions.length; i++) {
           if (!completions[i]) return false;
       }
       return true;
    }

}