// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @author manifold.xyz
 * @notice Serves an ERC721 lazy claim's tokenURI (StorageProtocol.ADDRESS). Every token shows a static
 * cover until a creator contract admin reveals a secret whose SHA-256 was fixed at deploy. From then on
 * each token's animation_url carries a key and a hash derived from that secret and the token's mint order.
 */
interface IERC721ClaimSecretReveal {
    error InvalidSupply();
    error NotCreatorAdmin();
    error AlreadyRevealed();
    error InvalidSecret();
    error NotRevealed();

    /**
     * @notice Token metadata settings, fixed at deploy.
     * @param name          token name prefix, rendered as "<name> #<mintOrder>"
     * @param description   token description
     * @param imageURI      static cover image, the same for every token
     * @param animationURI  renderer URI; after the reveal, "?payload=<base64 JSON>" is appended
     */
    struct Renderer {
        string name;
        string description;
        string imageURI;
        string animationURI;
    }

    event Revealed(bytes32 secret);

    /**
     * @notice Publish the secret. Creator contract admin only, once. sha256(secret) must equal COMMIT.
     */
    function reveal(bytes32 secret) external;

    /**
     * @notice HMAC-SHA256(secret, keyPrefix + decimal(edition)). Reverts before the reveal.
     */
    function editionKey(uint256 edition) external view returns (bytes32);

    /**
     * @notice keccak256(abi.encodePacked(secret, edition)). Reverts before the reveal.
     */
    function editionHash(uint256 edition) external view returns (bytes32);
}
