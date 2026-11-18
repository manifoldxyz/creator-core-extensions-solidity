// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@manifoldxyz/libraries-solidity/contracts/access/IAdminControl.sol";
import "@manifoldxyz/creator-core-solidity/contracts/core/ICreatorCore.sol";
import "@manifoldxyz/creator-core-solidity/contracts/core/IERC721CreatorCore.sol";
import "@manifoldxyz/creator-core-extensions-solidity/contracts/lazyclaim/ILazyPayableClaim.sol";
import "@manifoldxyz/creator-core-extensions-solidity/contracts/lazyclaim/IERC721LazyPayableClaim.sol";
import "@manifoldxyz/creator-core-extensions-solidity/contracts/lazyclaim/IERC721LazyPayableClaimMetadata.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import "./IERC721ClaimParams.sol";

/// @dev Mint fee getters exposed by the lazy claim extensions (constants in v1, storage in V2).
interface ILazyPayableClaimFees {
    function MINT_FEE() external view returns (uint256);
    function MINT_FEE_MERKLE() external view returns (uint256);
}

/**
 * @title ERC721 Claim Params
 * @author manifold.xyz
 * @notice Mints through one ERC721 lazy claim instance and stores per-token params in the same
 * transaction. The claim points its tokenURI here (StorageProtocol.ADDRESS) and this contract
 * renders each token's JSON from the renderer settings and the token's params.
 *
 * Params are keyed by the claim's mint order, which the claim passes to tokenURI. They are set
 * once and never change. No owner, no upgrades, holds no ETH between calls.
 */
