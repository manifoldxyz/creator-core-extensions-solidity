// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * Burn Redeem Core interface
 */
interface IPhysicalClaimCore is IERC165, IERC721Receiver  {
    error InvalidInstance();
    error UnsupportedContractVersion();
    error InvalidToken(uint256);
    error InvalidInput();
    error InvalidTokenSpec();
    error InvalidBurnSpec();
    error InvalidData();
    error TransferFailure();
    
    error PhysicalClaimDoesNotExist(uint256);
    error PhysicalClaimInactive(uint256);

    error InvalidBurnAmount();
    error InvalidBurnAmount2();
    error InvalidRedeemAmount();
    error InvalidPaymentAmount();
    error InvalidSignature();

    /**
     * @notice the validation type used for a `BurnItem`
     * CONTRACT                 any token from a specific contract is valid
     * RANGE                    token IDs within a range (inclusive) are valid
     * MERKLE_TREE              various individual token IDs included in a merkle tree are valid
     * ANY                      any token from any contract
     */
    enum ValidationType { INVALID, CONTRACT, RANGE, MERKLE_TREE, ANY }

    enum TokenSpec { ERC721, ERC1155 }

    enum BurnSpec { NONE, MANIFOLD, OPENZEPPELIN }

    /**
     * @notice a `BurnItem` indicates which tokens are eligible to be burned
     * @param validationType    which type of validation used to check that the burn item is 
     *                          satisfied
     * @param tokenSpec         whether the token is an  or ERC1155
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
     * @param id               the ID of the variation
     * @param max              the maximum number of times the variation can be redeemed
     */
    struct Variation {
        uint8 id;
        uint16 max;
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
     * @param totalSupply       the maximum number of redemptions to redeem (0 for unlimited)
     * @param startDate         the starting time for the burn redeem (0 for immediately)
     * @param endDate           the end time for the burn redeem (0 for never)
     * @param burnSet           a list of `BurnGroup`s that must each be satisfied for a burn redeem
     * @param variations        a list of `Variation`s for the redemptions
     * @param signer            the address of the signer for the transaction details
     */
    struct PhysicalClaimParameters {
        address payable paymentReceiver;
        uint32 totalSupply;
        uint48 startDate;
        uint48 endDate;
        address signer;
        BurnGroup[] burnSet;
        Variation[] variations;
    }

    struct PhysicalClaim {
        address payable paymentReceiver;
        uint32 redeemedCount;
        uint32 totalSupply;
        uint48 startDate;
        uint48 endDate;
        address signer;
        BurnGroup[] burnSet;
        Variation[] variations;
    }

    struct Redemption {
        uint48 timestamp;
        uint32 redeemedCount;
        uint8 variation;
    }

    struct PhysicalClaimSubmission {
        uint56 instanceId;
        uint32 physicalClaimCount;
        uint32 currentClaimCount;
        uint8 variation;
        bytes data;
        bytes signature;
        bytes32 message;
        bytes32 nonce;
        uint totalCost;
        BurnToken[] burnTokens;
    }

    /**
     * @notice a pointer to a `BurnItem` in a `BurnGroup` used in calls to `burnRedeem`
     * @param groupIndex        the index of the `BurnGroup` in `PhysicalClaim.burnSet`
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
     * @notice get a physical claim corresponding to an instanceId
     * @param instanceId                the instanceId of the physical claim
     * @return PhysicalClaim            the physical claim object
     */
    function getPhysicalClaim(uint256 instanceId) external view returns(PhysicalClaim memory);

    /**
     * @notice gets the redemptions for a physical claim for a given redeemer
     * @param instanceId           the instanceId of the physical claim
     * @return redeemer            the address who redeemed
     */
    function getRedemptions(uint256 instanceId, address redeemer) external view returns(Redemption[] memory);

    /**
     * @notice burn tokens and physical claims multiple times in a single transaction
     * @param submissions               the submissions for the physical claims
     */
    function burnRedeem(PhysicalClaimSubmission[] calldata submissions) external payable;
    
    /**
     * @notice recover a token that was sent to the contract without safeTransferFrom
     * @param tokenAddress              the address of the token contract
     * @param tokenId                   the id of the token
     * @param destination               the address to send the token to
     */
    function recover(address tokenAddress, uint256 tokenId, address destination) external;
}
