// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * Burn Redeem Core interface
 */
interface IPhysicalClaim is IERC165, IERC721Receiver, IERC1155Receiver {
    error InvalidToken(address, uint256);
    error InvalidTokenSpec();
    error InvalidBurnSpec();
    error InvalidBurnAmount();
    error InvalidInput();
    error InvalidData();
    error InvalidPaymentAmount();
    error TransferFailure();
    error SoldOut();

    error InvalidSignature(); // 0x8baa579f
    error ExpiredSignature();
    error InvalidNonce();

    enum TokenSpec { INVALID, ERC721, ERC1155, ERC721_NO_BURN }

    enum BurnSpec { INVALID, NONE, MANIFOLD, OPENZEPPELIN }

    struct BurnSubmission {
        bytes signature;
        bytes32 message;
        uint256 instanceId;
        BurnToken[] burnTokens;
        uint8 variation;
        uint64 variationLimit;
        uint64 totalLimit;
        address erc20;
        uint256 price;
        address payable fundsRecipient;
        uint160 expiration;
        bytes32 nonce;
    }

    event Redeem(uint256 indexed instanceId, address indexed redeemer, uint8 variationSelection, bytes32 nonce);

    /**
     * @notice a `BurnItem` indicates which tokens are eligible to be burned
     * @param contractAddress   the contract address of the token to burn
     * @param tokenId           the token to burn
     * @param tokenSpec         the burn item token type
     * @param burnSpec          whether the contract for a token has a `burn` function and, if so,
     *                          what interface
     * @param amount            (only for ERC1155 tokens) the amount (value) required to burn
     */
    struct BurnToken {
        address contractAddress;
        uint256 tokenId;
        TokenSpec tokenSpec;
        BurnSpec burnSpec;
        uint72 amount;
    }

    /**
     * @notice burn tokens and physical claims multiple times in a single transaction
     * @param submissions               the burn submission entries
     */
    function burnRedeem(BurnSubmission[] calldata submissions) external payable;

    /**
     * @notice burn tokens and physical claim
     * @param submission               the burn submission entries
     */
    function burnRedeem(BurnSubmission calldata submission) external payable;

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

    /**
     * @notice update the authorized signer
     * @param signingAddress            the authorized signer
     */
    function updateSigner(address signingAddress) external;

    /**
     * @notice recover a token that was sent to the contract without safeTransferFrom
     * @param tokenAddress              the address of the token contract
     * @param tokenId                   the id of the token
     * @param destination               the address to send the token to
     */
    function recover(address tokenAddress, uint256 tokenId, address destination) external;

    /**
     * @notice get the number of variations redeemed
     * @param instanceId                the instance id
     * @param variations                the variations
     * @return the number of variations redeemed
     */
    function getVariationCounts(uint256 instanceId, uint8[] calldata variations) external view returns (uint64[] memory);

    /**
     * @notice get the number of redemptions for a given instance
     * @param instanceId                the instance id
     * @return the number of redemptions
     */
    function getTotalCount(uint256 instanceId) external view returns (uint64);
    
}
