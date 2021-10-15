// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@manifoldxyz/creator-core-solidity/contracts/core/IERC721CreatorCore.sol";

import "./ERC721RedeemBase.sol";
import "./IERC721BurnRedeemSet.sol";

/**
 * @dev Burn NFT's to receive another lazy minted NFT
 */
contract ERC721BurnRedeemSet is ReentrancyGuard, ERC721RedeemBase, IERC721BurnRedeemSet, IERC1155Receiver {
    using EnumerableSet for EnumerableSet.UintSet;

    mapping (address => mapping (uint256 => address)) private _recoverableERC721;
    RedemptionItem[] private _redemptionSet;

    constructor(address creator, RedemptionItem[] memory redemptionSet, uint16 redemptionMax) ERC721RedeemBase(creator, uint16(redemptionSet.length), redemptionMax) {
        for (uint i = 0; i < redemptionSet.length; i++) {
            RedemptionItem memory redemptionItem = redemptionSet[i];
            _approvedTokenRange[redemptionItem.tokenAddress].push(range(redemptionItem.minTokenId, redemptionItem.maxTokenId));
            _redemptionSet.push(redemptionItem);
        }
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721RedeemBase, IERC165) returns (bool) {
        return interfaceId == type(IERC721BurnRedeemSet).interfaceId || interfaceId == type(IERC1155Receiver).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IERC721BurnRedeemSet-setERC721Recoverable}
     */
    function setERC721Recoverable(address contract_, uint256 tokenId, address recoverer) external virtual override adminRequired {
        require(ERC165Checker.supportsInterface(contract_, type(IERC721).interfaceId), "BurnRedeem: Must implement IERC721");
        _recoverableERC721[contract_][tokenId] = recoverer;
    }

    /**
     * @dev See {IERC721BurnRedeemSet-getRedemptionSet}
     */
    function getRedemptionSet() external override view returns(RedemptionItem[] memory) {
        return _redemptionSet;
    }

    /**
     * @dev See {IERC721BurnRedeemSet-recoverERC721}
     */
    function recoverERC721(address contract_, uint256 tokenId) external virtual override {
        address recoverer = _recoverableERC721[contract_][tokenId];
        require(recoverer == msg.sender, "BurnRedeem: Permission denied");
        IERC721(contract_).safeTransferFrom(address(this), msg.sender, tokenId);
    }

    /**
     * @dev Check to see if we have a complete redemption set
     */
    function _validateCompleteSet(address[] memory contracts, uint256[] memory tokenIds) private view returns (bool) {
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

    /**
     * @dev See {IERC721BurnRedeemSet-redeemERC721}
     */
    function redeemERC721(address[] calldata contracts, uint256[] calldata tokenIds) external virtual override nonReentrant {
        require(contracts.length == tokenIds.length, "BurnRedeem: Invalid parameters");
        require(contracts.length == _redemptionRate, "BurnRedeem: Incorrect number of NFTs being redeemed");
        require(_validateCompleteSet(contracts, tokenIds), "BurnRedeem: Incomplete set");

        // Attempt Burn
        for (uint i=0; i<contracts.length; i++) {
            try IERC721(contracts[i]).ownerOf(tokenIds[i]) returns (address ownerOfAddress) {
                require(ownerOfAddress == msg.sender, "BurnRedeem: Caller must own NFTs");
            } catch (bytes memory) {
                revert("BurnRedeem: Bad token contract");
            }

            try IERC721(contracts[i]).getApproved(tokenIds[i]) returns (address approvedAddress) {
                require(approvedAddress == address(this), "BurnRedeem: Contract must be given approval to burn NFT");
            } catch (bytes memory) {
                revert("BurnRedeem: Bad token contract");
            }
            

            // Burn
            try IERC721(contracts[i]).transferFrom(msg.sender, address(0xdEaD), tokenIds[i]) {
            } catch (bytes memory) {
                revert("BurnRedeem: Burn failure");
            }
        }

        // Mint reward
        _mintRedemption(msg.sender);
    }

    /**
     * @dev See {IERC1155Receiver-onERC1155Received}.
     */
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external override returns(bytes4) {
        revert("BurnRedeem: Incomplete set");
    }

    /**
     * @dev See {IERC1155Receiver-onERC1155BatchReceived}.
     */
    function onERC1155BatchReceived(
        address,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external override nonReentrant returns(bytes4) {
        require(ids.length == values.length, "BurnRedeem: Invalid input");
        address[] memory contracts = new address[](ids.length);
        for (uint i=0; i<ids.length; i++) {
            require(values[i] == 1, "BurnRedeem: Can only use one of each token");
            contracts[i] = msg.sender;
        }

        require(_validateCompleteSet(contracts, ids), "BurnRedeem: Incomplete set");

        // Burn it
        try IERC1155(msg.sender).safeBatchTransferFrom(address(this), address(0xdEaD), ids, values, data) {
        } catch (bytes memory) {
            revert("BurnRedeem: Burn failure");
        }

        // Mint reward
        _mintRedemption(from);

        return this.onERC1155BatchReceived.selector;
    }

}