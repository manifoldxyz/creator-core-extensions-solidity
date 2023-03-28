// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC721CreatorCore.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/ICreatorExtensionTokenURI.sol";

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import "./LazyPayableClaim.sol";
import "./IERC721LazyPayableClaim.sol";
import "../../libraries/IERC721CreatorCoreVersion.sol";

/**
 * @title Lazy Payable Claim
 * @author manifold.xyz
 * @notice Lazy payable claim with optional whitelist ERC721 tokens
 */
contract ERC721LazyPayableClaim is IERC165, IERC721LazyPayableClaim, ICreatorExtensionTokenURI, LazyPayableClaim {
    using Strings for uint256;

    // stores mapping from contractAddress/claimIndex to the claim it represents
    // { contractAddress => { claimIndex => Claim } }
    mapping(address => mapping(uint256 => Claim)) private _claims;

    struct TokenClaim {
        uint224 claimIndex;
        uint32 mintOrder;
    }

    // NOTE: Only used for creatorContract versions < 3
    // stores which tokenId corresponds to which claimIndex, used to generate token uris
    // { contractAddress => { tokenId => TokenClaim } }
    mapping(address => mapping(uint256 => TokenClaim)) private _tokenClaims;

    function supportsInterface(bytes4 interfaceId) public view virtual override(AdminControl, IERC165) returns (bool) {
        return interfaceId == type(IERC721LazyPayableClaim).interfaceId ||
            interfaceId == type(ILazyPayableClaim).interfaceId ||
            interfaceId == type(ICreatorExtensionTokenURI).interfaceId ||
            interfaceId == type(IAdminControl).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }

    constructor(address delegationRegistry) LazyPayableClaim(delegationRegistry) {}

    /**
     * See {IERC721LazyClaim-initializeClaim}.
     */
    function initializeClaim(
        address creatorContractAddress,
        uint256 claimIndex,
        ClaimParameters calldata claimParameters
    ) external override creatorAdminRequired(creatorContractAddress) {
        // Max uint56 for claimIndex
        require(claimIndex > 0 && claimIndex <= MAX_UINT_56, "Invalid claimIndex");
        // Revert if claim at claimIndex already exists
        require(_claims[creatorContractAddress][claimIndex].storageProtocol == StorageProtocol.INVALID, "Claim already initialized");

        // Sanity checks
        require(claimParameters.storageProtocol != StorageProtocol.INVALID, "Cannot initialize with invalid storage protocol");
        require(claimParameters.endDate == 0 || claimParameters.startDate < claimParameters.endDate, "Cannot have startDate greater than or equal to endDate");
        require(claimParameters.merkleRoot == "" || claimParameters.walletMax == 0, "Cannot provide both walletMax and merkleRoot");

        uint8 creatorContractVersion;
        try IERC721CreatorCoreVersion(creatorContractAddress).VERSION() returns(uint256 version) {
            require(version <= 255, "Unsupported contract version");
            creatorContractVersion = uint8(version);
        } catch {}

        // Create the claim
        _claims[creatorContractAddress][claimIndex] = Claim({
            total: 0,
            totalMax: claimParameters.totalMax,
            walletMax: claimParameters.walletMax,
            startDate: claimParameters.startDate,
            endDate: claimParameters.endDate,
            storageProtocol: claimParameters.storageProtocol,
            contractVersion: creatorContractVersion,
            identical: claimParameters.identical,
            merkleRoot: claimParameters.merkleRoot,
            location: claimParameters.location,
            cost: claimParameters.cost,
            paymentReceiver: claimParameters.paymentReceiver,
            erc20: claimParameters.erc20
        });

        emit ClaimInitialized(creatorContractAddress, claimIndex, msg.sender);
    }

    /**
     * See {IERC721LazyClaim-udpateClaim}.
     */
    function updateClaim(
        address creatorContractAddress,
        uint256 claimIndex,
        ClaimParameters memory claimParameters
    ) external override creatorAdminRequired(creatorContractAddress) {
        // Sanity checks
        Claim memory claim = _claims[creatorContractAddress][claimIndex];
        require(claim.storageProtocol != StorageProtocol.INVALID, "Claim not initialized");
        require(claimParameters.storageProtocol != StorageProtocol.INVALID, "Cannot set invalid storage protocol");
        require(claimParameters.endDate == 0 || claimParameters.startDate < claimParameters.endDate, "Cannot have startDate greater than or equal to endDate");
        require(claimParameters.erc20 == claim.erc20, "Cannot change payment token");
        if (claimParameters.totalMax != 0 && claim.total > claimParameters.totalMax) {
            claimParameters.totalMax = claim.total;
        }

        // Overwrite the existing claim
        _claims[creatorContractAddress][claimIndex] = Claim({
            total: claim.total,
            totalMax: claimParameters.totalMax,
            walletMax: claimParameters.walletMax,
            startDate: claimParameters.startDate,
            endDate: claimParameters.endDate,
            storageProtocol: claimParameters.storageProtocol,
            contractVersion: claim.contractVersion,
            identical: claimParameters.identical,
            merkleRoot: claimParameters.merkleRoot,
            location: claimParameters.location,
            cost: claimParameters.cost,
            paymentReceiver: claimParameters.paymentReceiver,
            erc20: claim.erc20
        });
        emit ClaimUpdated(creatorContractAddress, claimIndex);
    }

    /**
     * See {IERC721LazyClaim-updateTokenURIParams}.
     */
    function updateTokenURIParams(
        address creatorContractAddress, uint256 claimIndex,
        StorageProtocol storageProtocol,
        bool identical,
        string calldata location
    ) external override creatorAdminRequired(creatorContractAddress) {
        Claim storage claim = _claims[creatorContractAddress][claimIndex];
        require(_claims[creatorContractAddress][claimIndex].storageProtocol != StorageProtocol.INVALID, "Claim not initialized");
        require(storageProtocol != StorageProtocol.INVALID, "Cannot set invalid storage protocol");

        claim.storageProtocol = storageProtocol;
        claim.location = location;
        claim.identical = identical;
        emit ClaimUpdated(creatorContractAddress, claimIndex);
    }

    /**
     * See {IERC1155LazyClaim-extendTokenURI}.
     */
    function extendTokenURI(
        address creatorContractAddress, uint256 claimIndex,
        string calldata locationChunk
    ) external override creatorAdminRequired(creatorContractAddress) {
        Claim storage claim = _claims[creatorContractAddress][claimIndex];
        require(claim.storageProtocol == StorageProtocol.NONE && claim.identical, "Invalid storage protocol");
        claim.location = string(abi.encodePacked(claim.location, locationChunk));
        emit ClaimUpdated(creatorContractAddress, claimIndex);
    }

    /**
     * See {ILazyPayableClaim-getClaim}.
     */
    function getClaim(address creatorContractAddress, uint256 claimIndex) public override view returns(Claim memory) {
        return _getClaim(creatorContractAddress, claimIndex);
    }

    /**
     * See {ILazyPayableClaim-getClaimForToken}.
     */
    function getClaimForToken(address creatorContractAddress, uint256 tokenId) public override view returns(Claim memory) {
        TokenClaim memory tokenClaim = _tokenClaims[creatorContractAddress][tokenId];
        uint256 claimIndex;
        if (tokenClaim.claimIndex == 0) {
            // No claim, try to retrieve from tokenData
            uint80 tokenData = IERC721CreatorCore(creatorContractAddress).tokenData(tokenId);
            claimIndex = uint56(tokenData >> 24);
            require(claimIndex != 0, "Claim not initialized");
        }
        return _getClaim(creatorContractAddress, claimIndex);
    }

    function _getClaim(address creatorContractAddress, uint256 claimIndex) private view returns(Claim storage claim) {
        claim = _claims[creatorContractAddress][claimIndex];
        require(claim.storageProtocol != StorageProtocol.INVALID, "Claim not initialized");
    }

    /**
     * See {ILazyPayableClaim-checkMintIndex}.
     */
    function checkMintIndex(address creatorContractAddress, uint256 claimIndex, uint32 mintIndex) external override view returns(bool) {
        Claim memory claim = getClaim(creatorContractAddress, claimIndex);
        return _checkMintIndex(creatorContractAddress, claimIndex, claim.merkleRoot, mintIndex);
    }

    /**
     * See {ILazyPayableClaim-checkMintIndices}.
     */
    function checkMintIndices(address creatorContractAddress, uint256 claimIndex, uint32[] calldata mintIndices) external override view returns(bool[] memory minted) {
        Claim memory claim = getClaim(creatorContractAddress, claimIndex);
        uint256 mintIndicesLength = mintIndices.length;
        minted = new bool[](mintIndices.length);
        for (uint256 i; i < mintIndicesLength;) {
            minted[i] = _checkMintIndex(creatorContractAddress, claimIndex, claim.merkleRoot, mintIndices[i]);
            unchecked{ ++i; }
        }
    }

    /**
     * See {ILazyPayableClaim-getTotalMints}.
     */
    function getTotalMints(address minter, address creatorContractAddress, uint256 claimIndex) external override view returns(uint32) {
        Claim memory claim = getClaim(creatorContractAddress, claimIndex);
        return _getTotalMints(claim.walletMax, minter, creatorContractAddress, claimIndex);
    }

    /**
     * See {ILazyPayableClaim-mint}.
     */
    function mint(address creatorContractAddress, uint256 claimIndex, uint32 mintIndex, bytes32[] calldata merkleProof, address mintFor) external payable override {
        Claim storage claim = _getClaim(creatorContractAddress, claimIndex);

        // Check totalMax
        require((++claim.total <= claim.totalMax || claim.totalMax == 0) && claim.total <= MAX_UINT_24, "Maximum tokens already minted for this claim");

        // Validate mint
        _validateMint(creatorContractAddress, claimIndex, claim.startDate, claim.endDate, claim.walletMax, claim.merkleRoot, mintIndex, merkleProof, mintFor);

        // Transfer funds
        _transferFunds(claim.erc20, claim.cost, claim.paymentReceiver, 1, claim.merkleRoot != "");

        // Do mint
        if (claim.contractVersion >= 3) {
            uint80 tokenData = uint56(claimIndex) << 24 | uint24(claim.total);
            IERC721CreatorCore(creatorContractAddress).mintExtension(msg.sender, tokenData);
        } else {
            uint256 newTokenId = IERC721CreatorCore(creatorContractAddress).mintExtension(msg.sender);
            // Insert the new tokenId into _tokenClaims for the current claim address & index
            _tokenClaims[creatorContractAddress][newTokenId] = TokenClaim(uint224(claimIndex), claim.total);
        }

        emit ClaimMint(creatorContractAddress, claimIndex);
    }

    /**
     * See {ILazyPayableClaim-mintBatch}.
     */
    function mintBatch(address creatorContractAddress, uint256 claimIndex, uint16 mintCount, uint32[] calldata mintIndices, bytes32[][] calldata merkleProofs, address mintFor) external payable override {
        Claim storage claim = _getClaim(creatorContractAddress, claimIndex);

        // Check totalMax
        claim.total += mintCount;
        require((claim.totalMax == 0 || claim.total <= claim.totalMax) && claim.total <= MAX_UINT_24, "Too many requested for this claim");

        // Validate mint
        _validateMint(creatorContractAddress, claimIndex, claim.startDate, claim.endDate, claim.walletMax, claim.merkleRoot, mintCount, mintIndices, merkleProofs, mintFor);
        uint256 newMintIndex = claim.total - mintCount + 1;

        // Transfer funds
        _transferFunds(claim.erc20, claim.cost, claim.paymentReceiver, mintCount, claim.merkleRoot != "");

        if (claim.contractVersion >= 3) {
            uint80[] memory tokenData = new uint80[](mintCount);
            for (uint256 i; i < mintCount;) {
                tokenData[i] = uint56(claimIndex) << 24 | uint24(newMintIndex+i);
                unchecked { ++i; }
            }
            IERC721CreatorCore(creatorContractAddress).mintExtensionBatch(msg.sender, tokenData);
        } else {
            uint256[] memory newTokenIds = IERC721CreatorCore(creatorContractAddress).mintExtensionBatch(msg.sender, mintCount);
            for (uint256 i; i < mintCount;) {
                _tokenClaims[creatorContractAddress][newTokenIds[i]] = TokenClaim(uint224(claimIndex), uint32(newMintIndex+i));
                unchecked { ++i; }
            }
        }

        emit ClaimMintBatch(creatorContractAddress, claimIndex, mintCount);
    }

    /**
     * See {ILazyPayableClaim-mintProxy}.
     */
    function mintProxy(address creatorContractAddress, uint256 claimIndex, uint16 mintCount, uint32[] calldata mintIndices, bytes32[][] calldata merkleProofs, address mintFor) external payable override {
        Claim storage claim = _getClaim(creatorContractAddress, claimIndex);

        // Check totalMax
        claim.total += mintCount;
        require((claim.totalMax == 0 || claim.total <= claim.totalMax) && claim.total <= MAX_UINT_24, "Too many requested for this claim");

        // Validate mint
        _validateMintProxy(creatorContractAddress, claimIndex, claim.startDate, claim.endDate, claim.walletMax, claim.merkleRoot, mintCount, mintIndices, merkleProofs, mintFor);
        uint256 newMintIndex = claim.total - mintCount + 1;

        // Transfer funds
        _transferFundsProxy(claim.erc20, claim.cost, claim.paymentReceiver, mintCount, claim.merkleRoot != "");

        if (claim.contractVersion >= 3) {
            uint80[] memory tokenData = new uint80[](mintCount);
            for (uint256 i; i < mintCount;) {
                tokenData[i] = uint56(claimIndex) << 24 | uint24(newMintIndex+i);
                unchecked { ++i; }
            }
            IERC721CreatorCore(creatorContractAddress).mintExtensionBatch(mintFor, tokenData);
        } else {
            uint256[] memory newTokenIds = IERC721CreatorCore(creatorContractAddress).mintExtensionBatch(mintFor, mintCount);
            for (uint256 i; i < mintCount;) {
                _tokenClaims[creatorContractAddress][newTokenIds[i]] = TokenClaim(uint224(claimIndex), uint32(newMintIndex+i));
                unchecked { ++i; }
            }
        }

        emit ClaimMintProxy(creatorContractAddress, claimIndex, mintCount, msg.sender, mintFor);
    }

    /**
     * See {IERC721LazyClaim-airdrop}.
     */
    function airdrop(address creatorContractAddress, uint256 claimIndex, address[] calldata recipients,
            uint16[] calldata amounts) external override creatorAdminRequired(creatorContractAddress) {
        require(recipients.length == amounts.length, "Unequal number of recipients and amounts provided");

        // Fetch the claim, create newMintIndex to keep track of token ids created by the airdrop
        Claim storage claim = _claims[creatorContractAddress][claimIndex];
        uint256 newMintIndex = claim.total+1;

        if (claim.contractVersion >= 3) {
            for (uint256 i; i < recipients.length;) {
                uint16 mintCount = amounts[i];
                uint80[] memory tokenData = new uint80[](mintCount);
                for (uint256 j; j < mintCount;) {
                    tokenData[j] = uint56(claimIndex) << 24 | uint24(newMintIndex+i);
                    unchecked { ++j; }
                }
                // Airdrop the tokens
                IERC721CreatorCore(creatorContractAddress).mintExtensionBatch(recipients[i], tokenData);

                // Increment newMintIndex for the next airdrop
                unchecked{ newMintIndex += mintCount; }

                unchecked{ ++i; }
            }
        } else {
            for (uint256 i; i < recipients.length;) {
                // Airdrop the tokens
                uint256[] memory newTokenIds = IERC721CreatorCore(creatorContractAddress).mintExtensionBatch(recipients[i], amounts[i]);

                // Register the tokenClaims, so that tokenURI will work for airdropped tokens
                for (uint256 j; j < newTokenIds.length;) {
                    _tokenClaims[creatorContractAddress][newTokenIds[j]] = TokenClaim(uint224(claimIndex), uint32(newMintIndex+j));
                    unchecked { ++j; }
                }

                // Increment newMintIndex for the next airdrop
                unchecked{ newMintIndex += newTokenIds.length; }

                unchecked{ ++i; }
            }
        }
        
        require(newMintIndex - claim.total - 1 <= MAX_UINT_24, "Too many requested");
        claim.total += uint32(newMintIndex - claim.total - 1);
        if (claim.totalMax != 0 && claim.total > claim.totalMax) {
            claim.totalMax = claim.total;
        }
    }

    /**
     * See {ICreatorExtensionTokenURI-tokenURI}.
     */
    function tokenURI(address creatorContractAddress, uint256 tokenId) external override view returns(string memory uri) {
        TokenClaim memory tokenClaim = _tokenClaims[creatorContractAddress][tokenId];
        Claim memory claim;
        uint256 mintOrder;
        if (tokenClaim.claimIndex != 0) {
            claim = _claims[creatorContractAddress][tokenClaim.claimIndex];
            mintOrder = tokenClaim.mintOrder;
        } else {
            // No claim, try to retrieve from tokenData
            uint80 tokenData = IERC721CreatorCore(creatorContractAddress).tokenData(tokenId);
            uint56 claimIndex = uint56(tokenData >> 24);
            require(claimIndex != 0, "Token does not exist");
            claim = _claims[creatorContractAddress][claimIndex];
            mintOrder = uint24(tokenData & MAX_UINT_24);
        }

        string memory prefix = "";
        if (claim.storageProtocol == StorageProtocol.ARWEAVE) {
            prefix = ARWEAVE_PREFIX;
        } else if (claim.storageProtocol == StorageProtocol.IPFS) {
            prefix = IPFS_PREFIX;
        }
        uri = string(abi.encodePacked(prefix, claim.location));

        // Depending on params, we may want to append a suffix to location
        if (!claim.identical) {
            uri = string(abi.encodePacked(uri, "/", uint256(mintOrder).toString()));
        }
    }
}
