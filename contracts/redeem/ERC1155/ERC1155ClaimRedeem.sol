// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC1155CreatorCore.sol";

import "./ERC1155RedeemBase.sol";
import "./IERC1155ClaimRedeem.sol";

/**
 * @dev Claim redemption via ERC721 NFT
 */
abstract contract ERC1155ClaimRedeem is ReentrancyGuard, ERC1155RedeemBase, IERC1155ClaimRedeem {

    mapping (address => mapping (uint256 => bool)) private _claimedERC721;    
    uint256 internal _redemptionTokenId;

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1155RedeemBase, IERC165) returns (bool) {
        return interfaceId == type(IERC1155ClaimRedeem).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IERC1155ClaimRedeem-initialize}.
     */
    function initialize(string calldata uri) external virtual override adminRequired {
        require(_redemptionTokenId == 0, "Already initialized");
        address[] memory receivers = new address[](1);
        receivers[0] = address(this);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0;
        string[] memory uris = new string[](1);
        uris[0] = uri;
        _redemptionTokenId = IERC1155CreatorCore(_creator).mintExtensionNew(receivers, amounts, uris)[0];
    }

    /**
     * @dev See {IERC1155ClaimRedeem-updateURI}.
     */
    function updateURI(string calldata uri) external virtual override adminRequired {
        require(_redemptionTokenId != 0, "Not initialized");
        IERC1155CreatorCore(_creator).setTokenURIExtension(_redemptionTokenId, uri);
    }

    function _recordRedemption(address contract_, uint256 tokenId) internal {
        require(!_claimedERC721[contract_][tokenId], "Already claimed");
        _claimedERC721[contract_][tokenId] = true;
    }

    /**
     * @dev See {IRedeemBase-redeemable}
     */
    function redeemable(address contract_, uint256 tokenId) public view virtual override(RedeemBase, IRedeemBase) returns(bool) {
       if (_claimedERC721[contract_][tokenId]) return false;
       return super.redeemable(contract_, tokenId);
    }

}