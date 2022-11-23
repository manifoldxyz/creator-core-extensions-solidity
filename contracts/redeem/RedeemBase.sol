// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";

import "./IRedeemBase.sol";


/**
 * @dev Burn NFT's to receive another lazy minted NFT
 */
abstract contract RedeemBase is AdminControl, IRedeemBase {
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;

    // approved contract tokens
    EnumerableSet.AddressSet internal _approvedContracts;

    // approved specific tokens
    EnumerableSet.AddressSet internal _approvedTokensContracts;
    mapping(address => EnumerableSet.UintSet) internal _approvedTokens;
    EnumerableSet.AddressSet internal _approvedTokenRangeContracts;
    mapping(address => IRedeemBase.TokenRange[]) internal _approvedTokenRange;
     
    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(AdminControl, IERC165) returns (bool) {
        return interfaceId == type(IRedeemBase).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IRedeemBase-updateApprovedContracts}
     */
    function updateApprovedContracts(address[] memory contracts, bool[] memory approved) public virtual override adminRequired {
        require(contracts.length == approved.length, "Redeem: Invalid input parameters");
        for (uint i=0; i < contracts.length; i++) {
            if (approved[i]) {
                _approvedContracts.add(contracts[i]);
            } else {
                _approvedContracts.remove(contracts[i]);
            }
        }
        emit UpdateApprovedContracts(contracts, approved);
    }

    /**
     * @dev See {IRedeemBase-getApprovedContracts}
     */
    function getApprovedContracts() public virtual view override returns (address[] memory contracts) {
        contracts = new address[](_approvedContracts.length());
        for (uint i=0; i < _approvedContracts.length(); i++) {
            contracts[i] = _approvedContracts.at(i);
        }
    }
    
    /**
     * @dev See {IRedeemBase-updateApprovedTokens}
     */
    function updateApprovedTokens(address contract_, uint256[] memory tokenIds, bool[] memory approved) public virtual override adminRequired {
        require(tokenIds.length == approved.length, "Redeem: Invalid input parameters");
        for (uint i=0; i < tokenIds.length; i++) {
            if (approved[i] && !_approvedTokens[contract_].contains(tokenIds[i])) {
                _approvedTokens[contract_].add(tokenIds[i]);
            } else if (!approved[i] && _approvedTokens[contract_].contains(tokenIds[i])) {
                _approvedTokens[contract_].remove(tokenIds[i]);
            }
        }
        if (_approvedTokens[contract_].length() > 0) {
            _approvedTokensContracts.add(contract_);
        } else {
            _approvedTokensContracts.remove(contract_);
        }
        emit UpdateApprovedTokens(contract_, tokenIds, approved);
    }

    /**
     * @dev See {IRedeemBase-getApprovedTokens}
     */
    function getApprovedTokens() public virtual view override returns(address[] memory contracts, uint256[][] memory tokenIds) {
        contracts = new address[](_approvedTokensContracts.length());
        tokenIds = new uint[][](_approvedTokensContracts.length());
        for (uint i=0; i < _approvedTokensContracts.length(); i++) {
            address contract_ = _approvedTokensContracts.at(i);
            contracts[i] = contract_;
            EnumerableSet.UintSet storage approvedTokens = _approvedTokens[contract_];
            tokenIds[i] = new uint[](approvedTokens.length());
            for (uint j=0; j < approvedTokens.length(); j++) {
                tokenIds[i][j] = approvedTokens.at(j);
            }
        }
    }

    /**
     * @dev See {IRedeemBase-updateApprovedTokenRanges}
     */
    function updateApprovedTokenRanges(address contract_, uint256[] memory minTokenIds, uint256[] memory maxTokenIds) public virtual override adminRequired {
        require(minTokenIds.length == maxTokenIds.length, "Redeem: Invalid input parameters");
        delete _approvedTokenRange[contract_];
        for (uint i=0; i < minTokenIds.length; i++) {
            require(minTokenIds[i] < maxTokenIds[i], "Redeem: min must be less than max");
            _approvedTokenRange[contract_].push(IRedeemBase.TokenRange(minTokenIds[i], maxTokenIds[i]));
        }
        if (minTokenIds.length > 0) {
            _approvedTokenRangeContracts.add(contract_);
        } else {
            _approvedTokenRangeContracts.remove(contract_);
        }
        emit UpdateApprovedTokenRanges(contract_, minTokenIds, maxTokenIds);
    }
    
    /**
     * @dev See {IRedeemBase-getApprovedTokenRanges}
     */
    function getApprovedTokenRanges() public virtual view override returns(address[] memory contracts, IRedeemBase.TokenRange[][] memory tokenRanges) {
        contracts = new address[](_approvedTokenRangeContracts.length());
        tokenRanges = new IRedeemBase.TokenRange[][](_approvedTokenRangeContracts.length());
        for (uint i=0; i < _approvedTokenRangeContracts.length(); i++) {
            address contract_ = _approvedTokenRangeContracts.at(i);
            contracts[i] = contract_;
            tokenRanges[i] = _approvedTokenRange[contract_];
        }
    }

    /**
     * @dev See {IRedeemBase-redeemable}
     */    
    function redeemable(address contract_, uint256 tokenId) public view virtual override returns(bool) {
         if (_approvedContracts.contains(contract_)) {
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


}