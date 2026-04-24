// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

/// @author: manifold.xyz

import {ISeaDrop} from "../../../contracts/seadrop/ISeaDrop.sol";
import {INonFungibleSeaDropToken} from "../../../contracts/seadrop/INonFungibleSeaDropToken.sol";
import {
    AllowListData,
    PublicDrop,
    SignedMintValidationParams,
    TokenGatedDropStage
} from "../../../contracts/seadrop/SeaDropStructs.sol";

/**
 * @notice Test-only mock of stock SeaDrop v1.
 * @dev Records the last arguments forwarded by ManifoldERC1155SeaDropShim for
 *      every ISeaDrop setter and emits a matching trace event so Foundry tests
 *      can assert the shim is calling SeaDrop with the expected tuple. Also
 *      exposes fakeMint so tests can exercise the shim's mintSeaDrop through
 *      the only-allowed-SeaDrop auth path without standing up a real SeaDrop
 *      deployment. Intentionally does NOT validate phase windows, fee splits,
 *      merkle proofs, or anything else the real SeaDrop enforces — behaviour
 *      assertions against the mock are limited to what the shim forwards.
 */
contract MockSeaDrop is ISeaDrop {
    PublicDrop private _lastPublicDrop;
    AllowListData private _lastAllowListData;
    address public lastCreatorPayoutAddress;
    string public lastDropURI;

    // Last single-call snapshots (useful for deep-equal on the most recent toggle).
    address public lastFeeRecipient;
    bool public lastFeeRecipientAllowed;
    address public lastPayer;
    bool public lastPayerAllowed;
    address public lastTokenGatedNftToken;
    address public lastSigner;

    // Cumulative state so tests can assert "is this address currently allowed".
    mapping(address => bool) private _allowedFeeRecipients;
    mapping(address => bool) private _allowedPayers;
    mapping(address => TokenGatedDropStage) private _tokenGatedDrops;
    mapping(address => SignedMintValidationParams) private _signedMintValidationParams;

    event PublicDropUpdated(PublicDrop publicDrop);
    event AllowListUpdated(AllowListData allowListData);
    event CreatorPayoutAddressUpdated(address payoutAddress);
    event AllowedFeeRecipientUpdated(address feeRecipient, bool allowed);
    event DropURIUpdated(string dropURI);
    event PayerUpdated(address payer, bool allowed);
    event TokenGatedDropUpdated(address allowedNftToken, TokenGatedDropStage dropStage);
    event SignedMintValidationParamsUpdated(address signer, SignedMintValidationParams params);

    function updatePublicDrop(PublicDrop calldata publicDrop) external override {
        _lastPublicDrop = publicDrop;
        emit PublicDropUpdated(publicDrop);
    }

    function updateAllowList(AllowListData calldata allowListData) external override {
        _lastAllowListData = allowListData;
        emit AllowListUpdated(allowListData);
    }

    function updateCreatorPayoutAddress(address payoutAddress) external override {
        lastCreatorPayoutAddress = payoutAddress;
        emit CreatorPayoutAddressUpdated(payoutAddress);
    }

    function updateAllowedFeeRecipient(address feeRecipient, bool allowed) external override {
        lastFeeRecipient = feeRecipient;
        lastFeeRecipientAllowed = allowed;
        _allowedFeeRecipients[feeRecipient] = allowed;
        emit AllowedFeeRecipientUpdated(feeRecipient, allowed);
    }

    function updateDropURI(string calldata dropURI) external override {
        lastDropURI = dropURI;
        emit DropURIUpdated(dropURI);
    }

    function updatePayer(address payer, bool allowed) external override {
        lastPayer = payer;
        lastPayerAllowed = allowed;
        _allowedPayers[payer] = allowed;
        emit PayerUpdated(payer, allowed);
    }

    function updateTokenGatedDrop(address allowedNftToken, TokenGatedDropStage calldata dropStage)
        external
        override
    {
        lastTokenGatedNftToken = allowedNftToken;
        _tokenGatedDrops[allowedNftToken] = dropStage;
        emit TokenGatedDropUpdated(allowedNftToken, dropStage);
    }

    function updateSignedMintValidationParams(
        address signer,
        SignedMintValidationParams calldata params
    ) external override {
        lastSigner = signer;
        _signedMintValidationParams[signer] = params;
        emit SignedMintValidationParamsUpdated(signer, params);
    }

    // Struct getters — mappings auto-generate getters, but struct state vars
    // do not return their nested dynamic fields through auto-getters, so we
    // expose explicit memory-returning reads for tests to deep-equal against.
    function lastPublicDrop() external view returns (PublicDrop memory) {
        return _lastPublicDrop;
    }

    function lastAllowListData() external view returns (AllowListData memory) {
        return _lastAllowListData;
    }

    function allowedFeeRecipient(address feeRecipient) external view returns (bool) {
        return _allowedFeeRecipients[feeRecipient];
    }

    function allowedPayer(address payer) external view returns (bool) {
        return _allowedPayers[payer];
    }

    function tokenGatedDrop(address allowedNftToken)
        external
        view
        returns (TokenGatedDropStage memory)
    {
        return _tokenGatedDrops[allowedNftToken];
    }

    function signedMintValidationParams(address signer)
        external
        view
        returns (SignedMintValidationParams memory)
    {
        return _signedMintValidationParams[signer];
    }

    /**
     * @notice Test-only entry point that re-enters nftContract as the "only
     *         allowed SeaDrop" caller. Lets tests drive the shim's mintSeaDrop
     *         through its onlyAllowedSeaDrop guard without a real SeaDrop.
     */
    function fakeMint(address nftContract, address minter, uint256 quantity) external {
        INonFungibleSeaDropToken(nftContract).mintSeaDrop(minter, quantity);
    }
}
