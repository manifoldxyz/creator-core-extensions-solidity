// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

/// @author: manifold.xyz

import {
    AllowListData,
    PublicDrop,
    SignedMintValidationParams,
    TokenGatedDropStage
} from "./SeaDropStructs.sol";

/**
 * @notice Pass-through subset of stock SeaDrop v1 that
 *         ManifoldERC1155SeaDropShim forwards admin config to.
 * @dev Intentionally narrow: only the setters the shim proxies during
 *      initialize / multiConfigure / admin pass-through calls. The structs
 *      live in SeaDropStructs.sol so both the shim and this interface
 *      encode arguments identically to the deployed SeaDrop ABI. Mint-phase
 *      execution (public / allowlist / token-gated / signed) is NOT on this
 *      interface — SeaDrop enforces its per-phase checks internally and
 *      funnels every phase into `INonFungibleSeaDropToken.mintSeaDrop`.
 */
interface ISeaDrop {
    function updatePublicDrop(PublicDrop calldata publicDrop) external;

    function updateAllowList(AllowListData calldata allowListData) external;

    function updateCreatorPayoutAddress(address payoutAddress) external;

    function updateAllowedFeeRecipient(address feeRecipient, bool allowed) external;

    function updateDropURI(string calldata dropURI) external;

    function updatePayer(address payer, bool allowed) external;

    function updateTokenGatedDrop(address allowedNftToken, TokenGatedDropStage calldata dropStage)
        external;

    function updateSignedMintValidationParams(
        address signer,
        SignedMintValidationParams calldata signedMintValidationParams
    ) external;
}
