// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../dynamic/DynamicArweaveHash.sol";

contract JakeMeltDynamicArweaveHash is DynamicArweaveHash {

    using Strings for uint256;

    uint256 private _tokenId;
    uint256 private _mintTime;

    constructor(address creator) DynamicArweaveHash(creator) {}

    function mint(address to) public virtual override returns(uint256) {
        require(_tokenId == 0, "Token already minted");
        _tokenId = super.mint(to);
        _mintTime = block.timestamp;
        return _tokenId;
    }

    function _getName() internal view virtual override returns(string memory) {
        return "Melt";
    }

    function _getDescription() internal view virtual override returns(string memory) {
        return string(abi.encodePacked('Days passed: ',((block.timestamp-_mintTime)/86400).toString()));
    }

    // TODO: Get all 365 image hashes from Jake
    function _getImageHash() internal view override returns(string memory imageHash) {
        string[2] memory ARWEAVE_HASHES = ["Hbr2kOtUH0ZTcySaYR6goRdd1lFhLR-N9dHWjvL1Vt4", "MPTCVxo4HxTMp32qIn1nzklDZGwa-YeOnM012eBZCwE"];
        uint256 daysPassed = (block.timestamp - _mintTime)/86400 % ARWEAVE_HASHES.length;
        return ARWEAVE_HASHES[daysPassed];
    }
}
