// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC721CreatorCore.sol";

import "./ERC721RedeemBase.sol";
import "./IERC721BurnRedeem.sol";

/**
 * @dev Burn NFT's to receive another lazy minted NFT
 */
contract ERC721Burn is ReentrancyGuard, ERC721RedeemBase, IERC721Burn, IERC1155Receiver, IERC721Receiver {
    using EnumerableSet for EnumerableSet.UintSet;

    mapping (address => mapping (uint256 => address)) private _recoverableERC721;

    constructor(address creator, uint16 redemptionRate, uint16 redemptionMax) ERC721RedeemBase(creator, redemptionRate, redemptionMax) {}

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721RedeemBase, IERC165) returns (bool) {
        return interfaceId == type(IERC721Burn).interfaceId || interfaceId == type(IERC1155Receiver).interfaceId
            || interfaceId == type(IERC721Receiver).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IERC721Burn-setERC721Recoverable}
     */
    function setERC721Recoverable(address contract_, uint256 tokenId, address recoverer) external virtual override adminRequired {
        require(ERC165Checker.supportsInterface(contract_, type(IERC721).interfaceId), "BurnRedeem: Must implement IERC721");
        _recoverableERC721[contract_][tokenId] = recoverer;
    }

    /**
     * @dev See {IERC721Burn-recoverERC721}
     */
    function recoverERC721(address contract_, uint256 tokenId) external virtual override {
        address recoverer = _recoverableERC721[contract_][tokenId];
        require(recoverer == msg.sender, "BurnRedeem: Permission denied");
        IERC721(contract_).safeTransferFrom(address(this), msg.sender, tokenId);
    }

    /**
     * @dev See {IERC721Burn-redeemERC721}
     */
    function redeemERC721(address[] calldata contracts, uint256[] calldata tokenIds) external virtual override nonReentrant {
        require(contracts.length == tokenIds.length, "BurnRedeem: Invalid parameters");
        require(contracts.length == _redemptionRate, "BurnRedeem: Incorrect number of NFTs being redeemed");

        // Attempt Burn
        for (uint i = 0; i < contracts.length; i++) {
            // Check that we can burn
            require(redeemable(contracts[i], tokenIds[i]), "BurnRedeem: Invalid NFT");

            try IERC721(contracts[i]).ownerOf(tokenIds[i]) returns (address ownerOfAddress) {
                require(ownerOfAddress == msg.sender, "BurnRedeem: Caller must own NFTs");
            } catch (bytes memory) {
                revert("BurnRedeem: Bad token contract");
            }

            if (!IERC721(contracts[i]).isApprovedForAll(msg.sender, address(this))) {
                try IERC721(contracts[i]).getApproved(tokenIds[i]) returns (address approvedAddress) {
                    require(approvedAddress == address(this), "BurnRedeem: Contract must be given approval to burn NFT");
                } catch (bytes memory) {
                    revert("BurnRedeem: Bad token contract");
                }
            }
            
            // Then burn
            try IERC721(contracts[i]).transferFrom(msg.sender, address(0xdEaD), tokenIds[i]) {
            } catch (bytes memory) {
                revert("BurnRedeem: Burn failure");
            }
        }

        // Mint reward
        _mintRedemption(msg.sender);
    }

    /**
     * @dev See {IERC721Receiver-onERC721Received}.
     */
    function onERC721Received(address, address from, uint256 tokenId, bytes calldata data) external override nonReentrant returns (bytes4) {
        require(redeemable(msg.sender, tokenId), "BurnRedeem: Invalid NFT");
        require(_redemptionRate == 1, "BurnRedeem: Can only allow direct receiving of redemptions of 1 NFT");
        
        
        // Burn it
        try IERC721(msg.sender).safeTransferFrom(address(this), address(0xdEaD), tokenId, data) {
        } catch (bytes memory) {
            revert("BurnRedeem: Burn failure");
        }

        // Mint reward
        _mintRedemption(from);

        return this.onERC721Received.selector;
    }


    /**
     * @dev See {IERC1155Receiver-onERC1155Received}.
     */
    function onERC1155Received(
        address,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external override nonReentrant returns(bytes4) {
        require(redeemable(msg.sender, id), "BurnRedeem: Invalid NFT");
        require(value == _redemptionRate, "BurnRedeem: Incorrect number of NFTs being redeemed");

        // Burn it
        try IERC1155(msg.sender).safeTransferFrom(address(this), address(0xdEaD), id, value, data) {
        } catch (bytes memory) {
            revert("BurnRedeem: Burn failure");
        }

        // Mint reward
        _mintRedemption(from);

        return this.onERC1155Received.selector;
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

        uint256 totalValue = 0;
        for (uint i=0; i<ids.length; i++) {
            require(redeemable(msg.sender, ids[i]), "BurnRedeem: Invalid NFT");
            totalValue += values[i];
        }

        require(totalValue == _redemptionRate, "BurnRedeem: Incorrect number of NFTs being redeemed");

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
