// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC721CreatorCore.sol";

import "./BurnRedeemCore.sol";
import "./BurnRedeemLib.sol";
import "./IERC721BurnRedeem.sol";
import "../libraries/IERC721CreatorCoreVersion.sol";
import { IRedeem } from "./Interfaces.sol";

contract ERC721BurnRedeem is BurnRedeemCore, IERC721BurnRedeem {
    using Strings for uint256;

    // NOTE: Only used for creatorContract versions < 3
    // { contractAddress => { tokenId => { RedeemToken } }
    mapping(address => mapping(uint256 => RedeemToken)) internal _redeemTokens;

    // { creatorContractAddress => { instanceId =>  bool } }
    mapping(address => mapping(uint256 => bool)) private _identicalTokenURI;

    constructor(address initialOwner) BurnRedeemCore(initialOwner) {}

    function supportsInterface(bytes4 interfaceId) public view virtual override(BurnRedeemCore, IERC165) returns (bool) {
        return interfaceId == type(IERC721BurnRedeem).interfaceId || super.supportsInterface(interfaceId);
    }
    
    /**
     * @dev See {IERC721BurnRedeem-initializeBurnRedeem}.
     */
    function initializeBurnRedeem(
        address creatorContractAddress,
        uint256 instanceId,
        BurnRedeemParameters calldata burnRedeemParameters,
        bool identicalTokenURI
    ) external  {
        _validateAdmin(creatorContractAddress);
        // Max uint56 for instanceId
        if (instanceId == 0 || instanceId > MAX_UINT_56) {
            revert InvalidInput();
        }

        uint8 creatorContractVersion;
        try IERC721CreatorCoreVersion(creatorContractAddress).VERSION() returns(uint256 version) {
            if (version > 255) {
                revert UnsupportedContractVersion();
            }
            creatorContractVersion = uint8(version);
        } catch {}
        _initialize(creatorContractAddress, creatorContractVersion, instanceId, burnRedeemParameters);
        _identicalTokenURI[creatorContractAddress][instanceId] = identicalTokenURI;
    }

    /**
     * @dev See {IERC721BurnRedeem-updateBurnRedeem}.
     */
    function updateBurnRedeem(
        address creatorContractAddress,
        uint256 instanceId,
        BurnRedeemParameters calldata burnRedeemParameters,
        bool identicalTokenURI
    ) external {
        _validateAdmin(creatorContractAddress);
        _update(creatorContractAddress, instanceId, burnRedeemParameters);
        _identicalTokenURI[creatorContractAddress][instanceId] = identicalTokenURI;
    }

    /**
     * See {IERC721BurnRedeem-updateTokenURI}.
     */
    function updateTokenURI(
        address creatorContractAddress,
        uint256 instanceId,
        StorageProtocol storageProtocol,
        string calldata location,
        bool identicalTokenURI
    ) external override  {
        _validateAdmin(creatorContractAddress);
        BurnRedeem storage burnRedeemInstance = _getBurnRedeem(creatorContractAddress, instanceId);
        burnRedeemInstance.storageProtocol = storageProtocol;
        burnRedeemInstance.location = location;
        _identicalTokenURI[creatorContractAddress][instanceId] = identicalTokenURI;
        emit BurnRedeemLib.BurnRedeemUpdated(creatorContractAddress, instanceId);
    }

    /** 
     * Helper to mint multiple redeem tokens
     */
    function _redeem(address creatorContractAddress, uint256 instanceId, BurnRedeem storage burnRedeemInstance, address to, uint32 count, bytes memory data) internal override {
        if (burnRedeemInstance.redeemAmount == 1 && count == 1) {
            ++burnRedeemInstance.redeemedCount;
            uint256 newTokenId;
            if (burnRedeemInstance.contractVersion >= 3) {
                uint80 tokenData = uint56(instanceId) << 24 | burnRedeemInstance.redeemedCount;
                newTokenId = IERC721CreatorCore(creatorContractAddress).mintExtension(to, tokenData);
            } else {
                newTokenId = IERC721CreatorCore(creatorContractAddress).mintExtension(to);
                _redeemTokens[creatorContractAddress][newTokenId] = RedeemToken(uint224(instanceId), burnRedeemInstance.redeemedCount);
            }
            emit BurnRedeemLib.BurnRedeemMint(creatorContractAddress, instanceId, newTokenId, 1);
            if (burnRedeemInstance.redeemCallback != address(0)) {
                IRedeem(burnRedeemInstance.redeemCallback).onRedeem(to, creatorContractAddress, newTokenId, 1, data);
            }
        } else {
            uint256 totalCount = burnRedeemInstance.redeemAmount * count;
            if (totalCount > MAX_UINT_16) {
                revert InvalidInput();
            }
            uint256 startingCount = burnRedeemInstance.redeemedCount + 1;
            burnRedeemInstance.redeemedCount += uint32(totalCount);
            if (burnRedeemInstance.contractVersion >= 3) {
                uint80[] memory tokenDatas = new uint80[](totalCount);
                for (uint256 i; i < totalCount;) {
                    tokenDatas[i] = uint56(instanceId) << 24 | uint24(startingCount+i);
                    unchecked { ++i; }
                }
                uint256[] memory newTokenIds = IERC721CreatorCore(creatorContractAddress).mintExtensionBatch(to, tokenDatas);
                for (uint256 i; i < totalCount;) {
                    emit BurnRedeemLib.BurnRedeemMint(creatorContractAddress, instanceId, newTokenIds[i], 1);
                    if (burnRedeemInstance.redeemCallback != address(0)) {
                        IRedeem(burnRedeemInstance.redeemCallback).onRedeem(to, creatorContractAddress, newTokenIds[i], 1, data);
                    }

                    unchecked { i++; }
                }
            } else {
                uint256[] memory newTokenIds = IERC721CreatorCore(creatorContractAddress).mintExtensionBatch(to, uint16(totalCount));
                for (uint256 i; i < totalCount;) {
                    _redeemTokens[creatorContractAddress][newTokenIds[i]] = RedeemToken(uint224(instanceId), uint32(startingCount + i));
                    emit BurnRedeemLib.BurnRedeemMint(creatorContractAddress, instanceId, newTokenIds[i], 1);
                    if (burnRedeemInstance.redeemCallback != address(0)) {
                        IRedeem(burnRedeemInstance.redeemCallback).onRedeem(to, creatorContractAddress, newTokenIds[i], 1, data);
                    }

                    unchecked { i++; }
                }
            }
        }
    }

    /**
     * See {ICreatorExtensionTokenURI-tokenURI}.
     */
    function tokenURI(address creatorContractAddress, uint256 tokenId) external override view returns(string memory uri) {
        (uint256 instanceId, uint256 mintNumber) = _getInstanceIdAndMintNumber(creatorContractAddress, tokenId);
        BurnRedeem memory burnRedeem = _burnRedeems[creatorContractAddress][instanceId];

        string memory prefix = "";
        if (burnRedeem.storageProtocol == StorageProtocol.ARWEAVE) {
            prefix = ARWEAVE_PREFIX;
        } else if (burnRedeem.storageProtocol == StorageProtocol.IPFS) {
            prefix = IPFS_PREFIX;
        }
        uri = string(abi.encodePacked(prefix, burnRedeem.location));

        if (!_identicalTokenURI[creatorContractAddress][instanceId]) {
            uri = string(abi.encodePacked(uri, "/", uint256(mintNumber).toString()));
        }
    }

    /**
     * See {IBurnRedeemCore-getBurnRedeemForToken}.
     */
    function getBurnRedeemForToken(address creatorContractAddress, uint256 tokenId) external override view returns(uint256 instanceId, BurnRedeem memory burnRedeem) {
        (instanceId, ) = _getInstanceIdAndMintNumber(creatorContractAddress, tokenId);
        burnRedeem = _burnRedeems[creatorContractAddress][instanceId];
    }

    function _getInstanceIdAndMintNumber(address creatorContractAddress, uint256 tokenId) internal view returns(uint256 instanceId, uint256 mintNumber) {
        RedeemToken memory token = _redeemTokens[creatorContractAddress][tokenId];
        if (token.instanceId == 0) {
            // No claim, try to retrieve from tokenData
            uint80 tokenData = IERC721CreatorCore(creatorContractAddress).tokenData(tokenId);
            instanceId = uint56(tokenData >> 24);
            if (instanceId == 0) {
                revert InvalidToken(tokenId);
            }
            mintNumber = uint24(tokenData & MAX_UINT_24);
        } else {
            instanceId = token.instanceId;
            mintNumber = token.mintNumber;
        }
    }
}
