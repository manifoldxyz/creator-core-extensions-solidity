// SPDX-License-Identifier: MIT
// solhint-disable reason-string
pragma solidity ^0.8.0;

import "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
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
    string internal constant ARWEAVE_PREFIX = "https://arweave.net/";
    string internal constant IPFS_PREFIX = "ipfs://";

    uint256 internal constant MINT_INDEX_BITMASK = 0xFF;
    // solhint-disable-next-line
    address public immutable DELEGATION_REGISTRY;

    uint256 public constant MINT_FEE = 420000000000000;
    uint256 public constant MINT_FEE_MERKLE = 690000000000000;
    address public MEMBERSHIP_ADDRESS;

    uint32 internal constant MAX_UINT_32 = 0xffffffff;
    uint256 internal constant MAX_UINT_256 = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    address private constant ADDRESS_ZERO = 0x0000000000000000000000000000000000000000;

    // ONLY USED FOR NON-MERKLE MINTS: stores the number of tokens minted per wallet per claim, in order to limit maximum
    // { contractAddress => { claimIndex => { walletAddress => walletMints } } }
    mapping(address => mapping(uint256 => mapping(address => uint256))) internal _mintsPerWallet;

    // ONLY USED FOR MERKLE MINTS: stores mapping from claim to indices minted
    // { contractAddress => {claimIndex => { claimIndexOffset => index } } }
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) internal _claimMintIndices;

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

    constructor(address delegationRegistry) {
        DELEGATION_REGISTRY = delegationRegistry;
    }

    /**
     * See {ILazyClaim-withdraw}.
     */
    function withdraw(address payable receiver, uint256 amount) external override adminRequired {
        (bool sent, ) = receiver.call{value: amount}("");
        require(sent, "Failed to transfer to receiver");
    }

    /**
     * See {ILazyClaim-setMembershipAddress}.
     */
    function setMembershipAddress(address membershipAddress) external override adminRequired {
        MEMBERSHIP_ADDRESS = membershipAddress;
    }

    function _transferFunds(address erc20, uint256 cost, address payable recipient, uint16 mintCount, bool merkle) internal {
        uint256 payableCost;
        if (erc20 != ADDRESS_ZERO) {
            IERC20(erc20).transferFrom(msg.sender, recipient, cost*mintCount);
        } else {
            payableCost = cost;
        }
        if (MEMBERSHIP_ADDRESS != ADDRESS_ZERO) {
            if (!IManifoldMembership(MEMBERSHIP_ADDRESS).isActiveMember(msg.sender)) {
                payableCost += merkle ? MINT_FEE_MERKLE : MINT_FEE; 
            }
        } else {
            payableCost += merkle ? MINT_FEE_MERKLE : MINT_FEE; 
        }
        if (mintCount > 1) {
            payableCost *= mintCount;
            cost *= mintCount;
        }

        // Check price
        require(msg.value == payableCost, "Invalid amount");
        if (cost > 0) {
            // solhint-disable-next-line
            (bool sent, ) = recipient.call{value: cost}("");
            require(sent, "Failed to transfer to receiver");
        }
    }

    function _checkMintIndex(bytes32 merkleRoot, address creatorContractAddress, uint256 claimIndex, uint32 mintIndex) internal view returns (bool) {
        uint256 claimMintIndex = mintIndex >> 8;
        require(merkleRoot != "", "Can only check merkle claims");
        uint256 claimMintTracking = _claimMintIndices[creatorContractAddress][claimIndex][claimMintIndex];
        uint256 mintBitmask = 1 << (mintIndex & MINT_INDEX_BITMASK);
        return mintBitmask & claimMintTracking != 0;
    }

    function _validateMint(address creatorContractAddress, uint256 claimIndex, uint32 walletMax, bytes32 merkleRoot, uint32 mintIndex, bytes32[] calldata merkleProof, address mintFor) internal {
        if (merkleRoot != "") {
            // Merkle mint
            _checkMerkleAndUpdate(merkleRoot, creatorContractAddress, claimIndex, mintIndex, merkleProof, mintFor);
        } else {
            require(mintFor == msg.sender, "Invalid input");
            // Non-merkle mint
            if (walletMax != 0) {
                require(++_mintsPerWallet[creatorContractAddress][claimIndex][msg.sender] <= walletMax, "Maximum tokens already minted for this wallet");
            }
        }
    }

    function _validateMint(address creatorContractAddress, uint256 claimIndex, uint32 walletMax, bytes32 merkleRoot, uint16 mintCount, uint32[] calldata mintIndices, bytes32[][] calldata merkleProofs, address mintFor) internal {
        if (merkleRoot != "") {
            require(mintCount == mintIndices.length && mintCount == merkleProofs.length, "Invalid input");
            // Merkle mint
            for (uint256 i = 0; i < mintCount;) {
                uint32 mintIndex = mintIndices[i];
                bytes32[] memory merkleProof = merkleProofs[i];
                
                _checkMerkleAndUpdate(merkleRoot, creatorContractAddress, claimIndex, mintIndex, merkleProof, mintFor);
                unchecked { ++i; }
            }
        } else {
            require(mintFor == msg.sender, "Invalid input");
            // Non-merkle mint
            if (walletMax != 0) {
                _mintsPerWallet[creatorContractAddress][claimIndex][mintFor] += mintCount;
                require(_mintsPerWallet[creatorContractAddress][claimIndex][mintFor] <= walletMax, "Too many requested for this wallet");
            }
        }
    }

    function _checkMerkleAndUpdate(bytes32 merkleRoot, address creatorContractAddress, uint256 claimIndex, uint32 mintIndex, bytes32[] memory merkleProof, address mintFor) private {
        // Merkle mint
        bytes32 leaf;
        if (mintFor == msg.sender) {
            leaf = keccak256(abi.encodePacked(msg.sender, mintIndex));
        } else {
            // Direct verification failed, try delegate verification
            IDelegationRegistry dr = IDelegationRegistry(DELEGATION_REGISTRY);
            require(dr.checkDelegateForContract(msg.sender, mintFor, address(this)), "Invalid delegate");
            leaf = keccak256(abi.encodePacked(mintFor, mintIndex));
        }
        require(MerkleProof.verify(merkleProof, merkleRoot, leaf), "Could not verify merkle proof");

        // Check if mintIndex has been minted
        uint256 claimMintIndex = mintIndex >> 8;
        uint256 claimMintTracking = _claimMintIndices[creatorContractAddress][claimIndex][claimMintIndex];
        uint256 mintBitmask = 1 << (mintIndex & MINT_INDEX_BITMASK);
        require(mintBitmask & claimMintTracking == 0, "Already minted");
        _claimMintIndices[creatorContractAddress][claimIndex][claimMintIndex] = claimMintTracking | mintBitmask;
    }

    function _getTotalMints(uint32 walletMax, address minter, address creatorContractAddress, uint256 claimIndex) internal view returns(uint32) {
        require(walletMax != 0, "Can only retrieve for non-merkle claims with walletMax");
        return uint32(_mintsPerWallet[creatorContractAddress][claimIndex][minter]);
    }

}