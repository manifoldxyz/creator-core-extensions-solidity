// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

/// @author: manifold.xyz

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {ISeaDropTokenContractMetadata} from "./ISeaDropTokenContractMetadata.sol";
import {
    AllowListData,
    PublicDrop,
    SignedMintValidationParams,
    TokenGatedDropStage
} from "./SeaDropStructs.sol";

/**
 * @notice Local mirror of stock SeaDrop's INonFungibleSeaDropToken.
 * @dev Used by the shim ONLY for interfaceId computation — the shim claims
 *      support for this interface in supportsInterface so SeaDrop and
 *      OpenSea's drop indexer recognise the contract as a SeaDrop-launchable
 *      NFT surface. Method signatures + struct layouts must mirror the
 *      canonical ProjectOpenSea/seadrop interface verbatim so
 *      type(INonFungibleSeaDropToken).interfaceId matches the value live
 *      SeaDrop deployments expect
 */
interface INonFungibleSeaDropToken is ISeaDropTokenContractMetadata, IERC165 {
    /// @dev Thrown by mintSeaDrop when msg.sender is not an allowed SeaDrop.
    error OnlyAllowedSeaDrop();

    /// @dev Emitted when the allowed-SeaDrop set changes.
    event AllowedSeaDropUpdated(address[] allowedSeaDrop);

    function updateAllowedSeaDrop(address[] calldata allowedSeaDrop) external;

    function mintSeaDrop(address minter, uint256 quantity) external payable;

    function getMintStats(address minter)
        external
        view
        returns (uint256 minterNumMinted, uint256 currentTotalSupply, uint256 maxSupply);

    function updatePublicDrop(address seaDropImpl, PublicDrop calldata publicDrop) external;

    function updateAllowList(address seaDropImpl, AllowListData calldata allowListData) external;

    function updateTokenGatedDrop(
        address seaDropImpl,
        address allowedNftToken,
        TokenGatedDropStage calldata dropStage
    ) external;

    function updateDropURI(address seaDropImpl, string calldata dropURI) external;

    function updateCreatorPayoutAddress(address seaDropImpl, address payoutAddress) external;

    function updateAllowedFeeRecipient(address seaDropImpl, address feeRecipient, bool allowed) external;

    function updateSignedMintValidationParams(
        address seaDropImpl,
        address signer,
        SignedMintValidationParams memory signedMintValidationParams
    ) external;

    function updatePayer(address seaDropImpl, address payer, bool allowed) external;
}
