// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC721CreatorCore.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/CreatorExtension.sol";

import "../../libraries/single-creator/ERC721/ERC721SingleCreatorExtension.sol";

import "../RedeemBase.sol";
import "./IERC721RedeemBase.sol";

/**
 * @dev Redeem NFT base logic
 */
abstract contract ERC721RedeemBase is ERC721SingleCreatorExtension, RedeemBase, CreatorExtension, IERC721RedeemBase {

    uint16 internal immutable _redemptionRate;
    uint16 private _redemptionMax;
    uint16 private _redemptionCount;
    uint256[] private _mintedTokens;
    mapping(uint256 => uint256) internal _mintNumbers;

    constructor(address creator, uint16 redemptionRate_, uint16 redemptionMax_) ERC721SingleCreatorExtension(creator) {
        require(ERC165Checker.supportsInterface(creator, type(IERC721CreatorCore).interfaceId) ||
                ERC165Checker.supportsInterface(creator, LegacyInterfaces.IERC721CreatorCore_v1), 
                "Redeem: Minting reward contract must implement IERC721CreatorCore");
        _redemptionRate = redemptionRate_;
        _redemptionMax = redemptionMax_;
    }     

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(RedeemBase, CreatorExtension, IERC165) returns (bool) {
        return interfaceId == type(IERC721RedeemBase).interfaceId || RedeemBase.supportsInterface(interfaceId) || CreatorExtension.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IERC721RedeemBase-redemptionMax}
     */
    function redemptionMax() external view virtual override returns(uint16) {
        return _redemptionMax;
    }

    /**
     * @dev See {IERC721RedeemBase-redemptionRate}
     */
    function redemptionRate() external view virtual override returns(uint16) {
        return _redemptionRate;
    }

    /**
     * @dev See {IERC721RedeemBase-redemptionRemaining}
     */
    function redemptionRemaining() public view virtual override returns(uint16) {
        return _redemptionMax-_redemptionCount;
    }

    /**
     * @dev See {IERC721RedeemBase-mintNumber}.
     */
    function mintNumber(uint256 tokenId) external view virtual override returns(uint256) {
        return _mintNumbers[tokenId];
    }

    /**
     * @dev See {IERC721RedeemBase-mintedTokens}.
     */
    function mintedTokens() external view override returns(uint256[] memory) {
        return _mintedTokens;
    }

    /**
     * @dev mint token that was redeemed for
     */
    function _mintRedemption(address to) internal virtual returns (uint256) {
        require(_redemptionCount < _redemptionMax, "Redeem: No redemptions remaining");
        _redemptionCount++;
        
        // Mint token
        uint256 tokenId = _mint(to, _redemptionCount);

        _mintedTokens.push(tokenId);
        _mintNumbers[tokenId] = _redemptionCount;
        return tokenId;
    }

    /**
     * @dev override if you want to perform different mint functionality
     */
    function _mint(address to, uint16) internal virtual returns (uint256) {
        return IERC721CreatorCore(_creator).mintExtension(to);
    }

}
