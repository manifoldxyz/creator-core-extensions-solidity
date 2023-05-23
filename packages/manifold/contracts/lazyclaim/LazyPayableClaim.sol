// SPDX-License-Identifier: MIT
// solhint-disable reason-string
pragma solidity ^0.8.0;

import "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "../../libraries/delegation-registry/IDelegationRegistry.sol";
import "../../libraries/manifold-membership/IManifoldMembership.sol";

import "./ILazyPayableClaim.sol";

/**
 * @title Lazy Payable Claim
 * @author manifold.xyz
 * @notice Lazy payable claim with optional whitelist ERC721 tokens
 */
abstract contract LazyPayableClaim is ILazyPayableClaim, AdminControl {
    using EnumerableSet for EnumerableSet.AddressSet;

    string internal constant ARWEAVE_PREFIX = "https://arweave.net/";
    string internal constant IPFS_PREFIX = "ipfs://";

    uint256 internal constant MINT_INDEX_BITMASK = 0xFF;
    // solhint-disable-next-line
    address public immutable DELEGATION_REGISTRY;

    uint256 public constant MINT_FEE = 500000000000000;
    uint256 public constant MINT_FEE_MERKLE = 690000000000000;
    address public MEMBERSHIP_ADDRESS;

    uint256 internal constant MAX_UINT_24 = 0xffffff;
    uint256 internal constant MAX_UINT_32 = 0xffffffff;
    uint256 internal constant MAX_UINT_56 = 0xffffffffffffff;
    uint256 internal constant MAX_UINT_256 = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    address private constant ADDRESS_ZERO = 0x0000000000000000000000000000000000000000;

    // ONLY USED FOR NON-MERKLE MINTS: stores the number of tokens minted per wallet per claim, in order to limit maximum
    // { contractAddress => { instanceId => { walletAddress => walletMints } } }
    mapping(address => mapping(uint256 => mapping(address => uint256))) internal _mintsPerWallet;

    // ONLY USED FOR MERKLE MINTS: stores mapping from claim to indices minted
    // { contractAddress => {instanceId => { instanceIdOffset => index } } }
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) internal _claimMintIndices;

    EnumerableSet.AddressSet private _proxyAddresses;

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

    constructor(address initialOwner, address delegationRegistry) {
        _transferOwnership(initialOwner);
        DELEGATION_REGISTRY = delegationRegistry;
    }

    /**
     * See {ILazyPayableClaim-withdraw}.
     */
    function withdraw(address payable receiver, uint256 amount) external override adminRequired {
        (bool sent, ) = receiver.call{value: amount}("");
        require(sent, "Failed to transfer to receiver");
    }

    /**
     * See {ILazyPayableClaim-setMembershipAddress}.
     */
    function setMembershipAddress(address membershipAddress) external override adminRequired {
        MEMBERSHIP_ADDRESS = membershipAddress;
    }

    function _transferFunds(address erc20, uint256 cost, address payable recipient, uint16 mintCount, bool merkle, bool allowMembership) internal {
        uint256 payableCost;
        if (erc20 != ADDRESS_ZERO) {
            require(IERC20(erc20).transferFrom(msg.sender, recipient, cost*mintCount), "Insufficient funds");
        } else {
            payableCost = cost;
        }

        /**
         * Add mint fee if:
         * 1. Not allowing memberships OR
         * 2. No membership address set OR
         * 3. Not an active member
        */
        if (MEMBERSHIP_ADDRESS == ADDRESS_ZERO || !allowMembership || !IManifoldMembership(MEMBERSHIP_ADDRESS).isActiveMember(msg.sender)) {
            payableCost += merkle ? MINT_FEE_MERKLE : MINT_FEE; 
        }
        if (mintCount > 1) {
            payableCost *= mintCount;
            cost *= mintCount;
        }

        // Check price
        require(msg.value >= payableCost, "Invalid amount");
        if (erc20 == ADDRESS_ZERO && cost != 0) {
            // solhint-disable-next-line
            (bool sent, ) = recipient.call{value: cost}("");
            require(sent, "Failed to transfer to receiver");
        }
    }

    function _checkMintIndex(address creatorContractAddress, uint256 instanceId, bytes32 merkleRoot, uint32 mintIndex) internal view returns (bool) {
        uint256 claimMintIndex = mintIndex >> 8;
        require(merkleRoot != "", "Can only check merkle claims");
        uint256 claimMintTracking = _claimMintIndices[creatorContractAddress][instanceId][claimMintIndex];
        uint256 mintBitmask = 1 << (mintIndex & MINT_INDEX_BITMASK);
        return mintBitmask & claimMintTracking != 0;
    }

    function _validateMint(address creatorContractAddress, uint256 instanceId, uint48 startDate, uint48 endDate, uint32 walletMax, bytes32 merkleRoot, uint32 mintIndex, bytes32[] calldata merkleProof, address mintFor) internal {
        // Check timestamps
        require(
            (startDate <= block.timestamp) &&
            (endDate == 0 || endDate >= block.timestamp),
            "Claim inactive"
        );

        if (merkleRoot != "") {
            // Merkle mint
            _checkMerkleAndUpdate(msg.sender, creatorContractAddress, instanceId, merkleRoot, mintIndex, merkleProof, mintFor);
        } else {
            require(mintFor == msg.sender, "Invalid input");
            // Non-merkle mint
            if (walletMax != 0) {
                require(++_mintsPerWallet[creatorContractAddress][instanceId][msg.sender] <= walletMax, "Maximum tokens already minted for this wallet");
            }
        }
    }

    function _validateMint(address creatorContractAddress, uint256 instanceId, uint48 startDate, uint48 endDate, uint32 walletMax, bytes32 merkleRoot, uint16 mintCount, uint32[] calldata mintIndices, bytes32[][] calldata merkleProofs, address mintFor) internal {
        // Check timestamps
        require(
            (startDate <= block.timestamp) &&
            (endDate == 0 || endDate >= block.timestamp),
            "Claim inactive"
        );

        if (merkleRoot != "") {
            require(mintCount == mintIndices.length && mintCount == merkleProofs.length, "Invalid input");
            // Merkle mint
            for (uint256 i; i < mintCount;) {
                _checkMerkleAndUpdate(msg.sender, creatorContractAddress, instanceId, merkleRoot, mintIndices[i], merkleProofs[i], mintFor);
                unchecked { ++i; }
            }
        } else {
            require(mintFor == msg.sender, "Invalid input");
            // Non-merkle mint
            if (walletMax != 0) {
                _mintsPerWallet[creatorContractAddress][instanceId][mintFor] += mintCount;
                require(_mintsPerWallet[creatorContractAddress][instanceId][mintFor] <= walletMax, "Too many requested for this wallet");
            }
        }
    }

    function _validateMintProxy(address creatorContractAddress, uint256 instanceId, uint48 startDate, uint48 endDate, uint32 walletMax, bytes32 merkleRoot, uint16 mintCount, uint32[] calldata mintIndices, bytes32[][] calldata merkleProofs, address mintFor) internal {
        // Check timestamps
        require(
            (startDate <= block.timestamp) &&
            (endDate == 0 || endDate >= block.timestamp),
            "Claim inactive"
        );

        if (merkleRoot != "") {
            require(mintCount == mintIndices.length && mintCount == merkleProofs.length, "Invalid input");
            // Merkle mint
            for (uint256 i; i < mintCount;) {
                // Proxy mints treat the mintFor as the transaction sender
                _checkMerkleAndUpdate(mintFor, creatorContractAddress, instanceId, merkleRoot, mintIndices[i], merkleProofs[i], mintFor);
                unchecked { ++i; }
            }
        } else {
            // Non-merkle mint
            if (walletMax != 0) {
                _mintsPerWallet[creatorContractAddress][instanceId][mintFor] += mintCount;
                require(_mintsPerWallet[creatorContractAddress][instanceId][mintFor] <= walletMax, "Too many requested for this wallet");
            }
        }
    }

    function _checkMerkleAndUpdate(address sender, address creatorContractAddress, uint256 instanceId, bytes32 merkleRoot, uint32 mintIndex, bytes32[] memory merkleProof, address mintFor) private {
        // Merkle mint
        bytes32 leaf;
        if (mintFor == sender) {
            leaf = keccak256(abi.encodePacked(sender, mintIndex));
        } else {
            // Direct verification failed, try delegate verification
            IDelegationRegistry dr = IDelegationRegistry(DELEGATION_REGISTRY);
            require(dr.checkDelegateForContract(sender, mintFor, address(this)), "Invalid delegate");
            leaf = keccak256(abi.encodePacked(mintFor, mintIndex));
        }
        require(MerkleProof.verify(merkleProof, merkleRoot, leaf), "Could not verify merkle proof");

        // Check if mintIndex has been minted
        uint256 claimMintIndex = mintIndex >> 8;
        uint256 claimMintTracking = _claimMintIndices[creatorContractAddress][instanceId][claimMintIndex];
        uint256 mintBitmask = 1 << (mintIndex & MINT_INDEX_BITMASK);
        require(mintBitmask & claimMintTracking == 0, "Already minted");
        _claimMintIndices[creatorContractAddress][instanceId][claimMintIndex] = claimMintTracking | mintBitmask;
    }

    function _getTotalMints(uint32 walletMax, address minter, address creatorContractAddress, uint256 instanceId) internal view returns(uint32) {
        require(walletMax != 0, "Can only retrieve for non-merkle claims with walletMax");
        return uint32(_mintsPerWallet[creatorContractAddress][instanceId][minter]);
    }

}