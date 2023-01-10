// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/**
 * Burn Token interface
 */
interface Burnable721 {
    function burn(uint256 tokenId) external;
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;
}

/**
 * Burn Redeem interface
 */
interface IERC721BurnRedeem is IERC721Receiver {
    enum StorageProtocol { INVALID, NONE, ARWEAVE, IPFS }
    enum ValidationType { INVALID, CONTRACT, RANGE, MERKLE_TREE }

    struct BurnItem {
        ValidationType validationType;
        address contractAddress;
        uint256 minTokenId;
        uint256 maxTokenId;
        bytes32 merkleRoot;
    }

    struct BurnGroup {
        uint256 requiredCount;
        BurnItem[] items;
    }

    struct BurnRedeemParameters {
        uint48 startDate;
        uint48 endDate;
        uint32 totalSupply;
        bool identical;
        StorageProtocol storageProtocol;
        string location;
        uint256 cost;
        BurnGroup[] burnSet;
    }

    struct BurnRedeem {
        uint48 startDate;
        uint48 endDate;
        uint32 redeemedCount;
        uint32 totalSupply;
        bool identical;
        StorageProtocol storageProtocol;
        string location;
        uint256 cost;
        BurnGroup[] burnSet;
    }

    struct BurnToken {
        uint48 groupIndex;
        uint48 itemIndex;
        address contractAddress;
        uint256 id;
        bytes32[] merkleProof;
    }

    struct RedeemToken {
        uint224 burnRedeemIndex;
        uint32 mintNumber;
    }

    event BurnRedeemInitialized(address indexed creatorContract, uint256 indexed index, address initializer);
    event BurnRedeemMint(address indexed creatorContract, uint256 indexed index, uint256 indexed tokenId);

    /**
     * @notice initialize a new burn redeem, emit initialize event, and return the newly created index
     * @param creatorContractAddress    the creator contract the burn will mint redeem tokens for
     * @param index                     the index of the burnRedeem in the mapping of creatorContractAddress' _burnRedeems
     * @param burnRedeemParameters      the parameters which will affect the minting behavior of the burn redeem
     */
    function initializeBurnRedeem(address creatorContractAddress, uint256 index, BurnRedeemParameters calldata burnRedeemParameters) external;

    /**
     * @notice update an existing burn redeem at index
     * @param creatorContractAddress    the creator contract corresponding to the burn redeem
     * @param index                     the index of the burn redeem in the list of creatorContractAddress' _burnRedeems
     * @param burnRedeemParameters      the parameters which will affect the minting behavior of the burn redeem
     */
    function updateBurnRedeem(address creatorContractAddress, uint256 index, BurnRedeemParameters calldata burnRedeemParameters) external;

    /**
     * @notice get a burn redeem corresponding to a creator contract and index
     * @param creatorContractAddress    the address of the creator contract
     * @param index                     the index of the burn redeem
     * @return                          the burn redeem object
     */
    function getBurnRedeem(address creatorContractAddress, uint256 index) external view returns(BurnRedeem memory);
    
    /**
     * @notice burn tokens and mint a redeem token
     * @param creatorContractAddress    the address of the creator contract
     * @param index                     the index of the burn redeem
     * @param burnTokens                the tokens to burn with pointers to the corresponding BurnItem requirement
     */
    function burnRedeem(address creatorContractAddress, uint256 index, BurnToken[] calldata burnTokens) external payable;
}
