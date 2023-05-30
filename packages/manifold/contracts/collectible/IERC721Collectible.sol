// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@manifoldxyz/creator-core-solidity/contracts/core/IERC721CreatorCore.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/ERC721/IERC721CreatorExtensionApproveTransfer.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/ICreatorExtensionTokenURI.sol";

import "./ICollectibleCore.sol";

/**
 * @dev ERC721 Collection Interface
 */
interface IERC721Collectible is ICollectibleCore, IERC721CreatorExtensionApproveTransfer, ICreatorExtensionTokenURI {
    event Unveil(address creatorContractAddress, uint256 instanceId, uint256 tokenMintIndex, uint256 tokenId);

    /**
    * @dev Pre-mint given amount to caller
    * @param creatorContractAddress    the creator contract the claim will mint tokens for
    * @param instanceId                the id of the claim in the list of creatorContractAddress' _instances
    * @param amount                    the number of tokens to mint
    */
    function premint(address creatorContractAddress, uint256 instanceId, uint16 amount) external;

    /**
    * @dev Pre-mint 1 token to designated addresses
    * @param creatorContractAddress    the creator contract the claim will mint tokens for
    * @param instanceId                the id of the claim in the list of creatorContractAddress' _instances
    * @param addresses                 List of addresses to premint to
    */
    function premint(address creatorContractAddress, uint256 instanceId, address[] calldata addresses) external;

    /**
    *  @dev set the tokenURI prefix
    * @param creatorContractAddress    the creator contract the claim will mint tokens for
    * @param instanceId                the id of the claim in the list of creatorContractAddress' _instances
    * @param prefix                    the uri prefix to set
    */
    function setTokenURIPrefix(address creatorContractAddress, uint256 instanceId, string calldata prefix) external;

    /**
    * @dev Set whether or not token transfers are locked until end of sale.
    * @param creatorContractAddress    the creator contract the claim will mint tokens for
    * @param instanceId                the id of the claim in the list of creatorContractAddress' _instances
    * @param locked Whether or not transfers are locked
    */
    function setTransferLocked(address creatorContractAddress, uint256 instanceId, bool locked) external;

    /**
    * @dev The `claim` function represents minting during a free claim period. A bit of an overloaded use of hte word "claim".
    */
    function claim(
        address creatorContractAddress,
        uint256 instanceId,
        uint16 amount,
        bytes32 message,
        bytes calldata signature,
        bytes32 nonce
    ) external payable;

    /**
    * @dev purchase
    */
    function purchase(
        address creatorContractAddress,
        uint256 instanceId,
        uint16 amount,
        bytes32 message,
        bytes calldata signature,
        bytes32 nonce
    ) external payable;

    /**
    * @dev returns the collection state
    */
    function state(address creatorContractAddress, uint256 instanceId) external view returns (CollectibleState memory);

    /**
    * @dev Get number of tokens left
    */
    function purchaseRemaining(address creatorContractAddress, uint256 instanceId) external view returns (uint16);
}
