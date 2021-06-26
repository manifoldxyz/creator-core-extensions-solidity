// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC721CreatorCore.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/CreatorExtensionBasic.sol";


contract Airdrop is CreatorExtensionBasic {

    constructor() {}

    function airdrop(address creator, address[] calldata to) external adminRequired {
        for (uint i = 0; i < to.length; i++) {
            IERC721CreatorCore(creator).mintExtension(to[i]);
        }
    }

    function airdrop(address creator, address[] calldata to, string[] calldata uris) external adminRequired {
        require(to.length == uris.length, "Invalid input");
        for (uint i = 0; i < to.length; i++) {
            IERC721CreatorCore(creator).mintExtension(to[i], uris[i]);
        }
    }
}
