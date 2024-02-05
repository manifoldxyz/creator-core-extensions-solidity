// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";

import "./IFrameLazyClaim.sol";
import "./IFramePaymaster.sol";

/**
 * Frame Paymaster
 */
contract FramePaymaster is IFramePaymaster, AdminControl {

    address internal _signer;

    // Nonce usage tracking: mapping of fid to nonce to used status
    mapping(uint256 => mapping(uint256 => bool)) private _usedNonces;

    using ECDSA for bytes32;


    /**
     * See {IFramePaymaster-withdraw}.
     */
    function withdraw(address payable receiver, uint256 amount) external override adminRequired {
        (bool sent, ) = receiver.call{value: amount}("");
        if (!sent) revert FailedToTransfer();
    }

    /**
     * See {IFramePaymaster-setSigner}.
     */
    function setSigner(address signer) external override adminRequired {
        _signer = signer;
    }


    /**
     * See {IFramePaymaster-deliver}.
     */
    function deliver(address extensionAddres, IFrameLazyClaim.Mint[] calldata mints) external override {
        if (msg.sender != _signer) revert InvalidSignature();
        IFrameLazyClaim(extensionAddres).mint(mints);
    }

    /**
     * See {IFramePaymaster-checkout}.
     */
    function checkout(MintSubmission calldata submission) external payable override {
        _validateCheckout(submission);

        uint256 paymentReceived = msg.value;
        for (uint256 i; i < submission.extensionMints.length;) {
            ExtensionMint calldata extensionMint = submission.extensionMints[i];
            IFrameLazyClaim.Mint[] memory mints = new IFrameLazyClaim.Mint[](extensionMint.mints.length);
            uint256 extensionPayment;
            for (uint256 j; j < extensionMint.mints.length;) {
                Mint calldata mint = extensionMint.mints[j];
                IFrameLazyClaim.Recipient[] memory recipients = new IFrameLazyClaim.Recipient[](1);
                recipients[0] = IFrameLazyClaim.Recipient({
                    receiver: msg.sender,
                    amount: mint.amount,
                    payment: mint.payment
                });
                mints[j] = IFrameLazyClaim.Mint({
                    creatorContractAddress: mint.creatorContractAddress,
                    instanceId: mint.instanceId,
                    recipients: recipients
                });
                if (paymentReceived < mint.payment) revert InsufficientPayment();
                paymentReceived -= mint.payment;
                extensionPayment += mint.payment;
                unchecked { ++j; }
            }
            IFrameLazyClaim(extensionMint.extensionAddress).mint{value: extensionPayment}(mints);
            unchecked { ++i; }
        }
    }

    function _validateCheckout(MintSubmission calldata submission) private {
        if (block.timestamp > submission.expiration) revert ExpiredSignature();
        // Verify valid message based on input variables
        bytes memory messageData = abi.encode(submission.extensionMints, submission.fid, submission.expiration, submission.nonce, msg.value);
        bytes32 expectedMessage = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageData));
        address signer = submission.message.recover(submission.signature);
        if (submission.message != expectedMessage || signer != _signer) revert InvalidSignature();
        if (_usedNonces[submission.fid][submission.nonce]) revert InvalidNonce();
        _usedNonces[submission.fid][submission.nonce] = true;
    }
}