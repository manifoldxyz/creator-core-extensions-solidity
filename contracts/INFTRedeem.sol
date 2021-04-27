// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "openzeppelin-solidity/contracts/token/ERC1155/IERC1155Receiver.sol";
import "manifoldxyz-creator-core-solidity/contracts/IERC721CreatorExtension.sol";
import "manifoldxyz-libraries-solidity/contracts/access/IAdminControl.sol";

interface INFTRedeem is IAdminControl, IERC1155Receiver, IERC721CreatorExtension {

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

    /**
     * @dev Update approved contracts that can be used to redeem. Can only be called by contract owner/admin.
     */
    function updatedApprovedContracts(address[] calldata contracts, bool[] calldata approved) external;

    /**
     * @dev Update approved tokens that can be used to redeem. Can only be called by contract owner/admin.
     */
    function updatedApprovedTokens(address contract_, uint256[] calldata tokenIds, bool[] calldata approved) external;

    /**
     * @dev Get the redemption rate
     */
    function redemptionRate() external view returns(uint16);

    /**
     * @dev Get number of redemptions left
     */
    function redemptionRemaining() external view returns(uint16);

    /**
     * @dev Check if an NFT is redeemable
     */
     function redeemable(address contract_, uint256 tokenId) external view returns(bool);

}