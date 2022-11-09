// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/creator-core-solidity/contracts/ERC721Creator.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC1155Creator.sol";

import "../enumerable/ERC721/ERC721OwnerEnumerableExtension.sol";
import "../enumerable/ERC721/ERC721OwnerEnumerableSingleCreatorExtension.sol";
import "../redeem/ERC721/ERC721RedeemBase.sol";

contract MockERC721Creator is ERC721Creator {
     constructor (string memory _name, string memory _symbol) ERC721Creator(_name, _symbol) {}
}

contract MockERC1155Creator is ERC1155Creator {
     constructor () ERC1155Creator() {}
}

contract MockERC721OwnerEnumerableExtension is ERC721OwnerEnumerableExtension {
    function testMint(address creator, address to) public {
        ERC721Creator(creator).mintExtension(to);
    }
}

contract MockERC721OwnerEnumerableSingleCreatorExtension is ERC721OwnerEnumerableSingleCreatorExtension {
    constructor(address creator) ERC721OwnerEnumerableSingleCreatorExtension(creator) {}

    function testMint(address to) public {
        ERC721Creator(_creator).mintExtension(to);
    }
}

contract MockERC721RedeemEnumerable is ERC721OwnerEnumerableSingleCreatorBase, ERC721RedeemBase {
    constructor(address creator, uint16 redemptionRate_, uint16 redemptionMax_) ERC721RedeemBase(creator, redemptionRate_, redemptionMax_) {}

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721RedeemBase, ERC721CreatorExtensionApproveTransfer) returns (bool) {
        return ERC721RedeemBase.supportsInterface(interfaceId) || ERC721CreatorExtensionApproveTransfer.supportsInterface(interfaceId);
    }
}

contract MockETHReceiver {
    fallback() external payable {
        // Transfer caps gas at 2300. This function needs to consume more gas than that.
        for (uint j = 0; j < 2300;) {
            unchecked{ j++; }
        }
    }
}