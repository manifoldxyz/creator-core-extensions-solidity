// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @author manifold.xyz
 * @notice Mints one token through an ERC721 lazy claim and stores fixed-length params for it in the
 * same transaction. Also serves the claim's tokenURI (StorageProtocol.ADDRESS) from those params.
 * One deployment serves one claim instance.
 */
interface IERC721ClaimParams {
    error InvalidParamsLength();
    error InvalidPayment();
    error NotCreatorAdmin();
    error RendererIsLocked();
    error NotTokenOwner();
    error InvalidToken();
    error ParamsAlreadySet();

    /**
     * @notice Token metadata settings, editable by a creator contract admin until locked.
     * @param name          token name prefix, rendered as "<name> #<mintOrder>"
     * @param description   token description
     * @param imageURI      static preview image, the same for every token
     * @param animationURI  renderer URI; params and mintOrder are appended as a query string
     */
    struct Renderer {
        string name;
        string description;
        string imageURI;
        string animationURI;
    }

    event RendererUpdated();
    event RendererLocked();
    event ParamsSet(uint24 indexed mintOrder, bytes params);

    /**
     * @notice Mint one token to the caller and store its params.
     * @param params        exactly PARAMS_LENGTH bytes
     * @param mintIndex     allowlist index, ignored when the claim has no merkle root
     * @param merkleProof   allowlist proof for (msg.sender, mintIndex), ignored when the claim has no merkle root
     * msg.value must equal mintPrice().
     */
    function mint(bytes calldata params, uint32 mintIndex, bytes32[] calldata merkleProof) external payable;

    /**
     * @notice Set params once on a token of this claim that has none (minted directly on the claim or airdropped).
     * Only the token owner can call it.
     */
    function setParams(uint256 tokenId, bytes calldata params) external;

    /**
     * @notice Replace the renderer settings. Creator contract admin only, until lockRenderer is called.
     */
    function setRenderer(Renderer calldata renderer_) external;

    /**
     * @notice Permanently freeze the renderer settings. Creator contract admin only.
     */
    function lockRenderer() external;

    /**
     * @notice Exact msg.value for mint: the claim cost plus the claim's current mint fee.
     */
    function mintPrice() external view returns (uint256);

    /**
     * @notice Params stored for a mint order, empty if none.
     */
    function getParams(uint24 mintOrder) external view returns (bytes memory);
}
