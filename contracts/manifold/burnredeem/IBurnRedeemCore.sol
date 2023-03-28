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

    /**
     * @notice the validation type used for a `BurnItem`
     * CONTRACT                 any token from a specific contract is valid
     * RANGE                    token IDs within a range (inclusive) are valid
     * MERKLE_TREE              various individual token IDs included in a merkle tree are valid
     */
    enum ValidationType { INVALID, CONTRACT, RANGE, MERKLE_TREE }

    enum TokenSpec { INVALID, ERC721, ERC1155 }
    enum BurnSpec { NONE, MANIFOLD, OPENZEPPELIN }

    /**
     * @notice a `BurnItem` indicates which tokens are eligible to be burned
     * @param validationType    which type of validation used to check that the burn item is 
     *                          satisfied
     * @param tokenSpec         whether the token is an ERC721 or ERC1155
     * @param burnSpec          whether the contract for a token has a `burn` function and, if so,
     *                          what interface
     * @param amount            (only for ERC1155 tokens) the amount (value) required to burn
     * @param minTokenId        (only for RANGE validation) the minimum valid token ID
     * @param maxTokenId        (only for RANGE validation) the maximum valid token ID
     * @param merkleRoot        (only for MERKLE_TREE validation) the root of the merkle tree of
     *                          valid token IDs
     */
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

    /**
     * @notice a `BurnGroup` is a group of valid `BurnItem`s
     * @param requiredCount     the number of `BurnItem`s (0 < requiredCount <= items.length) that 
     *                          need to be included in a burn
     * @param items             the list of `BurnItem`s
     */
    struct BurnGroup {
        uint256 requiredCount;
        BurnItem[] items;
    }

    /**
     * @notice parameters for burn redeem intialization/updates
     * @param paymentReceiver   the address to forward proceeds from paid burn redeems
     * @param storageProtocol   the type of storage used for the redeem token URIs
     * @param redeemAmount      the number of redeem tokens to mint for each burn redeem
     * @param totalSupply       the maximum number of redeem tokens to mint (0 for unlimited)
     * @param startDate         the starting time for the burn redeem (0 for immediately)
     * @param endDate           the end time for the burn redeem (0 for never)
     * @param cost              the cost for each burn redeem
     * @param location          used to construct the token URI (Arweave hash, full URI, etc.)
     * @param burnSet           a list of `BurnGroup`s that must each be satisfied for a burn redeem
     */
    struct BurnRedeemParameters {
        address payable paymentReceiver;
        StorageProtocol storageProtocol;
        uint16 redeemAmount;
        uint32 totalSupply;
        uint48 startDate;
        uint48 endDate;
        uint160 cost;
        string location;
        BurnGroup[] burnSet;
    }

    struct BurnRedeem {
        address payable paymentReceiver;
        StorageProtocol storageProtocol;
        uint32 redeemedCount;
        uint16 redeemAmount;
        uint32 totalSupply;
        uint8 contractVersion;
        uint48 startDate;
        uint48 endDate;
        uint160 cost;
        string location;
        BurnGroup[] burnSet;
    }

    /**
     * @notice a pointer to a `BurnItem` in a `BurnGroup` used in calls to `burnRedeem`
     * @param groupIndex        the index of the `BurnGroup` in `BurnRedeem.burnSet`
     * @param itemIndex         the index of the `BurnItem` in `BurnGroup.items`
     * @param contractAddress   the address of the contract for the token
     * @param id                the token ID
     * @param merkleProof       the merkle proof for the token ID (only for MERKLE_TREE validation)
     */
    struct BurnToken {
        uint48 groupIndex;
        uint48 itemIndex;
        address contractAddress;
        uint256 id;
        bytes32[] merkleProof;
    }

    /**
     * @notice get a burn redeem corresponding to a creator contract and instanceId
     * @param creatorContractAddress    the address of the creator contract
     * @param instanceId                the instanceId of the burn redeem for the creator contract
     * @return BurnRedeem               the burn redeem object
     */
    function getBurnRedeem(address creatorContractAddress, uint256 instanceId) external view returns(BurnRedeem memory);
    
    /**
     * @notice get a burn redeem corresponding to a creator contract and tokenId
     * @param creatorContractAddress    the address of the creator contract
     * @param tokenId                   the token to retrieve the burn redeem for
     * @return                          the burn redeem instanceId and burn redeem object
     */
    function getBurnRedeemForToken(address creatorContractAddress, uint256 tokenId) external view returns(uint256, BurnRedeem memory);

    /**
     * @notice burn tokens and mint a redeem token
     * @param creatorContractAddress    the address of the creator contract
     * @param instanceId                the instanceId of the burn redeem for the creator contract
     * @param burnRedeemCount           the number of burn redeems we want to do
     * @param burnTokens                the tokens to burn with pointers to the corresponding BurnItem requirement
     */
    function burnRedeem(address creatorContractAddress, uint256 instanceId, uint32 burnRedeemCount, BurnToken[] calldata burnTokens) external payable;

    /**
     * @notice burn tokens and mint redeem tokens multiple times in a single transaction
     * @param creatorContractAddresses  the addresses of the creator contracts
     * @param instanceIds               the instanceIds of the burn redeems for the corresponding creator contract
     * @param burnRedeemCounts          the burn redeem counts for each burn
     * @param burnTokens                the tokens to burn for each burn redeem with pointers to the corresponding BurnItem requirement
     */
    function burnRedeem(address[] calldata creatorContractAddresses, uint256[] calldata instanceIds, uint32[] calldata burnRedeemCounts, BurnToken[][] calldata burnTokens) external payable;

    /**
     * @notice allow admin to airdrop arbitrary tokens 
     * @param creatorContractAddress    the creator contract to mint tokens for
     * @param instanceId                the instanceId of the burn redeem for the creator contract
     * @param recipients                addresses to airdrop to
     * @param amounts                   number of redeems to perform for each address in recipients
     */
    function airdrop(address creatorContractAddress, uint256 instanceId, address[] calldata recipients, uint32[] calldata amounts) external;

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
