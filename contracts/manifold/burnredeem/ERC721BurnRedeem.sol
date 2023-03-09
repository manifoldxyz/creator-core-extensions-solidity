// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC721CreatorCore.sol";

import "./BurnRedeemCore.sol";
import "./IERC721BurnRedeem.sol";

contract ERC721BurnRedeem is BurnRedeemCore, IERC721BurnRedeem {
    using Strings for uint256;

    // { contractAddress => { tokenId => { redeemIndex } }
    mapping(address => mapping(uint256 => RedeemToken)) internal _redeemTokens;

    // { creatorContractAddress => { index =>  bool } }
    mapping(address => mapping(uint256 => bool)) private _identicalTokenURI;

    function supportsInterface(bytes4 interfaceId) public view virtual override(BurnRedeemCore, IERC165) returns (bool) {
        return interfaceId == type(IERC721BurnRedeem).interfaceId || super.supportsInterface(interfaceId);
    }
    
    /**
     * @dev See {IERC721BurnRedeem-initializeBurnRedeem}.
     */
    function initializeBurnRedeem(
        address creatorContractAddress,
        uint256 index,
        BurnRedeemParameters calldata burnRedeemParameters,
        bool identicalTokenURI
    ) external creatorAdminRequired(creatorContractAddress) {
        _initialize(creatorContractAddress, index, burnRedeemParameters);
        _identicalTokenURI[creatorContractAddress][index] = identicalTokenURI;
    }

    /**
     * @dev See {IERC721BurnRedeem-updateBurnRedeem}.
     */
    function updateBurnRedeem(
        address creatorContractAddress,
        uint256 index,
        BurnRedeemParameters calldata burnRedeemParameters,
        bool identicalTokenURI
    ) external creatorAdminRequired(creatorContractAddress) {
        _update(creatorContractAddress, index, burnRedeemParameters);
        _identicalTokenURI[creatorContractAddress][index] = identicalTokenURI;
    }

    /**
     * See {IERC721BurnRedeem-updateTokenURI}.
     */
    function updateTokenURI(
        address creatorContractAddress,
        uint256 index,
        StorageProtocol storageProtocol,
        string calldata location,
        bool identicalTokenURI
    ) external override creatorAdminRequired(creatorContractAddress) {
        BurnRedeem storage burnRedeemInstance = _getBurnRedeem(creatorContractAddress, index);
        burnRedeemInstance.storageProtocol = storageProtocol;
        burnRedeemInstance.location = location;
        _identicalTokenURI[creatorContractAddress][index] = identicalTokenURI;
        emit BurnRedeemUpdated(creatorContractAddress, index);
    }

    /** 
     * Helper to mint multiple redeem tokens
     */
    function _redeem(address creatorContractAddress, uint256 index, BurnRedeem storage burnRedeemInstance, address to, uint32 count) internal override {
        if (burnRedeemInstance.redeemAmount == 1 && count == 1) {
            ++burnRedeemInstance.redeemedCount;
            uint256 newTokenId = IERC721CreatorCore(creatorContractAddress).mintExtension(to);
            _redeemTokens[creatorContractAddress][newTokenId] = RedeemToken(uint224(index), burnRedeemInstance.redeemedCount);
            emit BurnRedeemMint(creatorContractAddress, index, newTokenId, 1);
        } else {
            uint256 totalCount = burnRedeemInstance.redeemAmount * count;
            require(totalCount <= MAX_UINT_16, "Invalid input");
            uint256 startingCount = burnRedeemInstance.redeemedCount + 1;
            burnRedeemInstance.redeemedCount += uint32(totalCount);
            uint256[] memory newTokenIds = IERC721CreatorCore(creatorContractAddress).mintExtensionBatch(to, uint16(totalCount));
            for (uint256 i; i < totalCount;) {
                _redeemTokens[creatorContractAddress][newTokenIds[i]] = RedeemToken(uint224(index), uint32(startingCount + i));
                emit BurnRedeemMint(creatorContractAddress, index, newTokenIds[i], 1);
                unchecked { i++; }
            }
        }
    }

    /**
     * See {ICreatorExtensionTokenURI-tokenURI}.
     */
    function tokenURI(address creatorContractAddress, uint256 tokenId) external override view returns(string memory uri) {
        RedeemToken memory token = _redeemTokens[creatorContractAddress][tokenId];
        require(token.burnRedeemIndex > 0, "Token does not exist");
        BurnRedeem memory _burnRedeem = _burnRedeems[creatorContractAddress][token.burnRedeemIndex];

        string memory prefix = "";
        if (_burnRedeem.storageProtocol == StorageProtocol.ARWEAVE) {
            prefix = ARWEAVE_PREFIX;
        } else if (_burnRedeem.storageProtocol == StorageProtocol.IPFS) {
            prefix = IPFS_PREFIX;
        }
        uri = string(abi.encodePacked(prefix, _burnRedeem.location));

        if (!_identicalTokenURI[creatorContractAddress][token.burnRedeemIndex]) {
            uri = string(abi.encodePacked(uri, "/", uint256(token.mintNumber).toString()));
        }
    }
}
