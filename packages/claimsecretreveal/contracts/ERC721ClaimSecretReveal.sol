// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@manifoldxyz/libraries-solidity/contracts/access/IAdminControl.sol";
import "@manifoldxyz/creator-core-extensions-solidity/contracts/lazyclaim/IERC721LazyPayableClaimMetadata.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import "./IERC721ClaimSecretReveal.sol";

/**
 * @title ERC721 Claim Secret Reveal
 * @author manifold.xyz
 * @notice tokenURI source for ERC721 lazy claims (StorageProtocol.ADDRESS). Until the reveal, every
 * token renders the same cover image and no animation_url. A creator contract admin then reveals
 * the secret committed at deploy (sha256(secret) == COMMIT), and each token's animation_url becomes
 * "<animationURI>?payload=<base64 JSON>" with
 *   hash          = keccak256(abi.encodePacked(secret, mintOrder))
 *   editionNumber = mintOrder
 *   key           = HMAC-SHA256(secret, keyPrefix + decimal(mintOrder))
 * for mint orders 1 to SUPPLY. Nothing is written per token. No owner, no upgrades, holds no ETH.
 */
contract ERC721ClaimSecretReveal is IERC721ClaimSecretReveal, IERC721LazyPayableClaimMetadata, ERC165 {
    using Strings for uint256;

    bytes16 private constant _HEX = "0123456789abcdef";
    bytes32 private constant _IPAD = 0x3636363636363636363636363636363636363636363636363636363636363636;
    bytes32 private constant _OPAD = 0x5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c;

    address public immutable CREATOR_CONTRACT;
    bytes32 public immutable COMMIT;
    uint24 public immutable SUPPLY;

    Renderer public renderer;
    string public keyPrefix;
    bool public revealed;
    bytes32 public secret;

    constructor(
        address creatorContract,
        bytes32 commit,
        uint24 supply,
        string memory keyPrefix_,
        Renderer memory renderer_
    ) {
        if (supply == 0) revert InvalidSupply();
        CREATOR_CONTRACT = creatorContract;
        COMMIT = commit;
        SUPPLY = supply;
        keyPrefix = keyPrefix_;
        renderer = renderer_;
    }

    modifier creatorAdminRequired() {
        if (!IAdminControl(CREATOR_CONTRACT).isAdmin(msg.sender)) revert NotCreatorAdmin();
        _;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC721ClaimSecretReveal).interfaceId
            || interfaceId == type(IERC721LazyPayableClaimMetadata).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * See {IERC721ClaimSecretReveal-reveal}.
     */
    function reveal(bytes32 secret_) external override creatorAdminRequired {
        if (revealed) revert AlreadyRevealed();
        if (sha256(abi.encodePacked(secret_)) != COMMIT) revert InvalidSecret();
        secret = secret_;
        revealed = true;
        emit Revealed(secret_);
    }

    /**
     * See {IERC721ClaimSecretReveal-editionKey}.
     */
    function editionKey(uint256 edition) public view override returns (bytes32) {
        if (!revealed) revert NotRevealed();
        return _hmacSha256(secret, abi.encodePacked(keyPrefix, edition.toString()));
    }

    /**
     * See {IERC721ClaimSecretReveal-editionHash}.
     */
    function editionHash(uint256 edition) public view override returns (bytes32) {
        if (!revealed) revert NotRevealed();
        return keccak256(abi.encodePacked(secret, edition));
    }

    /**
     * See {IERC721LazyPayableClaimMetadata-tokenURI}.
     * Called by the claim. Only mintOrder is used.
     */
    function tokenURI(address, uint256, uint256, uint24 mintOrder) external view override returns (string memory) {
        Renderer memory r = renderer;
        string memory order = uint256(mintOrder).toString();
        bytes memory json = abi.encodePacked(
            '{"name":"', r.name, " #", order, '","description":"', r.description, '","image":"', r.imageURI, '"'
        );
        // mint orders past SUPPLY have no edition, so they keep the cover
        if (revealed && mintOrder != 0 && mintOrder <= SUPPLY) {
            json = abi.encodePacked(
                json, ',"animation_url":"', r.animationURI, "?payload=", _payload(mintOrder, order), '"'
            );
        }
        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(abi.encodePacked(json, "}"))));
    }

    /**
     * @dev base64 of {"hash":"0x<64 hex>","editionNumber":<n>,"key":"<64 hex>"}. That JSON is ASCII
     * without '>', '?' or '~', so its base64 never contains '+' or '/' and is safe in a query string.
     */
    function _payload(uint24 mintOrder, string memory order) private view returns (string memory) {
        return Base64.encode(
            abi.encodePacked(
                '{"hash":"0x',
                _toHex(editionHash(mintOrder)),
                '","editionNumber":',
                order,
                ',"key":"',
                _toHex(editionKey(mintOrder)),
                '"}'
            )
        );
    }

    /**
     * @dev HMAC-SHA256 (RFC 2104) with a 32-byte key. The 64-byte key block is the key followed by 32 zero
     * bytes, so its XOR with ipad/opad is (key ^ pad, pad).
     */
    function _hmacSha256(bytes32 key, bytes memory message) private pure returns (bytes32) {
        bytes32 inner = sha256(abi.encodePacked(key ^ _IPAD, _IPAD, message));
        return sha256(abi.encodePacked(key ^ _OPAD, _OPAD, inner));
    }

    /**
     * @dev 64 lowercase hex characters, no prefix.
     */
    function _toHex(bytes32 data) private pure returns (bytes memory out) {
        out = new bytes(64);
        for (uint256 i; i < 32;) {
            out[i * 2] = _HEX[uint8(data[i]) >> 4];
            out[i * 2 + 1] = _HEX[uint8(data[i]) & 0x0f];
            unchecked {
                ++i;
            }
        }
    }
}
