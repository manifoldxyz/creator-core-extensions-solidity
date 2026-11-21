// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@manifoldxyz/libraries-solidity/contracts/access/IAdminControl.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import "../libraries/onchain/SSTORE2.sol";
import "../libraries/onchain/LibZip.sol";
import "../libraries/onchain/Base64.sol";
import "../libraries/onchain/InflateLib.sol";

import "../lazyclaim/IERC1155LazyPayableClaimMetadata.sol";
import "../lazyclaim/IERC721LazyPayableClaimMetadata.sol";
import "./IOnchainMetadataStore.sol";

/**
 * @title OnchainMetadataStore
 * @notice Metadata-only store for fully on-chain claim art. Never mints, holds no ETH, no owner, not upgradeable.
 */
contract OnchainMetadataStore is IOnchainMetadataStore, IERC165 {
    /// @dev SSTORE2 pointers prefix the data with one STOP byte.
    uint256 private constant SSTORE2_DATA_OFFSET = 1;

    /**
     * @notice The token data for a given creator contract & claim instance id.
     */
    mapping(address => mapping(uint256 => Token)) public tokenData;

    /**
     * @notice Requires msg.sender to be an admin of the creator contract.
     */
    modifier creatorAdminRequired(address creatorContract) {
        require(IAdminControl(creatorContract).isAdmin(msg.sender), "Wallet is not an administrator for contract");
        _;
    }

    /**
     * @dev safe sets the token metadata, only overwriting string params if they exist
     */
    function _setTokenData(address creatorContract, uint256 instanceId, Options calldata options) internal {
        if (bytes(options.metadata).length > 0) {
            tokenData[creatorContract][instanceId].metadata = options.metadata;
        }
        if (bytes(options.image.mimeType).length > 0) {
            tokenData[creatorContract][instanceId].image.mimeType = options.image.mimeType;
        }
        if (bytes(options.animation.mimeType).length > 0) {
            tokenData[creatorContract][instanceId].animation.mimeType = options.animation.mimeType;
        }

        tokenData[creatorContract][instanceId].image.length = options.image.length;
        tokenData[creatorContract][instanceId].animation.length = options.animation.length;

        tokenData[creatorContract][instanceId].image.zipped = options.image.zipped;
        tokenData[creatorContract][instanceId].image.deflated = options.image.deflated;
        tokenData[creatorContract][instanceId].animation.zipped = options.animation.zipped;
        tokenData[creatorContract][instanceId].animation.deflated = options.animation.deflated;
        tokenData[creatorContract][instanceId].wrapped = options.wrapped;
    }

    /**
     * @dev sets (technically appends) to the image the chunks provided
     */
    function _setImage(address creatorContract, uint256 instanceId, bytes[] calldata image) internal {
        // loop through the image array, appending a new byte array
        // to the chunks. This is because the contract storage limit
        // is 24576 but we actually get much further than that before
        // running out of gas in the block.
        for (uint8 i = 0; i < image.length; i++) {
            tokenData[creatorContract][instanceId].image.chunks.push(SSTORE2.write(image[i]));
        }
    }

    /**
     * @dev sets (technically appends) to the animation the chunks provided
     */
    function _setAnimation(address creatorContract, uint256 instanceId, bytes[] calldata animation) internal {
        // same thing for animation as the image
        for (uint8 i = 0; i < animation.length; i++) {
            tokenData[creatorContract][instanceId].animation.chunks.push(SSTORE2.write(animation[i]));
        }
    }

    /**
     * @inheritdoc IOnchainMetadataStore
     */
    function setToken(
        address creatorContract,
        uint256 instanceId,
        Options calldata options,
        bytes[] calldata image,
        bytes[] calldata animation
    ) external override creatorAdminRequired(creatorContract) {
        _setTokenData(creatorContract, instanceId, options);

        if (image.length > 0) {
            delete tokenData[creatorContract][instanceId].image.chunks;
            _setImage(creatorContract, instanceId, image);
        }

        if (animation.length > 0) {
            delete tokenData[creatorContract][instanceId].animation.chunks;
            _setAnimation(creatorContract, instanceId, animation);
        }

        emit TokenDataUpdated(creatorContract, instanceId);
    }

    /**
     * @inheritdoc IOnchainMetadataStore
     */
    function appendChunks(address creatorContract, uint256 instanceId, bytes[] calldata chunks)
        external
        override
        creatorAdminRequired(creatorContract)
    {
        _setImage(creatorContract, instanceId, chunks);
        emit TokenDataUpdated(creatorContract, instanceId);
    }

    /**
     * @inheritdoc IOnchainMetadataStore
     */
    function appendAnimationChunks(address creatorContract, uint256 instanceId, bytes[] calldata chunks)
        external
        override
        creatorAdminRequired(creatorContract)
    {
        _setAnimation(creatorContract, instanceId, chunks);
        emit TokenDataUpdated(creatorContract, instanceId);
    }

    /**
     * @inheritdoc IOnchainMetadataStore
     */
    function chunkCounts(address creatorContract, uint256 instanceId)
        external
        view
        override
        returns (uint256 imageChunks, uint256 animChunks)
    {
        imageChunks = tokenData[creatorContract][instanceId].image.chunks.length;
        animChunks = tokenData[creatorContract][instanceId].animation.chunks.length;
    }

    /**
     * @inheritdoc IOnchainMetadataStore
     */
    function loadRawImage(address creatorContract, uint256 instanceId) public view override returns (bytes memory) {
        bytes memory data = _readChunks(tokenData[creatorContract][instanceId].image.chunks);

        if (tokenData[creatorContract][instanceId].image.zipped) {
            data = LibZip.flzDecompress(data);
        } else if (tokenData[creatorContract][instanceId].image.deflated) {
            data = InflateLib.puff(data, tokenData[creatorContract][instanceId].image.length);
        }

        return data;
    }

    /**
     * @inheritdoc IOnchainMetadataStore
     */
    function loadImage(address creatorContract, uint256 instanceId) public view override returns (string memory) {
        string memory image =
            string(abi.encodePacked("data:", tokenData[creatorContract][instanceId].image.mimeType, ";base64,"));

        bytes memory data = loadRawImage(creatorContract, instanceId);

        image = string(abi.encodePacked(image, Base64.encode(data)));

        return image;
    }

    /**
     * @inheritdoc IOnchainMetadataStore
     */
    function loadAnimation(address creatorContract, uint256 instanceId) public view override returns (string memory) {
        string memory animation =
            string(abi.encodePacked("data:", tokenData[creatorContract][instanceId].animation.mimeType, ";base64,"));

        bytes memory data = _readChunks(tokenData[creatorContract][instanceId].animation.chunks);

        if (tokenData[creatorContract][instanceId].animation.zipped) {
            data = LibZip.flzDecompress(data);
        } else if (tokenData[creatorContract][instanceId].animation.deflated) {
            data = InflateLib.puff(data, tokenData[creatorContract][instanceId].animation.length);
        }

        animation = string(abi.encodePacked(animation, Base64.encode(data)));

        return animation;
    }

    /**
     * @dev Concatenates SSTORE2 chunks into one buffer, allocated once. Same bytes as appending each
     * `SSTORE2.read(chunk)` in order, without re-copying the growing buffer per chunk.
     */
    function _readChunks(address[] storage chunks) private view returns (bytes memory data) {
        uint256 count = chunks.length;
        uint256 total;
        for (uint256 i = 0; i < count; i++) {
            total += chunks[i].code.length - SSTORE2_DATA_OFFSET;
        }
        data = new bytes(total);
        uint256 offset;
        for (uint256 i = 0; i < count; i++) {
            address pointer = chunks[i];
            uint256 size = pointer.code.length - SSTORE2_DATA_OFFSET;
            assembly {
                extcodecopy(pointer, add(add(data, 0x20), offset), SSTORE2_DATA_OFFSET, size)
            }
            offset += size;
        }
    }

    /**
     * @inheritdoc IERC1155LazyPayableClaimMetadata
     */
    function tokenURI(address creatorContract, uint256, uint256 instanceId)
        external
        view
        override(IERC1155LazyPayableClaimMetadata)
        returns (string memory)
    {
        return _tokenURI(creatorContract, instanceId);
    }

    /**
     * @inheritdoc IERC721LazyPayableClaimMetadata
     */
    function tokenURI(address creatorContract, uint256, uint256 instanceId, uint24)
        external
        view
        override(IERC721LazyPayableClaimMetadata)
        returns (string memory)
    {
        return _tokenURI(creatorContract, instanceId);
    }

    function _tokenURI(address creatorContract, uint256 instanceId) internal view returns (string memory) {
        Token storage t = tokenData[creatorContract][instanceId];
        require(t.image.chunks.length != 0, "Token metadata doesn't exist here");

        // Built in as few copies as possible (memory cost is quadratic in size); output is byte-identical
        // to appending image, animation_url and the closing brace step by step.
        bytes memory raw = loadRawImage(creatorContract, instanceId);
        bytes memory head = abi.encodePacked(
            "data:application/json;utf8,{", t.metadata, ', "image": "data:', t.image.mimeType, ";base64,"
        );

        if (t.animation.chunks.length > 0) {
            return string(
                abi.encodePacked(
                    head,
                    Base64.encode(raw),
                    '","animation_url": "',
                    loadAnimation(creatorContract, instanceId),
                    '"}'
                )
            );
        } else if (t.wrapped) {
            return string(
                abi.encodePacked(
                    head,
                    Base64.encode(raw),
                    '","animation_url": "data:text/html;base64,',
                    Base64.encode(
                        abi.encodePacked(
                            "<!DOCTYPE HTML>\n\n", "<html>\n", "<body>\n", raw, "</body>\n", "</html>\n"
                        )
                    ),
                    '"}'
                )
            );
        }
        return string(abi.encodePacked(head, Base64.encode(raw), '"}'));
    }

    /**
     * @inheritdoc IERC165
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC165).interfaceId
            || interfaceId == type(IERC1155LazyPayableClaimMetadata).interfaceId
            || interfaceId == type(IERC721LazyPayableClaimMetadata).interfaceId;
    }
}
