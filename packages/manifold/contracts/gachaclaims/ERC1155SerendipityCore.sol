// SPDX-License-Identifier: MIT
// solhint-disable reason-string
pragma solidity ^0.8.0;

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC1155CreatorCore.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/ICreatorExtensionTokenURI.sol";

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "./SerendipityCore.sol";
import "./IERC1155SerendipityCore.sol";

/**
 * @title Serendipity Lazy Payable Claim - ERC-1155 (Core)
 * @author manifold.xyz
 * @notice Core logic for ERC1155 Serendipity claims
 */
abstract contract ERC1155SerendipityCore is IERC165, IERC1155SerendipityCore, ICreatorExtensionTokenURI, SerendipityCore {
    using Strings for uint256;

    // stores mapping from contractAddress/instanceId to the claim it represents
    // { contractAddress => { instanceId => Claim } }
    mapping(address => mapping(uint256 => Claim)) internal _claims;

    // { contractAddress => { tokenId => { instanceId } }
    mapping(address => mapping(uint256 => uint256)) internal _tokenInstances;

    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, AdminControl) returns (bool) {
        return
            interfaceId == type(IERC1155SerendipityCore).interfaceId ||
            interfaceId == type(ISerendipityCore).interfaceId ||
            interfaceId == type(ICreatorExtensionTokenURI).interfaceId ||
            interfaceId == type(IAdminControl).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }

    /**
     * See {IERC1155SerendipityCore-initializeClaim}.
     */
    function initializeClaim(
        address creatorContractAddress,
        uint256 instanceId,
        ClaimParameters calldata claimParameters
    ) external payable virtual override creatorAdminRequired(creatorContractAddress) {
        _initializeClaim(creatorContractAddress, instanceId, claimParameters);
    }

    function _initializeClaim(
        address creatorContractAddress,
        uint256 instanceId,
        ClaimParameters calldata claimParameters
    ) internal {
        if (deprecated) {
            revert ContractDeprecated();
        }
        if (instanceId == 0 || instanceId > MAX_UINT_56) revert ISerendipityCore.InvalidInstance();
        if (_claims[creatorContractAddress][instanceId].storageProtocol != StorageProtocol.INVALID)
            revert ISerendipityCore.ClaimAlreadyInitialized();
        // Checks
        if (claimParameters.storageProtocol == StorageProtocol.INVALID) revert ISerendipityCore.InvalidStorageProtocol();
        if (claimParameters.endDate != 0 && claimParameters.startDate >= claimParameters.endDate)
            revert ISerendipityCore.InvalidDate();
        if (claimParameters.totalMax > MAX_UINT_32) revert ISerendipityCore.InvalidInput();
        if (claimParameters.tokenVariations > MAX_UINT_8) revert ISerendipityCore.InvalidInput();
        if (claimParameters.cost > MAX_UINT_96) revert ISerendipityCore.InvalidInput();

        address[] memory receivers = new address[](1);
        receivers[0] = msg.sender;
        uint256[] memory amounts = new uint256[](claimParameters.tokenVariations);
        string[] memory uris = new string[](claimParameters.tokenVariations);
        uint256[] memory newTokenIds = IERC1155CreatorCore(creatorContractAddress).mintExtensionNew(receivers, amounts, uris);

        if (newTokenIds[0] > MAX_UINT_80) revert ISerendipityCore.InvalidStartingTokenId();

        // Create the claim
        _claims[creatorContractAddress][instanceId] = Claim({
            storageProtocol: claimParameters.storageProtocol,
            total: 0,
            totalMax: claimParameters.totalMax,
            startDate: claimParameters.startDate,
            endDate: claimParameters.endDate,
            startingTokenId: uint80(newTokenIds[0]),
            tokenVariations: claimParameters.tokenVariations,
            location: claimParameters.location,
            paymentReceiver: claimParameters.paymentReceiver,
            cost: claimParameters.cost,
            erc20: claimParameters.erc20,
            signingAddress: claimParameters.signingAddress
        });
        for (uint256 i; i < claimParameters.tokenVariations; ) {
            _tokenInstances[creatorContractAddress][newTokenIds[i]] = instanceId;
            unchecked {
                ++i;
            }
        }

        emit SerendipityClaimInitialized(creatorContractAddress, instanceId, msg.sender);
    }

    /**
     * See {IERC1155SerendipityCore-updateClaim}.
     */
    function updateClaim(
        address creatorContractAddress,
        uint256 instanceId,
        UpdateClaimParameters memory updateClaimParameters
    ) external override creatorAdminRequired(creatorContractAddress) {
        if (deprecated) {
            revert ContractDeprecated();
        }
        Claim memory claim = _getClaim(creatorContractAddress, instanceId);
        if (instanceId == 0 || instanceId > MAX_UINT_56) revert ISerendipityCore.InvalidInstance();
        if (updateClaimParameters.endDate != 0 && updateClaimParameters.startDate >= updateClaimParameters.endDate)
            revert ISerendipityCore.InvalidDate();
        if (updateClaimParameters.totalMax != 0 && updateClaimParameters.totalMax < claim.total) revert ISerendipityCore.CannotLowerTotalMaxBeyondTotal();
        if (updateClaimParameters.totalMax > MAX_UINT_32) revert ISerendipityCore.InvalidInput();
        if (updateClaimParameters.storageProtocol == StorageProtocol.INVALID) revert ISerendipityCore.InvalidStorageProtocol();
        if (updateClaimParameters.cost > MAX_UINT_96) revert ISerendipityCore.InvalidInput();

        // Overwrite the existing values
        _claims[creatorContractAddress][instanceId] = Claim({
            storageProtocol: updateClaimParameters.storageProtocol,
            total: claim.total,
            totalMax: updateClaimParameters.totalMax,
            startDate: updateClaimParameters.startDate,
            endDate: updateClaimParameters.endDate,
            startingTokenId: claim.startingTokenId,
            tokenVariations: claim.tokenVariations,
            location: updateClaimParameters.location,
            paymentReceiver: updateClaimParameters.paymentReceiver,
            cost: updateClaimParameters.cost,
            erc20: claim.erc20,
            signingAddress: claim.signingAddress
        });
        emit SerendipityClaimUpdated(creatorContractAddress, instanceId);
    }

    /**
     * See {IERC1155SerendipityCore-getClaim}.
     */
    function getClaim(address creatorContractAddress, uint256 instanceId) public view override returns (Claim memory) {
        return _getClaim(creatorContractAddress, instanceId);
    }

    /**
     * See {IERC1155SerendipityCore-getClaimForToken}.
     */
    function getClaimForToken(
        address creatorContractAddress,
        uint256 tokenId
    ) external view override returns (uint256 instanceId, Claim memory claim) {
        instanceId = _tokenInstances[creatorContractAddress][tokenId];
        claim = _getClaim(creatorContractAddress, instanceId);
    }

    function _getClaim(address creatorContractAddress, uint256 instanceId) internal view returns (Claim storage claim) {
        claim = _claims[creatorContractAddress][instanceId];
        if (claim.storageProtocol == StorageProtocol.INVALID) revert ISerendipityCore.ClaimNotInitialized();
    }

    /**
     * See {ISerendipityCore-deliverMints}.
     */
    function deliverMints(
        ISerendipityCore.ClaimMint[] calldata mints,
        bytes calldata signature,
        bytes32 message,
        bytes32 nonce,
        uint256 expiration
    ) external override {
        if (mints.length == 0) revert ISerendipityCore.InvalidInput();
        // Get the first claim to retrieve the signing address
        Claim memory firstClaim = _getClaim(mints[0].creatorContractAddress, mints[0].instanceId);
        _validateMintSignature(firstClaim.signingAddress, signature, nonce, expiration);
        _checkSignatureAndUpdate(firstClaim.signingAddress, mints, signature, message, nonce, expiration);
        for (uint256 i; i < mints.length; ) {
            ClaimMint calldata mintData = mints[i];
            Claim memory claim = (i == 0) ? firstClaim : _getClaim(mintData.creatorContractAddress, mintData.instanceId);
            address[] memory receivers = new address[](mintData.variationMints.length);
            uint256[] memory amounts = new uint256[](mintData.variationMints.length);
            uint256[] memory tokenIds = new uint256[](mintData.variationMints.length);

            for (uint256 j; j < mintData.variationMints.length; ) {
                VariationMint calldata variationMint = mintData.variationMints[j];
                if (variationMint.variationIndex > MAX_UINT_8) revert ISerendipityCore.InvalidVariationIndex();
                uint8 variationIndex = variationMint.variationIndex;
                if (variationIndex > claim.tokenVariations || variationIndex < 1) revert ISerendipityCore.InvalidVariationIndex();
                address recipient = variationMint.recipient;
                if (variationMint.amount > MAX_UINT_32) revert ISerendipityCore.TooManyRequested();
                uint32 amount = variationMint.amount;
                UserMintDetails storage userMintDetails = _mintDetailsPerWallet[mintData.creatorContractAddress][
                    mintData.instanceId
                ][recipient];

                if (userMintDetails.deliveredCount + amount > userMintDetails.reservedCount)
                    revert ISerendipityCore.CannotMintMoreThanReserved();
                if (claim.startingTokenId > MAX_UINT_80) revert ISerendipityCore.InvalidStartingTokenId();
                tokenIds[j] = claim.startingTokenId + variationIndex - 1;
                amounts[j] = amount;
                receivers[j] = recipient;
                userMintDetails.deliveredCount += amount;
                unchecked {
                    j++;
                }
            }

            IERC1155CreatorCore(mintData.creatorContractAddress).mintExtensionExisting(receivers, tokenIds, amounts);
            unchecked {
                i++;
            }
        }
    }

    /**
     * See {ISerendipityCore-getUserMints}.
     */
    function getUserMints(
        address minter,
        address creatorContractAddress,
        uint256 instanceId
    ) external view override returns (UserMintDetails memory) {
        return _getUserMints(minter, creatorContractAddress, instanceId);
    }

    /**
     * See {ICreatorExtensionTokenURI-tokenURI}.
     */
    function tokenURI(address creatorContractAddress, uint256 tokenId) external view override returns (string memory uri) {
        uint256 instanceId = _tokenInstances[creatorContractAddress][tokenId];
        if (instanceId == 0) revert ISerendipityCore.TokenDNE();
        Claim memory claim = _getClaim(creatorContractAddress, instanceId);

        string memory prefix = "";
        if (claim.storageProtocol == StorageProtocol.ARWEAVE) {
            prefix = ARWEAVE_PREFIX;
        } else if (claim.storageProtocol == StorageProtocol.IPFS) {
            prefix = IPFS_PREFIX;
        }
        uri = string(abi.encodePacked(prefix, claim.location, "/", Strings.toString(tokenId - claim.startingTokenId + 1)));
    }

    /**
     * See {IERC1155SerendipityCore-updateTokenURIParams}.
     */
    function updateTokenURIParams(
        address creatorContractAddress,
        uint256 instanceId,
        StorageProtocol storageProtocol,
        string calldata location
    ) external override creatorAdminRequired(creatorContractAddress) {
        Claim storage claim = _getClaim(creatorContractAddress, instanceId);
        if (storageProtocol == StorageProtocol.INVALID) revert ISerendipityCore.InvalidStorageProtocol();
        claim.storageProtocol = storageProtocol;
        claim.location = location;
        emit SerendipityClaimUpdated(creatorContractAddress, instanceId);
    }

    /**
     * Internal function for minting reserves - to be implemented by child contracts
     */
    function _validateMintReserve(
        address creatorContractAddress,
        uint256 instanceId,
        uint32 mintCount
    ) internal view returns (Claim storage claim, uint32 amountToReserve) {
        if (Address.isContract(msg.sender)) revert ISerendipityCore.CannotMintFromContract();
        claim = _getClaim(creatorContractAddress, instanceId);
        // Checks for reserving
        if (mintCount == 0 || mintCount >= MAX_UINT_32) revert ISerendipityCore.InvalidMintCount();
        if (claim.startDate > block.timestamp || (claim.endDate > 0 && claim.endDate < block.timestamp))
            revert ISerendipityCore.ClaimInactive();
        if (claim.totalMax != 0 && claim.total == claim.totalMax) revert ISerendipityCore.ClaimSoldOut();
        if (claim.total == MAX_UINT_32) revert ISerendipityCore.TooManyRequested();

        // calculate the amount to reserve
        amountToReserve = mintCount;
        if (claim.totalMax != 0) {
            amountToReserve = uint32(Math.min(mintCount, claim.totalMax - claim.total));
        }
    }

    function _updateMintReserve(
        address creatorContractAddress,
        uint256 instanceId,
        Claim storage claim,
        uint32 amountToReserve
    ) internal {
        claim.total += amountToReserve;
        _mintDetailsPerWallet[creatorContractAddress][instanceId][msg.sender].reservedCount += amountToReserve;
    }

    function _updateMintReserveFor(
        address creatorContractAddress,
        uint256 instanceId,
        Claim storage claim,
        uint32 amountToReserve,
        address mintFor
    ) internal {
        claim.total += amountToReserve;
        _mintDetailsPerWallet[creatorContractAddress][instanceId][mintFor].reservedCount += amountToReserve;
    }
}
