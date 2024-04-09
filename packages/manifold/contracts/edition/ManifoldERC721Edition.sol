// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/libraries-solidity/contracts/access/IAdminControl.sol";
import "@manifoldxyz/creator-core-solidity/contracts/core/IERC721CreatorCore.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/CreatorExtension.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/ICreatorExtensionTokenURI.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "../libraries/IERC721CreatorCoreVersion.sol";
import "./IManifoldERC721Edition.sol";

/**
 * Manifold ERC721 Edition Controller Implementation
 */
contract ManifoldERC721Edition is CreatorExtension, ICreatorExtensionTokenURI, IManifoldERC721Edition, ReentrancyGuard {
    using Strings for uint256;

    struct IndexRange {
        uint256 startIndex;
        uint256 count;
    }

    string private constant ARWEAVE_PREFIX = "https://arweave.net/";
    string private constant IPFS_PREFIX = "ipfs://";

    uint256 private constant MAX_UINT_24 = 0xffffff;
    uint256 private constant MAX_UINT_56 = 0xffffffffffffff;
    uint256 private constant MAX_UINT_192 = 0xffffffffffffffffffffffffffffffffffffffffffffffff;

    mapping(address => mapping(uint256 => EditionInfo)) _editionInfo;
    mapping(address => mapping(uint256 => IndexRange[])) _indexRanges;

    mapping(address => uint256[]) _creatorInstanceIds;

    /**
     * @dev Only allows approved admins to call the specified function
     */
    modifier creatorAdminRequired(address creator) {
        if (!IAdminControl(creator).isAdmin(msg.sender)) revert("Must be owner or admin of creator contract");
        _;
    }
    
    function supportsInterface(bytes4 interfaceId) public view virtual override(CreatorExtension, IERC165) returns (bool) {
        return
            interfaceId == type(ICreatorExtensionTokenURI).interfaceId ||
            interfaceId == type(IManifoldERC721Edition).interfaceId ||
            CreatorExtension.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IManifoldERC721Edition-createSeries}.
     */
    function createSeries(address creatorCore, uint256 instanceId, uint24 maxSupply_, StorageProtocol storageProtocol, string calldata location, Recipient[] memory recipients) external override creatorAdminRequired(creatorCore) {
        if (instanceId == 0 ||
            instanceId > MAX_UINT_56 ||
            maxSupply_ == 0 ||
            storageProtocol == StorageProtocol.INVALID ||
            _editionInfo[creatorCore][instanceId].storageProtocol != StorageProtocol.INVALID
        ) revert InvalidInput();

        uint8 creatorContractVersion;
        try IERC721CreatorCoreVersion(creatorCore).VERSION() returns(uint256 version) {
            require(version <= 255, "Unsupported contract version");
            creatorContractVersion = uint8(version);
        } catch {}

        _editionInfo[creatorCore][instanceId] = EditionInfo({
            maxSupply: maxSupply_,
            totalSupply: 0,
            contractVersion: creatorContractVersion,
            storageProtocol: storageProtocol,
            location: location,
            firstTokenId: 0
        });

        if (creatorContractVersion < 3) {
            _creatorInstanceIds[creatorCore].push(instanceId);
        }
        
        emit SeriesCreated(msg.sender, creatorCore, instanceId, maxSupply_);

        if (recipients.length > 0) _mintTokens(creatorCore, instanceId, _editionInfo[creatorCore][instanceId], recipients);
    }

    /**
     * See {IManifoldERC721Edition-setTokenURI}.
     */
    function setTokenURI(address creatorCore, uint256 instanceId, StorageProtocol storageProtocol, string calldata location) external override creatorAdminRequired(creatorCore) {
        if (storageProtocol == StorageProtocol.INVALID) revert InvalidInput();
        EditionInfo storage info = _getEditionInfo(creatorCore, instanceId);
        info.storageProtocol = storageProtocol;
        info.location = location;
    }

    function _getEditionInfo(address creatorCore, uint256 instanceId) private view returns(EditionInfo storage info) {
        info = _editionInfo[creatorCore][instanceId];
        if (info.storageProtocol == StorageProtocol.INVALID) revert InvalidEdition();
    }

    /**
     * @dev See {IManifoldERC721Edition-getEditionInfo}.
     *
     * This is the public version of the above internal function. Separate function because it returns EditionInfo
     * memory instead of storage.
     */
    function getEditionInfo(address creatorCore, uint256 instanceId) public view returns(EditionInfo memory info) {
        info = _editionInfo[creatorCore][instanceId];
        if (info.storageProtocol == StorageProtocol.INVALID) revert InvalidEdition();
    }

    /**
     * @dev See {IManifoldERC721Edition-getInstanceIdsForTokens}.
     */
    function getInstanceIdsForTokens(address creatorCore, uint256[] calldata tokenIds) external view override returns(uint256[] memory instanceIds) {
        instanceIds = new uint256[](tokenIds.length);
        for (uint256 i; i < tokenIds.length;) {
            uint256 tokenId = tokenIds[i];
            try IERC721CreatorCore(creatorCore).tokenExtension(tokenId) returns(address tokenExtension) {
                if (tokenExtension == address(this)) {
                    uint256 creatorContractVersion;
                    uint256 instanceId;
                    try IERC721CreatorCoreVersion(creatorCore).VERSION() returns(uint256 version) {
                        creatorContractVersion = version;
                    } catch {}
                    if (creatorContractVersion >= 3) {
                        // Contract versions 3+ support storage of data with the token mint, so use that
                        uint80 tokenData = IERC721CreatorCore(creatorCore).tokenData(tokenId);
                        instanceId = uint56(tokenData >> 24);
                    } else {
                        (instanceId, ) = _tokenInstanceAndIndex(creatorCore, tokenId);
                    }
                    instanceIds[i] = instanceId;
                }
            } catch {}
            unchecked{++i;}
        }
    }

    /**
     * @dev See {IManifoldERC721Edition-getInstanceTokenIds}.
     */
    function getInstanceTokenIds(address creatorCore, uint256 instanceId) external view returns(uint256[] memory tokenIds) {
        EditionInfo storage info = _getEditionInfo(creatorCore, instanceId);
        uint256 creatorContractVersion;
        tokenIds = new uint256[](info.totalSupply);
        try IERC721CreatorCoreVersion(creatorCore).VERSION() returns(uint256 version) {
            creatorContractVersion = version;
        } catch {}
        if (creatorContractVersion >= 3) {
            // We do not have index ranges, so seek based on first tokenId
            uint256 tokenId = info.firstTokenId;
            uint256 foundTokens;
            while (foundTokens < info.totalSupply) {
                try IERC721CreatorCore(creatorCore).tokenExtension(tokenId) returns(address tokenExtension) {
                    if (tokenExtension == address(this)) {
                        uint80 tokenData = IERC721CreatorCore(creatorCore).tokenData(tokenId);
                        if (instanceId == uint56(tokenData >> 24)) {
                            tokenIds[foundTokens] = tokenId;
                            unchecked{++foundTokens;}
                        }
                    }
                } catch {}
                unchecked{++tokenId;}
            }
        } else {
            // We have index ranges, so we can just iterate through them
            IndexRange[] memory indexRanges = _indexRanges[creatorCore][instanceId];
            uint256 current;
            for (uint256 i; i < indexRanges.length;) {
                IndexRange memory currentIndex = indexRanges[i];
                for (uint256 j; j < currentIndex.count;) {
                    tokenIds[current] = currentIndex.startIndex + j;
                    unchecked{++current; ++j;}
                }
                unchecked{++i;}
            }
        }
    }

    /**
     * @dev See {ICreatorExtensionTokenURI-tokenURI}.
     */
    function tokenURI(address creatorCore, uint256 tokenId) external view override returns (string memory) {
        uint256 creatorContractVersion;
        try IERC721CreatorCoreVersion(creatorCore).VERSION() returns(uint256 version) {
            creatorContractVersion = version;
        } catch {}

        uint256 instanceId;
        uint256 index;
        if (creatorContractVersion >= 3) {
            // Contract versions 3+ support storage of data with the token mint, so use that
            uint80 tokenData = IERC721CreatorCore(creatorCore).tokenData(tokenId);
            instanceId = uint56(tokenData >> 24);
            if (instanceId == 0) revert InvalidToken();
            index = uint256(tokenData & MAX_UINT_24);
        } else {
            (instanceId, index) = _tokenInstanceAndIndex(creatorCore, tokenId);
        }
        
        EditionInfo storage info = _getEditionInfo(creatorCore, instanceId);

        string memory prefix = "";
        if (info.storageProtocol == StorageProtocol.ARWEAVE) {
            prefix = ARWEAVE_PREFIX;
        } else if (info.storageProtocol == StorageProtocol.IPFS) {
            prefix = IPFS_PREFIX;
        }
        return string(abi.encodePacked(prefix, info.location, "/", (index+1).toString()));
    }
    
    /**
     * @dev See {IManifoldERC721Edition-mint}.
     */
    function mint(address creatorCore, uint256 instanceId, uint24 currentSupply, Recipient[] memory recipients) external override nonReentrant creatorAdminRequired(creatorCore) {        
        EditionInfo storage info = _getEditionInfo(creatorCore, instanceId);
        if (currentSupply != info.totalSupply) revert InvalidInput();
        _mintTokens(creatorCore, instanceId, info, recipients);
    }

    function _mintTokens(address creatorCore, uint256 instanceId, EditionInfo storage info, Recipient[] memory recipients) private {
        if (recipients.length == 0) revert InvalidInput();
        if (info.totalSupply+1 > info.maxSupply) revert TooManyRequested();

        uint256[] memory tokenIdResults;
        if (info.contractVersion >= 3) {
            uint16 count = 0;
            uint24 totalSupply_ = info.totalSupply;
            uint24 maxSupply_ = info.maxSupply;
            uint256 newMintIndex = totalSupply_;
            // Contract versions 3+ support storage of data with the token mint, so use that
            // to avoid additional storage costs
            for (uint256 i; i < recipients.length;) {
                uint16 mintCount = recipients[i].count;
                if (mintCount == 0) revert InvalidInput();
                count += mintCount;
                if (totalSupply_+count > maxSupply_) revert TooManyRequested();
                uint80[] memory tokenDatas = new uint80[](mintCount);
                for (uint256 j; j < mintCount;) {
                    tokenDatas[j] = uint56(instanceId) << 24 | uint24(newMintIndex+j);
                    unchecked {++j;}
                }
                // Airdrop the tokens
                tokenIdResults = IERC721CreatorCore(creatorCore).mintExtensionBatch(recipients[i].recipient, tokenDatas);
                if (i == 0 && info.firstTokenId == 0) {
                    if (tokenIdResults[0] > MAX_UINT_192) revert InvalidInput();
                    info.firstTokenId = uint192(tokenIdResults[0]);
                }
                // Increment newMintIndex for the next airdrop
                unchecked{newMintIndex += mintCount;}

                unchecked{++i;}
            }
            info.totalSupply += count;
        } else {
            uint256 startIndex;
            uint16 count = 0;
            uint24 totalSupply_ = info.totalSupply;
            uint24 maxSupply_ = info.maxSupply;
            for (uint256 i; i < recipients.length;) {
                if (recipients[i].count == 0) revert InvalidInput();
                count += recipients[i].count;
                if (totalSupply_+count > maxSupply_) revert TooManyRequested();
                tokenIdResults = IERC721CreatorCore(creatorCore).mintExtensionBatch(recipients[i].recipient, recipients[i].count);
                if (i == 0) {
                    startIndex = tokenIdResults[0];
                    if (info.firstTokenId == 0) {
                        if (startIndex > MAX_UINT_192) revert InvalidInput();
                        info.firstTokenId = uint192(startIndex);
                    }
                }
                unchecked{++i;}
            }
            _updateIndexRanges(creatorCore, instanceId, info, startIndex, count);
        }
    }

    /**
     * @dev Update the index ranges, which is used to figure out the index from a tokenId
     */
    function _updateIndexRanges(address creatorCore, uint256 instanceId, EditionInfo storage info, uint256 startIndex, uint16 count) internal {
        IndexRange[] storage indexRanges = _indexRanges[creatorCore][instanceId];
        if (indexRanges.length == 0) {
           indexRanges.push(IndexRange(startIndex, count));
        } else {
          IndexRange storage lastIndexRange = indexRanges[indexRanges.length-1];
          if ((lastIndexRange.startIndex + lastIndexRange.count) == startIndex) {
             lastIndexRange.count += count;
          } else {
            indexRanges.push(IndexRange(startIndex, count));
          }
        }
        info.totalSupply += count;
    }

    /**
     * @dev Index from tokenId
     */
    function _tokenInstanceAndIndex(address creatorCore, uint256 tokenId) internal view returns(uint256, uint256) {
        // Go through all their series until we find the tokenId
        for (uint256 i; i < _creatorInstanceIds[creatorCore].length;) {
            uint256 instanceId = _creatorInstanceIds[creatorCore][i];
            IndexRange[] memory indexRanges = _indexRanges[creatorCore][instanceId];
            uint256 offset;
            for (uint j; j < indexRanges.length;) {
                IndexRange memory currentIndex = indexRanges[j];
                if (tokenId < currentIndex.startIndex) break;
                if (tokenId >= currentIndex.startIndex && tokenId < currentIndex.startIndex + currentIndex.count) {
                   return (instanceId, tokenId - currentIndex.startIndex + offset);
                }
                offset += currentIndex.count;
                unchecked{++j;}
            }
            unchecked{++i;}
        }
        revert InvalidToken();
    }

}
