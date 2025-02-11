// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../contracts/crossChainBurn/ICrossChainBurn.sol";

abstract contract CrossChainBurnBase is Test {
  uint256 internal privateKey = 0x1010101010101010101010101010101010101010101010101010101010101010;

  function constructSubmission(
    uint256 instanceId,
    ICrossChainBurn.BurnToken[] memory burnTokens,
    uint64 redeemAmount,
    uint64 totalLimit,
    uint160 expiration
  ) internal view returns (ICrossChainBurn.BurnSubmission memory submission) {
    // Hack because we were getting stack too deep, so need to pass into subfunction
    submission = _constructSubmission(instanceId, burnTokens, redeemAmount, totalLimit, expiration);
    submission.instanceId = instanceId;
  }

  function _constructSubmission(
    uint256 instanceId,
    ICrossChainBurn.BurnToken[] memory burnTokens,
    uint64 redeemAmount,
    uint64 totalLimit,
    uint160 expiration
  ) internal view returns (ICrossChainBurn.BurnSubmission memory submission) {
    bytes32 message = keccak256(abi.encode(instanceId, burnTokens, redeemAmount, totalLimit, expiration));

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, message);
    bytes memory signature = abi.encodePacked(r, s, v);

    submission.signature = signature;
    submission.message = message;
    submission.burnTokens = burnTokens;
    submission.redeemAmount = redeemAmount;
    submission.totalLimit = totalLimit;
    submission.expiration = expiration;
  }
}
