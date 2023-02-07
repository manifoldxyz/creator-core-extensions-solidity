// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * Burn Redeem Core interface
 */
interface IBurnRedeemCore is IERC165, IERC721Receiver, IERC1155Receiver  {
    enum StorageProtocol { INVALID, NONE, ARWEAVE, IPFS }
    enum ValidationType { INVALID, CONTRACT, RANGE, MERKLE_TREE }
    enum TokenSpec { INVALID, ERC721, ERC1155 }
    enum BurnSpec { NONE, MANIFOLD, OPENZEPPELIN }

    struct BurnItem {
        ValidationType validationType;
        address contractAddress;
        TokenSpec tokenSpec;
        BurnSpec burnSpec;
        uint72 amount;
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
     * @notice get a burn redeem corresponding to a creator contract and index
     * @param creatorContractAddress    the address of the creator contract
     * @param index                     the index of the burn redeem
     * @return BurnRedeem               the burn redeem object
     */
    function getBurnRedeem(address creatorContractAddress, uint256 index) external view returns(BurnRedeem memory);
    
    /**
     * @notice burn tokens and mint a redeem token
     * @param creatorContractAddress    the address of the creator contract
     * @param index                     the index of the burn redeem
     * @param burnTokens                the tokens to burn with pointers to the corresponding BurnItem requirement
     */
    function burnRedeem(address creatorContractAddress, uint256 index, BurnToken[] calldata burnTokens) external payable;

    /**
     * @notice burn tokens and mint redeem tokens multiple times in a single transaction
     * @param creatorContractAddresses  the addresses of the creator contracts
     * @param indexes                   the indexes of the burn redeems
     * @param burnTokens                the tokens to burn for each burn redeem with pointers to the corresponding BurnItem requirement
     */
    function burnRedeem(address[] calldata creatorContractAddresses, uint256[] calldata indexes, BurnToken[][] calldata burnTokens) external payable;

    /**
     * @notice recover a token that was sent to the contract without safeTransferFrom
     * @param tokenAddress              the address of the token contract
     * @param tokenId                   the id of the token
     * @param destination               the address to send the token to
     */
    function recoverERC721(address tokenAddress, uint256 tokenId, address destination) external;

    /**
     * @notice withdraw Manifold fee proceeds from the contract
     * @param recipient                 recepient of the funds
     * @param amount                    amount to withdraw in Wei
     */
    function withdraw(address payable recipient, uint256 amount) external;

    /**
     * @notice set the Manifold Membership contract address
     * @param addr                      the address of the Manifold Membership contract 
     */
    function setMembershipAddress(address addr) external;
}