contract ERC721ClaimParams is IERC721ClaimParams, IERC721LazyPayableClaimMetadata, ERC165 {
    using Strings for uint256;

    bytes16 private constant _HEX = "0123456789abcdef";

    address public immutable CLAIM;
    address public immutable CREATOR_CONTRACT;
    uint256 public immutable INSTANCE_ID;
    uint16 public immutable PARAMS_LENGTH;

    Renderer public renderer;
    bool public locked;

    mapping(uint24 => bytes) private _params;

    constructor(address claim, address creatorContract, uint256 instanceId, uint16 paramsLength) {
        if (paramsLength == 0) revert InvalidParamsLength();
        CLAIM = claim;
        CREATOR_CONTRACT = creatorContract;
        INSTANCE_ID = instanceId;
        PARAMS_LENGTH = paramsLength;
    }

    modifier creatorAdminRequired() {
        if (!IAdminControl(CREATOR_CONTRACT).isAdmin(msg.sender)) revert NotCreatorAdmin();
        _;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC721ClaimParams).interfaceId
            || interfaceId == type(IERC721LazyPayableClaimMetadata).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * See {IERC721ClaimParams-mint}.
     */
    function mint(bytes calldata params, uint32 mintIndex, bytes32[] calldata merkleProof) external payable override {
        if (params.length != PARAMS_LENGTH) revert InvalidParamsLength();
        IERC721LazyPayableClaim.Claim memory claim =
            IERC721LazyPayableClaim(CLAIM).getClaim(CREATOR_CONTRACT, INSTANCE_ID);
        if (msg.value != _mintPrice(claim)) revert InvalidPayment();

        // The claim increments total before it mints, so this is the mint order of the token below.
        // Params are stored first: a mint re-entering from onERC721Received reads the incremented
        // total and gets the next mint order. A failed claim mint reverts this write.
        // casting to uint24 is safe because the claim reverts any mint past MAX_UINT_24
        // forge-lint: disable-next-line(unsafe-typecast)
        uint24 mintOrder = uint24(claim.total + 1);
        _params[mintOrder] = params;
        emit ParamsSet(mintOrder, params);

        uint32[] memory mintIndices;
        bytes32[][] memory merkleProofs;
        if (claim.merkleRoot != bytes32(0)) {
            mintIndices = new uint32[](1);
            mintIndices[0] = mintIndex;
            merkleProofs = new bytes32[][](1);
            merkleProofs[0] = merkleProof;
        }
        ILazyPayableClaim(CLAIM).mintProxy{value: msg.value}(
            CREATOR_CONTRACT, INSTANCE_ID, 1, mintIndices, merkleProofs, msg.sender
        );
    }

    /**
     * See {IERC721ClaimParams-setParams}.
     */
    function setParams(uint256 tokenId, bytes calldata params) external override {
        if (params.length != PARAMS_LENGTH) revert InvalidParamsLength();
        if (IERC721(CREATOR_CONTRACT).ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        // Other extensions and other claims on the same creator contract mint tokens too
        if (ICreatorCore(CREATOR_CONTRACT).tokenExtension(tokenId) != CLAIM) revert InvalidToken();
        // Claim tokens carry tokenData = instanceId << 24 | mintOrder (56 + 24 bits)
        uint80 tokenData = IERC721CreatorCore(CREATOR_CONTRACT).tokenData(tokenId);
        // forge-lint: disable-next-line(unsafe-typecast)
        if (uint256(uint56(tokenData >> 24)) != INSTANCE_ID) revert InvalidToken();

        // forge-lint: disable-next-line(unsafe-typecast)
        uint24 mintOrder = uint24(tokenData);
        if (_params[mintOrder].length != 0) revert ParamsAlreadySet();
        _params[mintOrder] = params;
        emit ParamsSet(mintOrder, params);
    }

    /**
     * See {IERC721ClaimParams-setRenderer}.
     */
    function setRenderer(Renderer calldata renderer_) external override creatorAdminRequired {
        if (locked) revert RendererIsLocked();
        renderer = renderer_;
        emit RendererUpdated();
    }

    /**
     * See {IERC721ClaimParams-lockRenderer}.
     */
    function lockRenderer() external override creatorAdminRequired {
        locked = true;
        emit RendererLocked();
    }

    /**
     * See {IERC721ClaimParams-mintPrice}.
     */
    function mintPrice() external view override returns (uint256) {
        return _mintPrice(IERC721LazyPayableClaim(CLAIM).getClaim(CREATOR_CONTRACT, INSTANCE_ID));
    }

    /**
     * See {IERC721ClaimParams-getParams}.
     */
    function getParams(uint24 mintOrder) external view override returns (bytes memory) {
        return _params[mintOrder];
    }

    /**
     * See {IERC721LazyPayableClaimMetadata-tokenURI}.
     * Called by the claim. Only mintOrder is used.
     */
    function tokenURI(address, uint256, uint256, uint24 mintOrder) external view override returns (string memory) {
        Renderer memory r = renderer;
        string memory order = uint256(mintOrder).toString();
        bytes memory json = abi.encodePacked(
            '{"name":"',
            r.name,
            " #",
            order,
            '","description":"',
            r.description,
            '","image":"',
            r.imageURI,
            '","animation_url":"',
            r.animationURI,
            "?params=",
            _toHex(_params[mintOrder]),
            "&mintOrder=",
            order,
            '"}'
        );
        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(json)));
    }

    /**
     * @dev mintProxy charges the claim cost plus the full mint fee (no membership waiver).
     */
    function _mintPrice(IERC721LazyPayableClaim.Claim memory claim) private view returns (uint256) {
        uint256 fee = claim.merkleRoot != bytes32(0)
            ? ILazyPayableClaimFees(CLAIM).MINT_FEE_MERKLE()
            : ILazyPayableClaimFees(CLAIM).MINT_FEE();
        return claim.cost + fee;
    }

    /**
     * @dev 0x-prefixed lowercase hex. Empty input returns "0x".
     */
    function _toHex(bytes memory data) private pure returns (string memory) {
        bytes memory out = new bytes(2 + data.length * 2);
        out[0] = "0";
        out[1] = "x";
        for (uint256 i; i < data.length;) {
            out[2 + i * 2] = _HEX[uint8(data[i]) >> 4];
            out[3 + i * 2] = _HEX[uint8(data[i]) & 0x0f];
            unchecked {
                ++i;
            }
        }
        return string(out);
    }
}
