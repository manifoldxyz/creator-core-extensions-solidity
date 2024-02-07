// SPDX-License-Identifier: MIT
// solhint-disable reason-string
pragma solidity ^0.8.0;

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC1155CreatorCore.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/ICreatorExtensionTokenURI.sol";

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import "./FrameLazyClaim.sol";
import "./IERC1155FrameLazyClaim.sol";

/**
 * @title Frame Lazy Payable Claim
 * @author manifold.xyz
 * @notice Lazy claim ERC1155 tokens
 */
contract ERC1155FrameLazyClaim is IERC165, IERC1155FrameLazyClaim, ICreatorExtensionTokenURI, FrameLazyClaim {
    using Strings for uint256;

    // stores mapping from contractAddress/instanceId to the claim it represents
    // { contractAddress => { instanceId => Claim } }
    mapping(address => mapping(uint256 => Claim)) private _claims;

    // { contractAddress => { tokenId => { instanceId } }
    mapping(address => mapping(uint256 => uint256)) private _claimTokenIds;

    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, AdminControl) returns (bool) {
        return interfaceId == type(IERC1155FrameLazyClaim).interfaceId ||
            interfaceId == type(IFrameLazyClaim).interfaceId ||
            interfaceId == type(ICreatorExtensionTokenURI).interfaceId ||
            interfaceId == type(IAdminControl).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }

    constructor(address initialOwner) FrameLazyClaim(initialOwner) {}

    /**
     * See {IERC1155FrameLazyClaim-initializeClaim}.
     */
    function initializeClaim(
        address creatorContractAddress,
        uint256 instanceId,
        ClaimParameters calldata claimParameters
    ) external payable override creatorAdminRequired(creatorContractAddress) {
        // Revert if claim at instanceId already exists
        require(_claims[creatorContractAddress][instanceId].storageProtocol == StorageProtocol.INVALID, "Claim already initialized");

        // Sanity checks
        require(claimParameters.storageProtocol != StorageProtocol.INVALID, "Cannot initialize with invalid storage protocol");
        require(claimParameters.paymentReceiver == address(0) || claimParameters.sponsoredMints == 0, "Cannot have payment receiver and sponsored mints");

        if (claimParameters.sponsoredMints > MANIFOLD_FREE_MINTS) {
            if (msg.value != (claimParameters.sponsoredMints - MANIFOLD_FREE_MINTS) * SPONSORED_MINT_FEE) revert InsufficientPayment();
        }

        address[] memory receivers = new address[](1);
        receivers[0] = msg.sender;
        string[] memory uris = new string[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory newTokenIds = IERC1155CreatorCore(creatorContractAddress).mintExtensionNew(receivers, amounts, uris);

         // Create the claim
        _claims[creatorContractAddress][instanceId] = Claim({
            storageProtocol: claimParameters.storageProtocol,
            location: claimParameters.location,
            tokenId: newTokenIds[0],
            paymentReceiver: claimParameters.paymentReceiver,
            sponsoredMints: claimParameters.sponsoredMints
        });
        _claimTokenIds[creatorContractAddress][newTokenIds[0]] = instanceId;
        
        if (msg.value > 0) {
            _sendFunds(_fundsReceiver, msg.value);
        }

        emit FrameClaimInitialized(creatorContractAddress, instanceId, msg.sender);
    }

    /**
     * See {IERC1155FrameLazyClaim-updateTokenURIParams}.
     */
    function updateTokenURIParams(
        address creatorContractAddress, uint256 instanceId,
        StorageProtocol storageProtocol,
        string calldata location
    ) external override creatorAdminRequired(creatorContractAddress) {
        Claim storage claim = _claims[creatorContractAddress][instanceId];
        require(claim.storageProtocol != StorageProtocol.INVALID, "Claim not initialized");
        require(storageProtocol != StorageProtocol.INVALID, "Cannot set invalid storage protocol");

        claim.storageProtocol = storageProtocol;
        claim.location = location;
        emit FrameClaimUpdated(creatorContractAddress, instanceId);
    }

    /**
     * See {IERC1155FrameLazyClaim-extendTokenURI}.
     */
    function extendTokenURI(
        address creatorContractAddress, uint256 instanceId,
        string calldata locationChunk
    ) external override creatorAdminRequired(creatorContractAddress) {
        Claim storage claim = _claims[creatorContractAddress][instanceId];
        require(claim.storageProtocol == StorageProtocol.NONE, "Invalid storage protocol");
        claim.location = string(abi.encodePacked(claim.location, locationChunk));
    }

    /**
     * See {IERC1155FrameLazyClaim-getClaim}.
     */
    function getClaim(address creatorContractAddress, uint256 instanceId) public override view returns(Claim memory claim) {
        return _getClaim(creatorContractAddress, instanceId);
    }

    /**
     * See {IERC1155FrameLazyClaim-getClaimForToken}.
     */
    function getClaimForToken(address creatorContractAddress, uint256 tokenId) external override view returns(uint256 instanceId, Claim memory claim) {
        instanceId = _claimTokenIds[creatorContractAddress][tokenId];
        claim = _getClaim(creatorContractAddress, instanceId);
    }

    function _getClaim(address creatorContractAddress, uint256 instanceId) private view returns(Claim storage claim) {
        claim = _claims[creatorContractAddress][instanceId];
        require(claim.storageProtocol != StorageProtocol.INVALID, "Claim not initialized");
    }

    /**
     * See {IFrameLazyClaim-mint}.
     */
    function mint(Mint[] calldata mints) external override payable {
        _validateSigner();
        uint256 paymentReceived = msg.value;
        for (uint256 i; i < mints.length;) {
            Mint calldata mintData = mints[i];
            Claim storage claim = _getClaim(mintData.creatorContractAddress, mintData.instanceId);
            paymentReceived = _mintClaim(mintData, claim, paymentReceived);
            emit FrameClaimMint(mintData.creatorContractAddress, mintData.instanceId);
            unchecked{ ++i; }
        }

    }

    /**
     * See {IFrameLazyClaim-sponsorMints}.
     */
    function sponsorMints(address creatorContractAddress, uint256 instanceId, uint56 amount) external override payable creatorAdminRequired(creatorContractAddress) {
        if (msg.value != amount * SPONSORED_MINT_FEE) revert InsufficientPayment();
        Claim storage claim = _getClaim(creatorContractAddress, instanceId);
        if (claim.sponsoredMints == 0) revert PaymentNotAllowed();
         _sendFunds(_fundsReceiver, msg.value);
        claim.sponsoredMints += amount;
        emit FrameClaimSponsored(msg.sender, creatorContractAddress, instanceId, amount);
    }

    /**
     * Mint a claim
     */
    function _mintClaim(Mint calldata mintData, Claim storage claim, uint256 paymentReceived) private returns(uint256) {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = claim.tokenId;
        address[] memory receivers = new address[](mintData.recipients.length);
        uint256[] memory amounts = new uint256[](mintData.recipients.length);
        uint256 totalPayment;
        for (uint256 i; i < mintData.recipients.length;) {
            receivers[i] = mintData.recipients[i].receiver;
            amounts[i] = mintData.recipients[i].amount;
            totalPayment += mintData.recipients[i].payment;
            unchecked { ++i; }
        }
        if (totalPayment > 0) {
            if (paymentReceived < totalPayment) revert InsufficientPayment();
            paymentReceived -= totalPayment;
        }
        IERC1155CreatorCore(mintData.creatorContractAddress).mintExtensionExisting(receivers, tokenIds, amounts);
        if (totalPayment > 0) {
            _sendFunds(claim.paymentReceiver, totalPayment);
        }
        return paymentReceived;
    }

    /**
     * See {ICreatorExtensionTokenURI-tokenURI}.
     */
    function tokenURI(address creatorContractAddress, uint256 tokenId) external override view returns(string memory uri) {
        uint224 tokenClaim = uint224(_claimTokenIds[creatorContractAddress][tokenId]);
        require(tokenClaim > 0, "Token does not exist");
        Claim memory claim = _claims[creatorContractAddress][tokenClaim];

        string memory prefix = "";
        if (claim.storageProtocol == StorageProtocol.ARWEAVE) {
            prefix = ARWEAVE_PREFIX;
        } else if (claim.storageProtocol == StorageProtocol.IPFS) {
            prefix = IPFS_PREFIX;
        }
        uri = string(abi.encodePacked(prefix, claim.location));
    }
}
