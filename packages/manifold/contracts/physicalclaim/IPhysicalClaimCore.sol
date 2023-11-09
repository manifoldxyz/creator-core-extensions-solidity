// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * Burn Redeem Core interface
 */
interface IPhysicalClaimCore is IERC165, IERC721Receiver, IERC1155Receiver {
    error InvalidInstance();
    error UnsupportedContractVersion();
    error InvalidToken(uint256);
    error InvalidInput(); // 0xb4fa3fb3
    error InvalidBurnTokenSpec();
    error InvalidBurnFunctionSpec();
    error InvalidData();
    error TransferFailure();
    error ContractDeprecated();

    error PhysicalClaimDoesNotExist(uint256);
    error PhysicalClaimInactive(uint256);

    error InvalidBurnAmount(); // 0x2075cc10
    error InvalidRedeemAmount(); // 0x918e94c5
    error InvalidPaymentAmount(); // 0xfc512fde
    error InvalidSignature(); // 0x8baa579f
    error InvalidVariation(); // 0xc674e37c

    /**
     * @notice the validation type used for a `BurnItem`
     * CONTRACT                 any token from a specific contract is valid
     * RANGE                    token IDs within a range (inclusive) are valid
     * MERKLE_TREE              various individual token IDs included in a merkle tree are valid
     * ANY                      any token from any contract
     */
    enum ValidationType { INVALID, CONTRACT, RANGE, MERKLE_TREE, ANY }

    enum BurnTokenSpec { ERC721, ERC1155, ERC721_NO_BURN }

    enum BurnFunctionSpec { NONE, MANIFOLD, OPENZEPPELIN }

    /**
     * @notice a `BurnItem` indicates which tokens are eligible to be burned
     * @param validationType    which type of validation used to check that the burn item is 
     *                          satisfied
     * @param tokenSpec         the burn item token type
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
        BurnTokenSpec burnTokenSpec;
        BurnFunctionSpec burnFunctionSpec;
        uint72 amount;
        uint256 minTokenId;
        uint256 maxTokenId;
        bytes32 merkleRoot;
    }

    /**
     * @param totalSupply      the maximum number of times the variation can be redeemed (0 means no limit)
     * @param redeemedCount    the number of times the variation has been redeemed
     * @param active           whether the variation is active
     */
    struct VariationState {
        uint16 totalSupply;
        uint16 redeemedCount;
        bool active;
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
     * @param signer            the address of the signer for the transaction details
     * @param burnSet           a list of `BurnGroup`s that must each be satisfied for a burn redeem
     * @param variationLimits        a list of `Variation` ids and limits
     */
    struct PhysicalClaimParameters {
        address payable paymentReceiver;
        uint16 totalSupply;
        uint48 startDate;
        uint48 endDate;
        address signer;
        BurnGroup[] burnSet;
        VariationLimit[] variationLimits;
    }

    /**
     * @notice parameters
     */
    struct VariationLimit {
        uint8 id;
        uint16 totalSupply;
    }

    /**
     * @notice the state for a physical claim
     * @param paymentReceiver   the address to forward proceeds from paid burn redeems
     * @param redeemedCount     the amount currently redeemed
     * @param totalSupply       the maximum number of redemptions to redeem (0 for unlimited)
     * @param startDate         the starting time for the burn redeem (0 for immediately)
     * @param endDate           the end time for the burn redeem (0 for never)
     * @param signer            the address of the signer for the transaction details
     * @param burnSet           a list of `BurnGroup`s that must each be satisfied for a burn redeem
     * @param variationIds      a list of variation IDs for the redemptions
     * @param variations        a mapping of `Variation`s for the redemptions
     */
    struct PhysicalClaim {
        address payable paymentReceiver;
        uint16 redeemedCount;
        uint16 totalSupply;
        uint48 startDate;
        uint48 endDate;
        address signer;
        BurnGroup[] burnSet;
        uint8[] variationIds;
        mapping(uint8 => VariationState) variations;
    }

    /**
     * @notice the state for a physical claim
     * @param paymentReceiver   the address to forward proceeds from paid burn redeems
     * @param redeemedCount     the amount currently redeemed
     * @param totalSupply       the maximum number of redemptions to redeem (0 for unlimited)
     * @param startDate         the starting time for the burn redeem (0 for immediately)
     * @param endDate           the end time for the burn redeem (0 for never)
     * @param signer            the address of the signer for the transaction details
     * @param burnSet           a list of `BurnGroup`s that must each be satisfied for a burn redeem
     * @param variationIds      a list of variation IDs for the redemptions
     * @param variations        a mapping of `Variation`s for the redemptions
     */
    struct PhysicalClaimView {
        address payable paymentReceiver;
        uint16 redeemedCount;
        uint16 totalSupply;
        uint48 startDate;
        uint48 endDate;
        address signer;
        BurnGroup[] burnSet;
        VariationState[] variationStates;
    }

    /**
     * @notice a submission for a physical claim
     * @param instanceId            the instanceId of the physical claim
     * @param count                 the number of times to perform a claim for this instance
     * @param currentClaimCount     the current number of times the physical claim has been redeemed
     * @param variation             the variation to redeem
     * @param data                  the data for the transaction
     * @param signature             the signature for the transaction
     * @param message               the message for the transaction
     * @param nonce                 the nonce for the transaction
     * @param totalCost             the total cost for the transaction
     * @param burnTokens            the tokens to burn
     */
    struct PhysicalClaimSubmission {
        uint56 instanceId;
        uint16 count;
        uint16 currentClaimCount;
        uint8 variation;
        bytes data;
        bytes signature;
        bytes32 message;
        bytes32 nonce;
        uint256 totalCost;
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
    function getPhysicalClaim(uint256 instanceId) external view returns(PhysicalClaimView memory);

    /**
     * @notice gets the number of redemptions for a physical claim for a given redeemer
     * @param instanceId           the instanceId of the physical claim
     * @return redeemer            the address who redeemed
     */
    function getRedemptions(uint256 instanceId, address redeemer) external view returns(uint256);

    /**
     * @notice gets the redemption state for a physical claim for a given variation
     * @param instanceId           the instanceId of the physical claim
     * @param variation            the variation
     * @return VariationState      the max and available for the variation
     */
    function getVariationState(uint256 instanceId, uint8 variation) external view returns(VariationState memory);

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
