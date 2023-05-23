// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/creator-core-solidity/contracts/ERC721Creator.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC1155Creator.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";

import "../enumerable/ERC721/ERC721OwnerEnumerableExtension.sol";
import "../enumerable/ERC721/ERC721OwnerEnumerableSingleCreatorExtension.sol";
import "../redeem/ERC721/ERC721RedeemBase.sol";

contract MockERC721Creator is ERC721Creator {
    constructor (string memory _name, string memory _symbol) ERC721Creator(_name, _symbol) {}
}

contract MockERC1155Creator is ERC1155Creator {
    constructor (string memory _name, string memory _symbol) ERC1155Creator(_name, _symbol) {}
}

contract MockERC721OwnerEnumerableExtension is ERC721OwnerEnumerableExtension {
    function testMint(address creator, address to) public {
        super._mintExtension(creator, to);
    }
}

contract MockERC721OwnerEnumerableSingleCreatorExtension is ERC721OwnerEnumerableSingleCreatorExtension {
    constructor(address creator) ERC721OwnerEnumerableSingleCreatorExtension(creator) {}

    function testMint(address to) public {
        super._mintExtension(to);
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

contract MockRegistry {
    address[] public _failOperators;

    function setBlockedOperators(address[] memory failOperators) public {
        for (uint i = 0; i < failOperators.length; i++) {
            _failOperators.push(failOperators[i]);
        }
    }

    function isOperatorAllowed(address, address operator) external view returns (bool) {
        for (uint i = 0; i < _failOperators.length; i++) {
            if (_failOperators[i] == operator) {
                return false;
            }
        }

        return true;
    }

    function registerAndSubscribe(address registrant, address subscription) external {}
}

contract MockManifoldMembership {
    mapping(address => bool) private _members;

    function setMember(address member, bool isMember) public {
        _members[member] = isMember;
    }

    function isActiveMember(address sender) external view returns (bool) {
        return _members[sender];
    }
}

contract MockERC20 is ERC20 {

    constructor (string memory _name, string memory _symbol) ERC20(_name, _symbol) {
    }

    function testMint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockERC721 is ERC721 {
    constructor (string memory _name, string memory _symbol) ERC721(_name, _symbol) {}

    function mint(address to, uint256 tokenId) public {
        _mint(to, tokenId);
    }
}

contract MockERC1155 is ERC1155 {
    constructor (string memory _uri) ERC1155(_uri) {}

    function mint(address to, uint256 id, uint256 amount) public {
        _mint(to, id, amount, "");
    }
}

contract MockERC721Burnable is ERC721Burnable {
    constructor (string memory _name, string memory _symbol) ERC721(_name, _symbol) {}

    function mint(address to, uint256 tokenId) public {
        _mint(to, tokenId);
    }
}

contract MockERC1155Burnable is ERC1155Burnable {
    constructor (string memory _uri) ERC1155(_uri) {}

    function mint(address to, uint256 id, uint256 amount) public {
        _mint(to, id, amount, "");
    }
}
