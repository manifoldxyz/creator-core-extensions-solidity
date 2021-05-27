// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "manifoldxyz-creator-core-solidity/contracts/core/IERC721CreatorCore.sol";
import "manifoldxyz-creator-core-solidity/contracts/extensions/CreatorExtension.sol";
import "manifoldxyz-libraries-solidity/contracts/access/AdminControl.sol";

import "./IRedeemBase.sol";

struct range{
   uint256 min;
   uint256 max;
}

/**
 * @dev Burn NFT's to receive another lazy minted NFT
 */
abstract contract RedeemBase is AdminControl, CreatorExtension, IRedeemBase {
     using EnumerableSet for EnumerableSet.UintSet;

     // The creator mint contract
     address internal _creator;

     uint16 internal immutable _redemptionRate;
     uint16 private _redemptionMax;
     uint16 private _redemptionCount;
     uint256[] private _mintedTokens;
     mapping(uint256 => uint256) private _mintNumbers;

     // approved contract tokens
    mapping(address => bool) private _approvedContracts;

    // approved specific tokens
    mapping(address => EnumerableSet.UintSet) private _approvedTokens;
    mapping(address => range[]) private _approvedTokenRange;
     
    constructor(address creator, uint16 redemptionRate_, uint16 redemptionMax_) {
        require(ERC165Checker.supportsInterface(creator, type(IERC721CreatorCore).interfaceId), "BurnRedeem: Minting reward contract must implement IERC721CreatorCore");
        _redemptionRate = redemptionRate_;
        _redemptionMax = redemptionMax_;
        _creator = creator;
    }     

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(AdminControl, CreatorExtension, IERC165) returns (bool) {
        return interfaceId == type(IRedeemBase).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IRedeemBase-updateApprovedContracts}
     */
    function updateApprovedContracts(address[] memory contracts, bool[] memory approved) public virtual override adminRequired {
        require(contracts.length == approved.length, "BurnRedeem: Invalid input parameters");
        for (uint i=0; i < contracts.length; i++) {
            _approvedContracts[contracts[i]] = approved[i];
        }
    }
    
    /**
     * @dev See {IRedeemBase-updateApprovedTokens}
     */
    function updateApprovedTokens(address contract_, uint256[] memory tokenIds, bool[] memory approved) public virtual override adminRequired {
        require(tokenIds.length == approved.length, "BurnRedeem: Invalid input parameters");

        for (uint i=0; i < tokenIds.length; i++) {
            if (approved[i] && !_approvedTokens[contract_].contains(tokenIds[i])) {
                _approvedTokens[contract_].add(tokenIds[i]);
            } else if (!approved[i] && _approvedTokens[contract_].contains(tokenIds[i])) {
                _approvedTokens[contract_].remove(tokenIds[i]);
            }
        }
    }

    /**
     * @dev See {IRedeemBase-updateApprovedTokenRanges}
     */
    function updateApprovedTokenRanges(address contract_, uint256[] memory minTokenIds, uint256[] memory maxTokenIds) public virtual override adminRequired {
        require(minTokenIds.length == maxTokenIds.length, "BurnRedeem: Invalid input parameters");
        
        uint existingRangesLength = _approvedTokenRange[contract_].length;
        for (uint i=0; i < existingRangesLength; i++) {
            _approvedTokenRange[contract_][i].min = 0;
            _approvedTokenRange[contract_][i].max = 0;
        }
        
        for (uint i=0; i < minTokenIds.length; i++) {
            require(minTokenIds[i] < maxTokenIds[i], "BurnRedeem: min must be less than max");
            if (i < existingRangesLength) {
                _approvedTokenRange[contract_][i].min = minTokenIds[i];
                _approvedTokenRange[contract_][i].max = maxTokenIds[i];
            } else {
                _approvedTokenRange[contract_].push(range(minTokenIds[i], maxTokenIds[i]));
            }
        }
    }

    /**
     * @dev See {IRedeemBase-redemptionRate}
     */
    function redemptionRate() external view virtual override returns(uint16) {
        return _redemptionRate;
    }

    /**
     * @dev See {IRedeemBase-redemptionRemaining}
     */
    function redemptionRemaining() external view virtual override returns(uint16) {
        return _redemptionMax-_redemptionCount;
    }

    /**
     * @dev See {IRedeemBase-redeemable}
     */    
    function redeemable(address contract_, uint256 tokenId) public view virtual override returns(bool) {
        require(_redemptionCount < _redemptionMax, "BurnRedeem: No redemptions remaining");

         if (_approvedContracts[contract_]) {
             return true;
         }
         if (_approvedTokens[contract_].contains(tokenId)) {
             return true;
         }
         if (_approvedTokenRange[contract_].length > 0) {
             for (uint i=0; i < _approvedTokenRange[contract_].length; i++) {
                 if (_approvedTokenRange[contract_][i].max != 0 && tokenId >= _approvedTokenRange[contract_][i].min && tokenId <= _approvedTokenRange[contract_][i].max) {
                     return true;
                 }
             }
         }
         return false;
    }

    /**
     * @dev See {IRedeemBase-mintNumber}.
     */
    function mintNumber(uint256 tokenId) external view override returns(uint256) {
        return _mintNumbers[tokenId];
    }

    /**
     * @dev See {IRedeemBase-mintedTokens}.
     */
    function mintedTokens() external view override returns(uint256[] memory) {
        return _mintedTokens;
    }

    /**
     * @dev mint token that was redeemed for
     */
    function _mintRedemption(address to) internal {
        require(_redemptionCount < _redemptionMax, "Redeem: No redemptions remaining");
        _redemptionCount++;
        
        // Mint token
        uint256 tokenId = _mint(to);

        _mintedTokens.push(tokenId);
        _mintNumbers[tokenId] = _redemptionCount;
    }

    /**
     * @dev override if you want to perform different mint functionality
     */
    function _mint(address to) internal returns (uint256) {
        return IERC721CreatorCore(_creator).mintExtension(to);
    }

}