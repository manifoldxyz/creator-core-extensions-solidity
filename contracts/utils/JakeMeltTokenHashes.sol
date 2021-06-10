// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Strings.sol";

library JakeMeltTokenHashes {
  using Strings for string;

  // TODO: Get all 365 image hashes from Jake
  function getHash(uint256 _index) internal pure returns (string memory imageHash) {
    string[2] memory ARWEAVE_HASHES = ["Hbr2kOtUH0ZTcySaYR6goRdd1lFhLR-N9dHWjvL1Vt4", "MPTCVxo4HxTMp32qIn1nzklDZGwa-YeOnM012eBZCwE"];
    return ARWEAVE_HASHES[_index];
  }
}
