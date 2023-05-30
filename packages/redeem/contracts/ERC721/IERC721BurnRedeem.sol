// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "./IERC721RedeemBase.sol";

/**
 * @dev Burn NFT's to receive another lazy minted NFT
 */
interface IERC721Burn is IERC721RedeemBase {

    /**
     * @dev Enable recovery of a given token. Can only be called by contract owner/admin.
     * This is a special function used in case someone accidentally sends a token to this contract.
     */
    function setERC721Recoverable(address contract_, uint256 tokenId, address recoverer) external;

    /**
     * @dev Recover a token.  Returns it to the recoverer set by setERC721Recoverable
     * This is a special function used in case someone accidentally sends a token to this contract.
     */
    function recoverERC721(address contract_, uint256 tokenId) external;

    /**
     * @dev Redeem ERC721 tokens for redemption reward NFT.
     * Requires the user to grant approval beforehand by calling contract's 'approve' function.
     * If the it cannot redeem the NFT, it will clear approvals
     */
    function redeemERC721(address[] calldata contracts, uint256[] calldata tokenIds) external;

}
