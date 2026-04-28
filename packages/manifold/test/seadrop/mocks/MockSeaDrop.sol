// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

/// @author: manifold.xyz

import {SeaDrop} from "seadrop/src/SeaDrop.sol";
import {
    AllowListData as ShimAllowListData,
    PublicDrop as ShimPublicDrop,
    SignedMintValidationParams as ShimSignedMintValidationParams,
    TokenGatedDropStage as ShimTokenGatedDropStage
} from "../../../contracts/seadrop/SeaDropStructs.sol";
import {
    AllowListData as ActualAllowListData,
    PublicDrop as ActualPublicDrop,
    SignedMintValidationParams as ActualSignedMintValidationParams,
    TokenGatedDropStage as ActualTokenGatedDropStage
} from "seadrop/src/lib/SeaDropStructs.sol";

/**
 * @notice Test wrapper around the deployed SeaDrop v1 source from Etherscan.
 * @dev This intentionally uses the real SeaDrop implementation for all config
 *      and mint-path behavior, while preserving the old MockSeaDrop helper
 *      methods used by the shim unit tests. The wrapper reads state for a
 *      single observed NFT contract (the shim under test) because stock SeaDrop
 *      keys all config by `msg.sender`/`nftContract`.
 */
contract MockSeaDrop is SeaDrop {
    address internal _observedNftContract;

    function setObservedNftContract(address nftContract) external {
        _observedNftContract = nftContract;
    }

    function lastPublicDrop() external view returns (ShimPublicDrop memory pd) {
        ActualPublicDrop memory actual = this.getPublicDrop(_observedNftContract);
        pd = ShimPublicDrop({
            mintPrice: actual.mintPrice,
            startTime: actual.startTime,
            endTime: actual.endTime,
            maxTotalMintableByWallet: actual.maxTotalMintableByWallet,
            feeBps: actual.feeBps,
            restrictFeeRecipients: actual.restrictFeeRecipients
        });
    }

    function lastAllowListData() external view returns (ShimAllowListData memory ald) {
        ald = ShimAllowListData({
            merkleRoot: this.getAllowListMerkleRoot(_observedNftContract),
            publicKeyURIs: new string[](0),
            allowListURI: ""
        });
    }

    function lastCreatorPayoutAddress() external view returns (address) {
        return this.getCreatorPayoutAddress(_observedNftContract);
    }

    function allowedFeeRecipient(address feeRecipient) external view returns (bool) {
        return this.getFeeRecipientIsAllowed(_observedNftContract, feeRecipient);
    }

    function allowedPayer(address payer) external view returns (bool) {
        return this.getPayerIsAllowed(_observedNftContract, payer);
    }

    function tokenGatedDrop(address allowedNftToken)
        external
        view
        returns (ShimTokenGatedDropStage memory stage)
    {
        ActualTokenGatedDropStage memory actual = this.getTokenGatedDrop(
            _observedNftContract,
            allowedNftToken
        );
        stage = ShimTokenGatedDropStage({
            mintPrice: actual.mintPrice,
            maxTotalMintableByWallet: actual.maxTotalMintableByWallet,
            startTime: actual.startTime,
            endTime: actual.endTime,
            dropStageIndex: actual.dropStageIndex,
            maxTokenSupplyForStage: actual.maxTokenSupplyForStage,
            feeBps: actual.feeBps,
            restrictFeeRecipients: actual.restrictFeeRecipients
        });
    }

    function signedMintValidationParams(address signer)
        external
        view
        returns (ShimSignedMintValidationParams memory params)
    {
        ActualSignedMintValidationParams memory actual = this.getSignedMintValidationParams(
            _observedNftContract,
            signer
        );
        params = ShimSignedMintValidationParams({
            minMintPrice: actual.minMintPrice,
            maxMaxTotalMintableByWallet: actual.maxMaxTotalMintableByWallet,
            minStartTime: actual.minStartTime,
            maxEndTime: actual.maxEndTime,
            maxMaxTokenSupplyForStage: actual.maxMaxTokenSupplyForStage,
            minFeeBps: actual.minFeeBps,
            maxFeeBps: actual.maxFeeBps
        });
    }

    function lastFeeRecipient() external pure returns (address) {
        revert("lastFeeRecipient is not tracked by stock SeaDrop");
    }

    function lastFeeRecipientAllowed() external pure returns (bool) {
        revert("lastFeeRecipientAllowed is not tracked by stock SeaDrop");
    }

    function lastPayer() external pure returns (address) {
        revert("lastPayer is not tracked by stock SeaDrop");
    }

    function lastPayerAllowed() external pure returns (bool) {
        revert("lastPayerAllowed is not tracked by stock SeaDrop");
    }

    function lastDropURI() external pure returns (string memory) {
        revert("dropURI is emitted by stock SeaDrop, not stored");
    }

    function lastTokenGatedNftToken() external pure returns (address) {
        revert("lastTokenGatedNftToken is not tracked by stock SeaDrop");
    }

    function lastSigner() external pure returns (address) {
        revert("lastSigner is not tracked by stock SeaDrop");
    }
}
