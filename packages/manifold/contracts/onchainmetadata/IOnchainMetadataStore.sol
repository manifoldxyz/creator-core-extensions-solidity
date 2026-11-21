// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../lazyclaim/IERC1155LazyPayableClaimMetadata.sol";
import "../lazyclaim/IERC721LazyPayableClaimMetadata.sol";

/**
 * @notice Stores a claim instance's art on chain and renders a fully on-chain `data:` tokenURI.
 * Data is keyed by (creatorContract, instanceId). Usable as a lazy claim `StorageProtocol.ADDRESS` location.
 */
interface IOnchainMetadataStore is IERC1155LazyPayableClaimMetadata, IERC721LazyPayableClaimMetadata {
    struct File {
        string mimeType;
        address[] chunks;
        uint256 length;
        bool zipped;
        bool deflated;
    }

    struct Token {
        string metadata;
        File image;
        File animation;
        bool wrapped;
    }

    struct Options {
        string metadata;
        File image;
        File animation;
        bool wrapped;
    }

    /// @notice Emitted on every write to the data of (creatorContract, instanceId)
    event TokenDataUpdated(address indexed creatorContract, uint256 indexed instanceId);

    /**
     * @notice Replaces the data of an instance. Image/animation chunks are replaced only if provided.
     * @param options metadata (JSON fragment without braces), file descriptors and wrapped flag
     * @param image image chunks, max 24576 bytes each
     * @param animation animation chunks, max 24576 bytes each
     */
    function setToken(
        address creatorContract,
        uint256 instanceId,
        Options calldata options,
        bytes[] calldata image,
        bytes[] calldata animation
    ) external;

    /// @notice Appends image chunks, max 24576 bytes each
    function appendChunks(address creatorContract, uint256 instanceId, bytes[] calldata chunks) external;

    /// @notice Appends animation chunks, max 24576 bytes each
    function appendAnimationChunks(address creatorContract, uint256 instanceId, bytes[] calldata chunks) external;

    /// @notice Number of stored image and animation chunks
    function chunkCounts(address creatorContract, uint256 instanceId)
        external
        view
        returns (uint256 imageChunks, uint256 animChunks);

    /// @notice Image bytes after chunk concatenation and decompression
    function loadRawImage(address creatorContract, uint256 instanceId) external view returns (bytes memory);

    /// @notice Image as a base64 `data:` URI
    function loadImage(address creatorContract, uint256 instanceId) external view returns (string memory);

    /// @notice Animation as a base64 `data:` URI
    function loadAnimation(address creatorContract, uint256 instanceId) external view returns (string memory);
}
