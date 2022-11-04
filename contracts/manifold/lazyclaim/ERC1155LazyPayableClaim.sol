// SPDX-License-Identifier: MIT
// solhint-disable reason-string

pragma solidity ^0.8.0;

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC1155CreatorCore.sol";
import "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/ICreatorExtensionTokenURI.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/interfaces/IERC165.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "./IERC1155LazyPayableClaim.sol";
import "../../libraries/delegation-registry/IDelegationRegistry.sol";

/**
 * @title Lazy Payable Claim
 * @author manifold.xyz
 * @notice Lazy claim with optional whitelist ERC1155 tokens
 */
contract ERC1155LazyPayableClaim is IERC165, IERC1155LazyPayableClaim, ICreatorExtensionTokenURI, ReentrancyGuard {
    using Strings for uint256;

    string private constant ARWEAVE_PREFIX = "https://arweave.net/";
    string private constant IPFS_PREFIX = "ipfs://";
    uint256 private constant MINT_INDEX_BITMASK = 0xFF;
    address public delegationRegistry = 0x00000000b1BBFe1BF5C5934c4bb9c30FEF15E57A;
    uint256 private constant MAX_INT = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    // stores mapping from tokenId to the claim it represents
    // { contractAddress => { tokenId => Claim } }
    mapping(address => mapping(uint256 => Claim)) private _claims;

    // ONLY USED FOR NON-MERKLE MINTS: stores the number of tokens minted per wallet per claim, in order to limit maximum
    // { contractAddress => { claimIndex => { walletAddress => walletMints } } }
    mapping(address => mapping(uint256 => mapping(address => uint256))) private _mintsPerWallet;

    // ONLY USED FOR MERKLE MINTS: stores mapping from claim to indices minted
    // { contractAddress => { claimIndex => { claimIndexOffset => index } } }
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) private _claimMintIndices;

    // { contractAddress => { tokenId => { claimIndex } }
    mapping(address => mapping(uint256 => uint256)) private _claimTokenIds;

    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165) returns (bool) {
        return interfaceId == type(IERC1155LazyPayableClaim).interfaceId ||
            interfaceId == type(ICreatorExtensionTokenURI).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }

    constructor(address newDelegationRegistry) {
        if (newDelegationRegistry != address(0)) delegationRegistry = newDelegationRegistry;
    }

    /**
     * @notice This extension is shared, not single-creator. So we must ensure
     * that a claim's initializer is an admin on the creator contract
     * @param creatorContractAddress    the address of the creator contract to check the admin against
     */
    modifier creatorAdminRequired(address creatorContractAddress) {
        AdminControl creatorCoreContract = AdminControl(creatorContractAddress);
        require(creatorCoreContract.isAdmin(msg.sender), "Wallet is not an administrator for contract");
        _;
    }

    /**
     * See {IERC1155LazyClaim-initializeClaim}.
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

        // // Mint one copy of token to self
        // address[] memory minterAddress = new address[](1);
        // minterAddress[0] = msg.sender;
        // uint[] memory amount = new uint[](1);
        // amount[0] = 1;
        // string[] memory uris = new string[](1);
        // uris[0] = "";

        // // Mint new token on base contract, save which token that is for given claim.
        // uint[] memory tokenIds = IERC1155CreatorCore(creatorContractAddress).mintExtensionNew(minterAddress, amount, uris);
        // _claimTokenIds[creatorContractAddress][tokenIds[0]] = claimIndex;

         // Create the claim
        _claims[creatorContractAddress][claimIndex] = Claim({
            total: 0,
            totalMax: claimParameters.totalMax,
            walletMax: claimParameters.walletMax,
            startDate: claimParameters.startDate,
            endDate: claimParameters.endDate,
            storageProtocol: claimParameters.storageProtocol,
            merkleRoot: claimParameters.merkleRoot,
            location: claimParameters.location,
            tokenId: MAX_INT,
            cost: claimParameters.cost,
            paymentReceiver: claimParameters.paymentReceiver
        });
        
        emit ClaimInitialized(creatorContractAddress, claimIndex, msg.sender);
    }

    /**
     * See {IERC1155LazyClaim-updateClaim}.
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
            merkleRoot: claimParameters.merkleRoot,
            location: claimParameters.location,
            tokenId: _claims[creatorContractAddress][claimIndex].tokenId,
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
            merkleRoot: claim.merkleRoot,
            location: location,
            tokenId: claim.tokenId,
            cost: claim.cost,
            paymentReceiver: claim.paymentReceiver
        });
    }

    /**
     * See {IERC1155LazyClaim-getClaim}.
     */
    function getClaim(address creatorContractAddress, uint256 claimIndex) external override view returns(Claim memory) {
        require(_claims[creatorContractAddress][claimIndex].storageProtocol != StorageProtocol.INVALID, "Claim not initialized");
        return _claims[creatorContractAddress][claimIndex];
    }

    /**
     * See {IERC1155LazyClaim-checkMintIndex}.
     */
    function checkMintIndex(address creatorContractAddress, uint256 claimIndex, uint32 mintIndex) public override view returns(bool) {
        Claim storage claim = _claims[creatorContractAddress][claimIndex];
        require(claim.storageProtocol != StorageProtocol.INVALID, "Claim not initialized");
        require(claim.merkleRoot != "", "Can only check merkle claims");
        uint256 claimMintIndex = mintIndex >> 8;
        uint256 claimMintTracking = _claimMintIndices[creatorContractAddress][claimIndex][claimMintIndex];
        uint256 mintBitmask = 1 << (mintIndex & MINT_INDEX_BITMASK);
        return mintBitmask & claimMintTracking != 0;
    }

    /**
     * See {IERC1155LazyClaim-checkMintIndices}.
     */
    function checkMintIndices(address creatorContractAddress, uint256 claimIndex, uint32[] calldata mintIndices) external override view returns(bool[] memory minted) {
        minted = new bool[](mintIndices.length);
        for (uint i = 0; i < mintIndices.length; i++) {
            minted[i] = checkMintIndex(creatorContractAddress, claimIndex, mintIndices[i]);
        }
    }

    /**
     * See {IERC1155LazyClaim-getTotalMints}.
     */
    function getTotalMints(address minter, address creatorContractAddress, uint256 claimIndex) external override view returns(uint32) {
        Claim storage claim = _claims[creatorContractAddress][claimIndex];
        require(claim.storageProtocol != StorageProtocol.INVALID, "Claim not initialized");
        require(claim.walletMax != 0, "Can only retrieve for non-merkle claims with walletMax");
        return  uint32(_mintsPerWallet[creatorContractAddress][claimIndex][minter]);
    }

    /**
     * See {IERC1155LazyClaim-mint}.
     */
    function mint(address creatorContractAddress, uint256 claimIndex, uint32 mintIndex, bytes32[] calldata merkleProof, address mintFor) external payable override {
        Claim storage claim = _claims[creatorContractAddress][claimIndex];
        
        // Safely retrieve the claim
        require(claim.storageProtocol != StorageProtocol.INVALID, "Claim not initialized");

        // Check price
        require(msg.value == claim.cost, "Must pay more.");

        // Check timestamps
        require(claim.startDate == 0 || claim.startDate < block.timestamp, "Transaction before start date");
        require(claim.endDate == 0 || claim.endDate >= block.timestamp, "Transaction after end date");

        // Check totalMax
        require(claim.totalMax == 0 || claim.total < claim.totalMax, "Maximum tokens already minted for this claim");

        if (claim.merkleRoot != "") {
            // Merkle mint
            _checkMerkleAndUpdate(claim, creatorContractAddress, claimIndex, mintIndex, merkleProof, mintFor);
        } else {
            // Non-merkle mint
            if (claim.walletMax != 0) {
                require(_mintsPerWallet[creatorContractAddress][claimIndex][msg.sender] < claim.walletMax, "Maximum tokens already minted for this wallet");
                unchecked{ _mintsPerWallet[creatorContractAddress][claimIndex][msg.sender]++; }
            }
        }
        unchecked{ claim.total++; }

        address[] memory minterAddress = new address[](1);
        minterAddress[0] = msg.sender;
        uint[] memory amount = new uint[](1);
        amount[0] = 1; // Default 1 for `mint` function.

        // Do mint
        if (claim.tokenId == MAX_INT) {
            // Hasn't been created yet, use mintExtensionNew
            string[] memory uris = new string[](1);
            uris[0] = "";
            uint[] memory newTokenIds = IERC1155CreatorCore(creatorContractAddress).mintExtensionNew(minterAddress, amount, uris);
            _claimTokenIds[creatorContractAddress][newTokenIds[0]] = claimIndex;
            claim.tokenId = newTokenIds[0];
        } else {
            uint[] memory tokenIds = new uint[](1);
            tokenIds[0] = claim.tokenId;
            IERC1155CreatorCore(creatorContractAddress).mintExtensionExisting(minterAddress, tokenIds, amount);
        }

        // Transfer proceeds to receiver
        // solhint-disable-next-line
        (bool sent, ) = payable(claim.paymentReceiver).call{value: msg.value}("");
        require(sent, "Failed to transfer to receiver");

        emit ClaimMint(creatorContractAddress, _claimTokenIds[creatorContractAddress][claimIndex]);
    }

    /**
     * See {IERC1155LazyClaim-mintBatch}.
     */
    function mintBatch(address creatorContractAddress, uint256 claimIndex, uint16 mintCount, uint32[] calldata mintIndices, bytes32[][] calldata merkleProofs, address mintFor) external payable override {
        Claim storage claim = _claims[creatorContractAddress][claimIndex];
        
        // Safely retrieve the claim
        require(claim.storageProtocol != StorageProtocol.INVALID, "Claim not initialized");

        // Check price
        require(msg.value == claim.cost * mintCount, "Must pay more.");

        // Check timestamps
        require(claim.startDate == 0 || claim.startDate < block.timestamp, "Transaction before start date");
        require(claim.endDate == 0 || claim.endDate >= block.timestamp, "Transaction after end date");

        // Check totalMax
        require(claim.totalMax == 0 || claim.total+mintCount <= claim.totalMax, "Too many requested for this claim");

        if (claim.merkleRoot != "") {
            require(mintCount == mintIndices.length && mintCount == merkleProofs.length, "Invalid input");
            // Merkle mint
            for (uint i = 0; i < mintCount; ) {
                uint32 mintIndex = mintIndices[i];
                bytes32[] memory merkleProof = merkleProofs[i];
                
                _checkMerkleAndUpdate(claim, creatorContractAddress, claimIndex, mintIndex, merkleProof, mintFor);
                unchecked { i++; }
            }
        } else {
            // Non-merkle mint
            if (claim.walletMax != 0) {
                require(_mintsPerWallet[creatorContractAddress][claimIndex][msg.sender]+mintCount <= claim.walletMax, "Too many requested for this wallet");
                unchecked{ _mintsPerWallet[creatorContractAddress][claimIndex][msg.sender] += mintCount; }
            }
            
        }
        unchecked{ claim.total += mintCount; }

        address[] memory minterAddress = new address[](1);
        minterAddress[0] = msg.sender;
        uint[] memory amount = new uint[](1);
        amount[0] = mintCount;

        // Do mint
        if (claim.tokenId == MAX_INT) {
            // Hasn't been created yet, use mintExtensionNew
            string[] memory uris = new string[](1);
            uris[0] = "";
            uint[] memory newTokenIds = IERC1155CreatorCore(creatorContractAddress).mintExtensionNew(minterAddress, amount, uris);
            _claimTokenIds[creatorContractAddress][newTokenIds[0]] = claimIndex;
            claim.tokenId = newTokenIds[0];
        } else {
            uint[] memory tokenIds = new uint[](1);
            tokenIds[0] = claim.tokenId;
            IERC1155CreatorCore(creatorContractAddress).mintExtensionExisting(minterAddress, tokenIds, amount);
        }
        // solhint-disable-next-line
        (bool sent, ) = payable(claim.paymentReceiver).call{value: msg.value}("");
        require(sent, "Failed to transfer to receiver");

        emit ClaimMintBatch(creatorContractAddress, claimIndex, mintCount);
    }

    /**
     * See {IERC1155LazyPayableClaim-airdrop}.
     */
    function airdrop(address creatorContractAddress, uint256 claimIndex, address[] calldata recipients,
            uint16[] calldata amounts) external override creatorAdminRequired(creatorContractAddress) {
        require(recipients.length == amounts.length, "Unequal number of recipients and amounts provided");

        // Fetch the claim
        Claim storage claim = _claims[creatorContractAddress][claimIndex];

        for (uint256 i = 0; i < recipients.length;) {
            // Prepare params for airdrop
            address[] memory airdropAddress = new address[](1);
            airdropAddress[0] = recipients[i];
            uint[] memory amount = new uint[](1);
            amount[0] = amounts[i];

            // Airdrop the tokens
            if (claim.tokenId == MAX_INT) {
                // Hasn't been created yet, use mintExtensionNew
                string[] memory uris = new string[](1);
                uris[0] = "";
                uint[] memory newTokenIds = IERC1155CreatorCore(creatorContractAddress).mintExtensionNew(airdropAddress, amount, uris);
                _claimTokenIds[creatorContractAddress][newTokenIds[0]] = claimIndex;
                claim.tokenId = newTokenIds[0];
            } else {
                uint[] memory tokenIds = new uint[](1);
                tokenIds[0] = claim.tokenId;
                IERC1155CreatorCore(creatorContractAddress).mintExtensionExisting(airdropAddress, tokenIds, amount);
            }

            // Increment claim.total
            unchecked{ claim.total += uint32(amounts[i]); }

            unchecked{i++;}
        }
    }

    /**
     * Helper to check merkle proof and whether or not the mintIndex was consumed. Also updates the consumed counts
     */
    function _checkMerkleAndUpdate(Claim storage claim, address creatorContractAddress, uint256 claimIndex, uint32 mintIndex, bytes32[] memory merkleProof, address mintFor) private {
        // Merkle mint
        bytes32 leaf;
        if (mintFor == msg.sender) {
            leaf = keccak256(abi.encodePacked(msg.sender, mintIndex));
        } else {
            // Direct verification failed, try delegate verification
            IDelegationRegistry dr = IDelegationRegistry(delegationRegistry);
            require(dr.checkDelegateForContract(msg.sender, mintFor, address(this)), "Invalid delegate");
            leaf = keccak256(abi.encodePacked(mintFor, mintIndex));
        }
        require(MerkleProof.verify(merkleProof, claim.merkleRoot, leaf), "Could not verify merkle proof");

        // Check if mintIndex has been minted
        uint256 claimMintIndex = mintIndex >> 8;
        uint256 claimMintTracking = _claimMintIndices[creatorContractAddress][claimIndex][claimMintIndex];
        uint256 mintBitmask = 1 << (mintIndex & MINT_INDEX_BITMASK);
        require(mintBitmask & claimMintTracking == 0, "Already minted");
        _claimMintIndices[creatorContractAddress][claimIndex][claimMintIndex] = claimMintTracking | mintBitmask;
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
