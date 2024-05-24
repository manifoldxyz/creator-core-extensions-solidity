// SPDX-License-Identifier: MIT
// solhint-disable reason-string
pragma solidity ^0.8.0;

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC1155CreatorCore.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/ICreatorExtensionTokenURI.sol";

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import './GachaLazyClaim.sol';
import './IERC1155GachaLazyClaim.sol';

/**
 * @title Gacha Lazy 1155 Payable Claim
 * @author manifold.xyz
 * @notice
 */
contract ERC1155GachaLazyClaim is IERC165, IERC1155GachaLazyClaim, ICreatorExtensionTokenURI, GachaLazyClaim {
    using Strings for uint256;

    // stores mapping from contractAddress/instanceId to the claim it represents
    // { contractAddress => { instanceId => Claim } }
    mapping(address => mapping(uint256 => Claim)) private _claims;

    struct GachaItem {
        uint224 instanceId;
        uint32 itemIndex;
    }

    // stores mapping from contractAddress to tokenId to matching GachaItem
    // { contractAddress => { tokenId => GachaItem }}
    mapping(address => mapping(uint256 => GachaItem)) private _gachaItems;

    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, AdminControl) returns (bool) {
        return interfaceId == type(IERC1155GachaLazyClaim).interfaceId ||
            interfaceId == type(IGachaLazyClaim).interfaceId ||
            interfaceId == type(ICreatorExtensionTokenURI).interfaceId ||
            interfaceId == type(IAdminControl).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }

    constructor(address initialOwner) GachaLazyClaim(initialOwner) {}

}