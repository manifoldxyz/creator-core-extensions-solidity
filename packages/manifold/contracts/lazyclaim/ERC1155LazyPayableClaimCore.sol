// SPDX-License-Identifier: MIT
// solhint-disable reason-string
pragma solidity ^0.8.0;

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC1155CreatorCore.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/ICreatorExtensionTokenURI.sol";

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import "./LazyPayableClaimCore.sol";
import "./IERC1155LazyPayableClaim.sol";
import "./IERC1155LazyPayableClaimMetadata.sol";

/**
 * @title Lazy Payable Claim (Core)
 * @author manifold.xyz
 * @notice Lazy claim with optional whitelist ERC1155 tokens
 */
abstract contract ERC1155LazyPayableClaimCore is
    IERC165,
    IERC1155LazyPayableClaim,
    ICreatorExtensionTokenURI,
    LazyPayableClaimCore
{
    using Strings for uint256;

    // stores mapping from contractAddress/instanceId to the claim it represents
    // { contractAddress => { instanceId => Claim } }
    mapping(address => mapping(uint256 => Claim)) private _claims;

    // { contractAddress => { tokenId => { instanceId } }
    mapping(address => mapping(uint256 => uint256)) private _claimTokenIds;

    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, AdminControl) returns (bool) {
        return interfaceId == type(IERC1155LazyPayableClaim).interfaceId
            || interfaceId == type(ILazyPayableClaimCore).interfaceId
            || interfaceId == type(ICreatorExtensionTokenURI).interfaceId || interfaceId == type(IAdminControl).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }

    /**
     * See {IERC1155LazyClaim-initializeClaim}.
     */
    function initializeClaim(
        address creatorContractAddress,
        uint256 instanceId,
        ClaimParameters calldata claimParameters
    ) public virtual override creatorAdminRequired(creatorContractAddress) {
        // Revert if claim at instanceId already exists
        require(
            _claims[creatorContractAddress][instanceId].storageProtocol == StorageProtocol.INVALID,
            "Claim already initialized"
        );

        // Sanity checks
        if (claimParameters.storageProtocol == StorageProtocol.INVALID) {
            revert ILazyPayableClaimCore.InvalidStorageProtocol();
        }
        if (claimParameters.storageProtocol == StorageProtocol.ADDRESS && bytes(claimParameters.location).length != 20)
        {
            revert ILazyPayableClaimCore.InvalidStorageProtocol();
        }
        if (claimParameters.endDate != 0 && claimParameters.startDate >= claimParameters.endDate) {
            revert ILazyPayableClaimCore.InvalidStartDate();
        }
        require(
            claimParameters.merkleRoot == "" || claimParameters.walletMax == 0,
            "Cannot provide both walletMax and merkleRoot"
        );

        address[] memory receivers = new address[](1);
        receivers[0] = msg.sender;
        string[] memory uris = new string[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory newTokenIds =
            IERC1155CreatorCore(creatorContractAddress).mintExtensionNew(receivers, amounts, uris);

        // Create the claim
        _claims[creatorContractAddress][instanceId] = Claim({
            total: 0,
            totalMax: claimParameters.totalMax,
            walletMax: claimParameters.walletMax,
            startDate: claimParameters.startDate,
            endDate: claimParameters.endDate,
            storageProtocol: claimParameters.storageProtocol,
            merkleRoot: claimParameters.merkleRoot,
            location: claimParameters.location,
            tokenId: newTokenIds[0],
            cost: claimParameters.cost,
            paymentReceiver: claimParameters.paymentReceiver,
            erc20: claimParameters.erc20,
            signingAddress: claimParameters.signingAddress
        });
        _claimTokenIds[creatorContractAddress][newTokenIds[0]] = instanceId;

        emit ClaimInitialized(creatorContractAddress, instanceId, msg.sender);
    }

    /**
     * See {IERC1155LazyClaim-updateClaim}.
     */
    function updateClaim(address creatorContractAddress, uint256 instanceId, ClaimParameters memory claimParameters)
        external
        override
        creatorAdminRequired(creatorContractAddress)
    {
        Claim memory claim = _getClaim(creatorContractAddress, instanceId);
        if (claimParameters.storageProtocol == StorageProtocol.INVALID) {
            revert ILazyPayableClaimCore.InvalidStorageProtocol();
        }
        if (claimParameters.storageProtocol == StorageProtocol.ADDRESS && bytes(claimParameters.location).length != 20)
        {
            revert ILazyPayableClaimCore.InvalidStorageProtocol();
        }
        if (claimParameters.endDate != 0 && claimParameters.startDate >= claimParameters.endDate) {
            revert ILazyPayableClaimCore.InvalidStartDate();
        }
        if (claimParameters.erc20 != claim.erc20) revert ILazyPayableClaimCore.CannotChangePaymentToken();
        if (claimParameters.totalMax != 0 && claim.total > claimParameters.totalMax) {
            claimParameters.totalMax = claim.total;
        }

        // Overwrite the existing claim
        _claims[creatorContractAddress][instanceId] = Claim({
            total: claim.total,
            totalMax: claimParameters.totalMax,
            walletMax: claimParameters.walletMax,
            startDate: claimParameters.startDate,
            endDate: claimParameters.endDate,
            storageProtocol: claimParameters.storageProtocol,
            merkleRoot: claimParameters.merkleRoot,
            location: claimParameters.location,
            tokenId: claim.tokenId,
            cost: claimParameters.cost,
            paymentReceiver: claimParameters.paymentReceiver,
            erc20: claimParameters.erc20,
            signingAddress: claimParameters.signingAddress
        });
        emit ClaimUpdated(creatorContractAddress, instanceId);
    }

    /**
     * See {IERC1155LazyClaim-updateTokenURIParams}.
     */
    function updateTokenURIParams(
        address creatorContractAddress,
        uint256 instanceId,
        StorageProtocol storageProtocol,
        string calldata location
    ) external override creatorAdminRequired(creatorContractAddress) {
        Claim storage claim = _getClaim(creatorContractAddress, instanceId);
        if (storageProtocol == StorageProtocol.INVALID) revert ILazyPayableClaimCore.InvalidStorageProtocol();
        if (storageProtocol == StorageProtocol.ADDRESS && bytes(location).length != 20) {
            revert ILazyPayableClaimCore.InvalidStorageProtocol();
        }

        claim.storageProtocol = storageProtocol;
        claim.location = location;
        emit ClaimUpdated(creatorContractAddress, instanceId);
    }

    /**
     * See {IERC1155LazyClaim-extendTokenURI}.
     */
    function extendTokenURI(address creatorContractAddress, uint256 instanceId, string calldata locationChunk)
        external
        override
        creatorAdminRequired(creatorContractAddress)
    {
        Claim storage claim = _getClaim(creatorContractAddress, instanceId);
        if (claim.storageProtocol != StorageProtocol.NONE) revert ILazyPayableClaimCore.InvalidStorageProtocol();
        claim.location = string(abi.encodePacked(claim.location, locationChunk));
    }

    /**
     * See {IERC1155LazyClaim-getClaim}.
     */
    function getClaim(address creatorContractAddress, uint256 instanceId)
        public
        view
        override
        returns (Claim memory claim)
    {
        return _getClaim(creatorContractAddress, instanceId);
    }

    /**
     * See {IERC1155LazyClaim-getClaimForToken}.
     */
    function getClaimForToken(address creatorContractAddress, uint256 tokenId)
        external
        view
        override
        returns (uint256 instanceId, Claim memory claim)
    {
        instanceId = _claimTokenIds[creatorContractAddress][tokenId];
        claim = _getClaim(creatorContractAddress, instanceId);
    }

    function _getClaim(address creatorContractAddress, uint256 instanceId)
        internal
        view
        returns (Claim storage claim)
    {
        claim = _claims[creatorContractAddress][instanceId];
        if (claim.storageProtocol == StorageProtocol.INVALID) revert ILazyPayableClaimCore.ClaimNotInitialized();
    }

    /**
     * See {ILazyPayableClaim-checkMintIndex}.
     */
    function checkMintIndex(address creatorContractAddress, uint256 instanceId, uint32 mintIndex)
        external
        view
        override
        returns (bool)
    {
        Claim memory claim = getClaim(creatorContractAddress, instanceId);
        return _checkMintIndex(creatorContractAddress, instanceId, claim.merkleRoot, mintIndex);
    }

    /**
     * See {ILazyPayableClaim-checkMintIndices}.
     */
    function checkMintIndices(address creatorContractAddress, uint256 instanceId, uint32[] calldata mintIndices)
        external
        view
        override
        returns (bool[] memory minted)
    {
        Claim memory claim = getClaim(creatorContractAddress, instanceId);
        uint256 mintIndicesLength = mintIndices.length;
        minted = new bool[](mintIndices.length);
        for (uint256 i; i < mintIndicesLength;) {
            minted[i] = _checkMintIndex(creatorContractAddress, instanceId, claim.merkleRoot, mintIndices[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * See {ILazyPayableClaim-getTotalMints}.
     */
    function getTotalMints(address minter, address creatorContractAddress, uint256 instanceId)
        external
        view
        override
        returns (uint32)
    {
        Claim memory claim = getClaim(creatorContractAddress, instanceId);
        return _getTotalMints(claim.walletMax, minter, creatorContractAddress, instanceId);
    }

    /**
     * See {IERC1155LazyPayableClaim-airdrop}.
     */
    function airdrop(
        address creatorContractAddress,
        uint256 instanceId,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external override creatorAdminRequired(creatorContractAddress) {
        if (recipients.length != amounts.length) revert ILazyPayableClaimCore.InvalidAirdrop();

        // Fetch the claim
        Claim storage claim = _getClaim(creatorContractAddress, instanceId);

        uint256 totalAmount;
        for (uint256 i; i < amounts.length;) {
            totalAmount += amounts[i];
            unchecked {
                ++i;
            }
        }
        if (totalAmount > MAX_UINT_32) revert TooManyRequested();
        claim.total += uint32(totalAmount);
        if (claim.totalMax != 0 && claim.total > claim.totalMax) {
            claim.totalMax = claim.total;
        }

        // Airdrop the tokens
        _mintClaim(creatorContractAddress, claim, recipients, amounts);
    }

    /**
     * Mint a claim
     */
    function _mintClaim(
        address creatorContractAddress,
        Claim storage claim,
        address[] memory recipients,
        uint256[] memory amounts
    ) internal {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = claim.tokenId;
        IERC1155CreatorCore(creatorContractAddress).mintExtensionExisting(recipients, tokenIds, amounts);
    }

    /**
     * See {ICreatorExtensionTokenURI-tokenURI}.
     */
    function tokenURI(address creatorContractAddress, uint256 tokenId)
        external
        view
        override
        returns (string memory uri)
    {
        uint224 instanceId = uint224(_claimTokenIds[creatorContractAddress][tokenId]);
        if (instanceId == 0) revert ILazyPayableClaimCore.TokenDNE();
        Claim memory claim = _claims[creatorContractAddress][instanceId];

        if (claim.storageProtocol == StorageProtocol.ADDRESS) {
            return IERC1155LazyPayableClaimMetadata(_bytesToAddress(bytes(claim.location))).tokenURI(
                creatorContractAddress, tokenId, instanceId
            );
        }

        string memory prefix = "";
        if (claim.storageProtocol == StorageProtocol.ARWEAVE) {
            prefix = ARWEAVE_PREFIX;
        } else if (claim.storageProtocol == StorageProtocol.IPFS) {
            prefix = IPFS_PREFIX;
        }
        uri = string(abi.encodePacked(prefix, claim.location));
    }
}
