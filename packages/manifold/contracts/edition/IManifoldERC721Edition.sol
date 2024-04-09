// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

/**
 * Manifold ERC721 Edition Controller interface
 */
interface IManifoldERC721Edition {

    error InvalidEdition();
    error InvalidInput();
    error TooManyRequested();
    error InvalidToken();

    event SeriesCreated(address caller, address creatorCore, uint256 series, uint256 maxSupply);

    struct Recipient {
        address recipient;
        uint16 count;
    }

    enum StorageProtocol { INVALID, NONE, ARWEAVE, IPFS }

    struct EditionInfo {
        uint192 firstTokenId;
        uint8 contractVersion;
        uint24 totalSupply;
        uint24 maxSupply;
        StorageProtocol storageProtocol; 
        string location;
    }

    /**
     * @dev Create a new series.  Returns the series id.
     */
    function createSeries(address creatorCore, uint256 instanceId, uint24 maxSupply_, StorageProtocol storageProtocol, string calldata location, Recipient[] memory recipients) external;

    /**
     * @dev Set the token uri prefix
     */
    function setTokenURI(address creatorCore, uint256 instanceId, StorageProtocol storageProtocol, string calldata location) external;
    
    /**
     * @dev Mint NFTs to a single recipient
     */
    function mint(address creatorCore, uint256 instanceId, uint24 currentSupply, Recipient[] memory recipients) external;

    /**
     * @dev Get the EditionInfo for a Series
     */
    function getEditionInfo(address creatorCore, uint256 instanceId) external view returns(EditionInfo memory);

    /**
     * @dev Get the instance ids for a set of token
     */
    function getInstanceIdsForTokens(address creatorCore, uint256[] calldata tokenIds) external view returns(uint256[] memory);

    /**
     * @dev Get all the token ids for an instance
     */
    function getInstanceTokenIds(address creatorCore, uint256 instanceId) external view returns(uint256[] memory);
}
