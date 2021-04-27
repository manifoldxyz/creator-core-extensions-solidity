// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "openzeppelin-solidity/contracts/security/ReentrancyGuard.sol";
import "openzeppelin-solidity/contracts/token/ERC1155/IERC1155.sol";
import "openzeppelin-solidity/contracts/token/ERC721/IERC721.sol";
import "openzeppelin-solidity/contracts/utils/introspection/ERC165Checker.sol";
import "openzeppelin-solidity/contracts/utils/structs/EnumerableSet.sol";

import "manifoldxyz-creator-core-solidity/contracts/ERC721CreatorExtension.sol";
import "manifoldxyz-libraries-solidity/contracts/access/AdminControl.sol";

import "./INFTRedeem.sol";

struct range{
   uint256 min;
   uint256 max;
}

contract NFTRedeem is ReentrancyGuard, AdminControl, ERC721CreatorExtension, INFTRedeem {
     using EnumerableSet for EnumerableSet.UintSet;

     mapping (address => mapping (uint256 => address)) private _recoverableERC721;

     uint16 private immutable _redemptionRate;
     uint16 private _redemptionRemaining;

     // approved contracts
    mapping(address => bool) private _approvedContracts;
    // approved tokens
    mapping(address => EnumerableSet.UintSet) private _approvedTokens;
    mapping(address => range[]) private _approvedTokenRange;
     
    constructor(address creator, uint16 redemptionRate_, uint16 redemptionRemaining_) ERC721CreatorExtension(creator) {
        require(ERC165Checker.supportsInterface(creator, type(IERC721Creator).interfaceId), "NFTRedeem: Must implement IERCreator");
        _redemptionRate = redemptionRate_;
        _redemptionRemaining = redemptionRemaining_;
    }     

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(AdminControl, ERC721CreatorExtension, IERC165) returns (bool) {
        return interfaceId == type(INFTRedeem).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {INFTRedeem-setERC721Recoverable}
     */
    function setERC721Recoverable(address contract_, uint256 tokenId, address recoverer) external virtual override adminRequired {
        require(ERC165Checker.supportsInterface(contract_, type(IERC721).interfaceId), "NFTRedeem: Must implement IERC721");
        _recoverableERC721[contract_][tokenId] = recoverer;
    }

    /**
     * @dev See {INFTRedeem-updateApprovedContracts}
     */
    function updateApprovedContracts(address[] calldata contracts, bool[] calldata approved) external virtual override adminRequired {
        require(contracts.length == approved.length, "NFTRedeem: Invalid input parameters");
        for (uint i=0; i < contracts.length; i++) {
            _approvedContracts[contracts[i]] = approved[i];
        }
    }
    
    /**
     * @dev See {INFTRedeem-updateApprovedTokens}
     */
    function updateApprovedTokens(address contract_, uint256[] calldata tokenIds, bool[] calldata approved) external virtual override adminRequired {
        require(tokenIds.length == approved.length, "NFTRedeem: Invalid input parameters");

        for (uint i=0; i < tokenIds.length; i++) {
            if (approved[i] && !_approvedTokens[contract_].contains(tokenIds[i])) {
                _approvedTokens[contract_].add(tokenIds[i]);
            } else if (!approved[i] && _approvedTokens[contract_].contains(tokenIds[i])) {
                _approvedTokens[contract_].remove(tokenIds[i]);
            }
        }
    }

    /**
     * @dev See {INFTRedeem-updateApprovedTokenRanges}
     */
    function updateApprovedTokenRanges(address contract_, uint256[] calldata minTokenIds, uint256[] calldata maxTokenIds) external virtual override adminRequired {
        require(minTokenIds.length == maxTokenIds.length, "NFTRedeem: Invalid input parameters");
        
        uint existingRangesLength = _approvedTokenRange[contract_].length;
        for (uint i=0; i < existingRangesLength; i++) {
            _approvedTokenRange[contract_][i].min = 0;
            _approvedTokenRange[contract_][i].max = 0;
        }
        
        for (uint i=0; i < minTokenIds.length; i++) {
            require(minTokenIds[i] < maxTokenIds[i], "NFTRedeem: min must be less than max");
            if (i < existingRangesLength) {
                _approvedTokenRange[contract_][i].min = minTokenIds[i];
                _approvedTokenRange[contract_][i].max = maxTokenIds[i];
            } else {
                _approvedTokenRange[contract_].push(range(minTokenIds[i], maxTokenIds[i]));
            }
        }
    }

    /**
     * @dev See {INFTRedeem-recoverERC721}
     */
    function recoverERC721(address contract_, uint256 tokenId) external virtual override {
        address recoverer = _recoverableERC721[contract_][tokenId];
        require(recoverer == msg.sender, "NFTRedeem: Permission denied");
        IERC721(contract_).safeTransferFrom(address(this), msg.sender, tokenId);
    }

    /**
     * @dev See {INFTRedeem-redeemERC721}
     */
    function redeemERC721(address[] calldata contracts, uint256[] calldata tokenIds) external virtual override nonReentrant {

        require(contracts.length == tokenIds.length, "NFTRedeem: Invalid parameters");
        require(contracts.length == _redemptionRate, "NFTRedeem: Incorrect number of NFTs being redeemed");
        require(_redemptionRemaining > 0, "NFTRedeem: No redemptions remaining");

        // Attempt Burn
        for (uint i=0; i<contracts.length; i++) {
            // Check that we can burn
            require(redeemable(contracts[i], tokenIds[i]), "NFTRedeem: Invalid token");

            (bool ownerOfSuccess, bytes memory ownerOfReturnData) = contracts[i].call(abi.encodeWithSelector(IERC721.ownerOf.selector, tokenIds[i]));
            require(ownerOfSuccess, "NFTRedeem: Bad token contract");
            address ownerOfAddress = abi.decode(ownerOfReturnData, (address));
            require(ownerOfAddress == msg.sender, "NFTRedeem: Caller must own NFTs");

            (bool approvedSuccess, bytes memory approvedReturnData) = contracts[i].call(abi.encodeWithSelector(IERC721.getApproved.selector, tokenIds[i]));
            require(approvedSuccess, "NFTRedeem: Bad token contract");
            address approvedAddress = abi.decode(approvedReturnData, (address));
            require(approvedAddress == address(this), "NFTRedeem: Contract must be given approval to burn NFT");

            // Then burn
            (bool burnSuccess,) = contracts[i].call(abi.encodeWithSelector(IERC721.transferFrom.selector, msg.sender, address(0xdEaD), tokenIds[i]));
            require(burnSuccess, "NFTRedeem: Burn failure");
        }

        _redemptionRemaining--;

        // Mint reward
        (bool mintSuccess,) = _creator.call(abi.encodeWithSelector(IERC721Creator.mint.selector, msg.sender));
        require(mintSuccess, "NFTRedeem: Redemption failure");
    }

    /**
     * @dev See {INFTRedeem-redemptionRate}
     */
    function redemptionRate() external view virtual override returns(uint16) {
        return _redemptionRate;
    }

    /**
     * @dev See {INFTRedeem-redemptionRemaining}
     */
    function redemptionRemaining() external view virtual override returns(uint16) {
        return _redemptionRemaining;
    }

    /**
     * @dev See {INFTRedeem-redeemable}
     */    
    function redeemable(address contract_, uint256 tokenId) public view virtual override returns(bool) {
         require(_redemptionRemaining > 0, "NFTRedeem: No redemptions remaining");

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

    /*
     * @dev See {IERC1155Receiver-onERC1155Received}.
     */
    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external override nonReentrant returns(bytes4) {
        require(redeemable(operator, id), "NFTRedeem: Invalid token");
        require(value == _redemptionRate, "NFTRedeem: Incorrect number of NFT's being redeemed");

        _redemptionRemaining--;
        
        // Burn it
        IERC1155(operator).safeTransferFrom(address(this), address(0xdEaD), id, value, data);

        // Mint reward
        IERC721Creator(_creator).mint(from);

        return this.onERC1155Received.selector;
    }

    /*
     * @dev See {IERC1155Receiver-onERC1155BatchReceived}.
     */
    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external override nonReentrant returns(bytes4) {
        require(ids.length == values.length, "NFTRedeem: Invalid input");

        uint256 totalValue = 0;
        for (uint i=0; i<ids.length; i++) {
            require(redeemable(operator, ids[i]), "NFTRedeem: Invalid token");
            totalValue += values[i];
        }

        require(totalValue == _redemptionRate, "NFTRedeem: Incorrect number of NFT's being redeemed");

        _redemptionRemaining--;

        // Burn
        IERC1155(operator).safeBatchTransferFrom(address(this), address(0xdEaD), ids, values, data);

        // Mint reward
        IERC721Creator(_creator).mint(from);

        return this.onERC1155BatchReceived.selector;
    }

}