// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../contracts/physicalclaim/IPhysicalClaim.sol";

abstract contract PhysicalClaimBase is Test {

    uint256 internal privateKey = 0x1010101010101010101010101010101010101010101010101010101010101010;

    function constructSubmission(uint256 instanceId, IPhysicalClaim.BurnToken[] memory burnTokens, uint8 variation, uint64 variationLimit, uint64 totalLimit, address erc20, uint256 price, address payable fundsRecipient, uint160 expiration, bytes32 nonce) internal view returns (IPhysicalClaim.BurnSubmission memory submission) {
        // Hack because we were getting stack too deep, so need to pass into subfunction
        submission = _constructSubmission(instanceId, burnTokens, variation, variationLimit, totalLimit, erc20, price, fundsRecipient, expiration, nonce);
        submission.instanceId = instanceId;
    }

    function _constructSubmission(uint256 instanceId, IPhysicalClaim.BurnToken[] memory burnTokens, uint8 variation, uint64 variationLimit, uint64 totalLimit, address erc20, uint256 price, address payable fundsRecipient, uint160 expiration, bytes32 nonce) internal view returns (IPhysicalClaim.BurnSubmission memory submission) {
        bytes memory messageData = abi.encode(instanceId, burnTokens, variation, variationLimit, totalLimit, erc20, price, fundsRecipient, expiration, nonce);
        bytes32 message = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageData));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, message);
        bytes memory signature = abi.encodePacked(r, s, v);

        submission.signature = signature;
        submission.message = message;
        submission.burnTokens = burnTokens;
        submission.variation = variation;
        submission.variationLimit = variationLimit;
        submission.totalLimit = totalLimit;
        submission.erc20 = erc20;
        submission.price = price;
        submission.fundsRecipient = fundsRecipient;
        submission.expiration = expiration;
        submission.nonce = nonce;
    }

  }
