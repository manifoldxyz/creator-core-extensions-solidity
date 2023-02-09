// SPDX-License-Identifier: MIT
// solhint-disable reason-string
pragma solidity ^0.8.0;

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC721CreatorCore.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/ICreatorExtensionTokenURI.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import "./LazyPayableClaim.sol";
import "./IERC721LazyPayableClaim.sol";

/**
 * @title Lazy Payable Claim
 * @author manifold.xyz
 * @notice Lazy payable claim with optional whitelist ERC721 tokens
 */
contract ERC721LazyPayableClaim is IERC165, IERC721LazyPayableClaim, ICreatorExtensionTokenURI, ReentrancyGuard, LazyPayableClaim {
    using Strings for uint256;

    // stores mapping from tokenId to the claim it represents
    // { contractAddress => { tokenId => Claim } }
    mapping(address => mapping(uint256 => Claim)) private _claims;

    struct TokenClaim {
        uint224 claimIndex;
        uint32 mintOrder;
    }

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
        // Revert if claim at claimIndex already exists
        require(_claims[creatorContractAddress][claimIndex].storageProtocol == StorageProtocol.INVALID, "Claim already initialized");

        // Sanity checks
        require(claimParameters.storageProtocol != StorageProtocol.INVALID, "Cannot initialize with invalid storage protocol");
        require(claimParameters.endDate == 0 || claimParameters.startDate < claimParameters.endDate, "Cannot have startDate greater than or equal to endDate");
        require(claimParameters.merkleRoot == "" || claimParameters.walletMax == 0, "Cannot provide both mintsPerWallet and merkleRoot");

        // Create the claim
        _claims[creatorContractAddress][claimIndex] = Claim({
            total: 0,
            totalMax: claimParameters.totalMax,
            walletMax: claimParameters.walletMax,
            startDate: claimParameters.startDate,
            endDate: claimParameters.endDate,
            storageProtocol: claimParameters.storageProtocol,
            identical: claimParameters.identical,
            merkleRoot: claimParameters.merkleRoot,
            location: claimParameters.location,
            cost: claimParameters.cost,
            paymentReceiver: claimParameters.paymentReceiver
        });

        emit ClaimInitialized(creatorContractAddress, claimIndex, msg.sender);
    }

    /**
     * See {IERC721LazyClaim-udpateClaim}.
     */
    function updateClaim(
        address creatorContractAddress,
        uint256 claimIndex,
        ClaimParameters calldata claimParameters
    ) external override creatorAdminRequired(creatorContractAddress) {
        // Sanity checks
        require(_claims[creatorContractAddress][claimIndex].storageProtocol != StorageProtocol.INVALID, "Claim not initialized");
        require(claimParameters.storageProtocol != StorageProtocol.INVALID, "Cannot set invalid storage protocol");
        require(claimParameters.endDate == 0 || claimParameters.startDate < claimParameters.endDate, "Cannot have startDate greater than or equal to endDate");

        // Overwrite the existing claim
        _claims[creatorContractAddress][claimIndex] = Claim({
            total: _claims[creatorContractAddress][claimIndex].total,
            totalMax: claimParameters.totalMax,
            walletMax: claimParameters.walletMax,
            startDate: claimParameters.startDate,
            endDate: claimParameters.endDate,
            storageProtocol: claimParameters.storageProtocol,
            identical: claimParameters.identical,
            merkleRoot: claimParameters.merkleRoot,
            location: claimParameters.location,
            cost: claimParameters.cost,
            paymentReceiver: claimParameters.paymentReceiver
        });
    }

    /**
     * See {IERC721LazyClaim-updateTokenURIParams}.
     */
    function updateTokenURIParams(
        address creatorContractAddress, uint256 claimIndex,
        StorageProtocol storageProtocol,
        bool identical,
        string calldata location
    ) external override creatorAdminRequired(creatorContractAddress)  {
        Claim memory claim = _claims[creatorContractAddress][claimIndex];
        require(_claims[creatorContractAddress][claimIndex].storageProtocol != StorageProtocol.INVALID, "Claim not initialized");
        require(storageProtocol != StorageProtocol.INVALID, "Cannot set invalid storage protocol");

        // Overwrite the existing claim
        _claims[creatorContractAddress][claimIndex] = Claim({
            total: claim.total,
            totalMax: claim.totalMax,
            walletMax: claim.walletMax,
            startDate: claim.startDate,
            endDate: claim.endDate,
            storageProtocol: storageProtocol,
            identical: identical,
            merkleRoot: claim.merkleRoot,
            location: location,
            cost: claim.cost,
            paymentReceiver: claim.paymentReceiver
        });
    }

    /**
     * See {ILazyClaim-getClaim}.
     */
    function getClaim(address creatorContractAddress, uint256 claimIndex) public override view returns(Claim memory claim) {
        claim = _claims[creatorContractAddress][claimIndex];
        require(claim.storageProtocol != StorageProtocol.INVALID, "Claim not initialized");
    }

    /**
     * See {ILazyClaim-checkMintIndex}.
     */
    function checkMintIndex(address creatorContractAddress, uint256 claimIndex, uint32 mintIndex) external override view returns(bool) {
        Claim memory claim = getClaim(creatorContractAddress, claimIndex);
        return _checkMintIndex(claim.merkleRoot, creatorContractAddress, claimIndex, mintIndex);
    }

    /**
     * See {ILazyClaim-checkMintIndices}.
     */
    function checkMintIndices(address creatorContractAddress, uint256 claimIndex, uint32[] calldata mintIndices) external override view returns(bool[] memory minted) {
        Claim memory claim = getClaim(creatorContractAddress, claimIndex);
        uint256 mintIndicesLength = mintIndices.length;
        minted = new bool[](mintIndices.length);
        for (uint256 i = 0; i < mintIndicesLength;) {
            minted[i] = _checkMintIndex(claim.merkleRoot, creatorContractAddress, claimIndex, mintIndices[i]);
            unchecked{ ++i; }
        }
    }

    /**
     * See {ILazyClaim-getTotalMints}.
     */
    function getTotalMints(address minter, address creatorContractAddress, uint256 claimIndex) external override view returns(uint32) {
        Claim memory claim = getClaim(creatorContractAddress, claimIndex);
        return _getTotalMints(claim.walletMax, minter, creatorContractAddress, claimIndex);
    }

    /**
     * See {ILazyClaim-mint}.
     */
    function mint(address creatorContractAddress, uint256 claimIndex, uint32 mintIndex, bytes32[] calldata merkleProof, address mintFor) external payable override {
        Claim storage claim = _claims[creatorContractAddress][claimIndex];
        // Safely retrieve the claim
        require(claim.storageProtocol != StorageProtocol.INVALID, "Claim not initialized");

        // Check timestamps
        require(
            (claim.startDate == 0 || claim.startDate < block.timestamp) &&
            (claim.endDate == 0 || claim.endDate >= block.timestamp),
            "Claim inactive"
        );

        // Check totalMax
        require(claim.totalMax == 0 || claim.total < claim.totalMax, "Maximum tokens already minted for this claim");

        _validateMint(creatorContractAddress, claimIndex, claim.walletMax, claim.merkleRoot, mintIndex, merkleProof, mintFor);
        unchecked{ ++claim.total; }

        // Transfer funds
        _transferFunds(claim.cost, claim.paymentReceiver, 1, claim.merkleRoot != "");

        // Do mint
        uint256 newTokenId = IERC721CreatorCore(creatorContractAddress).mintExtension(msg.sender);

        // Insert the new tokenId into _tokenClaims for the current claim address & index
        _tokenClaims[creatorContractAddress][newTokenId] = TokenClaim(uint224(claimIndex), claim.total);

        emit ClaimMint(creatorContractAddress, claimIndex);
    }

    /**
     * See {ILazyClaim-mintBatch}.
     */
    function mintBatch(address creatorContractAddress, uint256 claimIndex, uint16 mintCount, uint32[] calldata mintIndices, bytes32[][] calldata merkleProofs, address mintFor) external payable override {
        Claim storage claim = _claims[creatorContractAddress][claimIndex];
        
        // Safely retrieve the claim
        require(claim.storageProtocol != StorageProtocol.INVALID, "Claim not initialized");

        // Check timestamps
        require(
            (claim.startDate == 0 || claim.startDate < block.timestamp) &&
            (claim.endDate == 0 || claim.endDate >= block.timestamp),
            "Claim inactive"
        );

        // Check totalMax
        require(claim.totalMax == 0 || claim.total+mintCount <= claim.totalMax, "Too many requested for this claim");
        
        //  Validate mint
        _validateMint(creatorContractAddress, claimIndex, claim.walletMax, claim.merkleRoot, mintCount, mintIndices, merkleProofs, mintFor);
        uint256 newMintIndex = claim.total+1;
        unchecked{ claim.total += mintCount; }
        
        // Transfer funds
        _transferFunds(claim.cost, claim.paymentReceiver, mintCount, claim.merkleRoot != "");

        uint256[] memory newTokenIds = IERC721CreatorCore(creatorContractAddress).mintExtensionBatch(msg.sender, mintCount);
        for (uint256 i = 0; i < mintCount;) {
            _tokenClaims[creatorContractAddress][newTokenIds[i]] = TokenClaim(uint224(claimIndex), uint32(newMintIndex+i));
            unchecked { ++i; }
        }

        emit ClaimMintBatch(creatorContractAddress, claimIndex, mintCount);
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

        for (uint256 i = 0; i < recipients.length;) {
            // Airdrop the tokens
            uint256[] memory newTokenIds = IERC721CreatorCore(creatorContractAddress).mintExtensionBatch(recipients[i], amounts[i]);
            
            // Register the tokenClaims, so that tokenURI will work for airdropped tokens
            for (uint256 j = 0; j < newTokenIds.length;) {
                _tokenClaims[creatorContractAddress][newTokenIds[j]] = TokenClaim(uint224(claimIndex), uint32(newMintIndex+j));
                unchecked { ++j; }
            }

            // Increment claim.total and newMintIndex for the next airdrop
            unchecked{ claim.total += uint32(newTokenIds.length); }
            unchecked{ newMintIndex += newTokenIds.length; }

            unchecked{ ++i; }
        }
    }

    /**
     * See {ICreatorExtensionTokenURI-tokenURI}.
     */
    function tokenURI(address creatorContractAddress, uint256 tokenId) external override view returns(string memory uri) {
        TokenClaim memory tokenClaim = _tokenClaims[creatorContractAddress][tokenId];
        require(tokenClaim.claimIndex > 0, "Token does not exist");
        Claim memory claim = _claims[creatorContractAddress][tokenClaim.claimIndex];

        string memory prefix = "";
        if (claim.storageProtocol == StorageProtocol.ARWEAVE) {
            prefix = ARWEAVE_PREFIX;
        } else if (claim.storageProtocol == StorageProtocol.IPFS) {
            prefix = IPFS_PREFIX;
        }
        uri = string(abi.encodePacked(prefix, claim.location));

        // Depending on params, we may want to append a suffix to location
        if (!claim.identical) {
            uri = string(abi.encodePacked(uri, "/", uint256(tokenClaim.mintOrder).toString()));
        }
    }
}
