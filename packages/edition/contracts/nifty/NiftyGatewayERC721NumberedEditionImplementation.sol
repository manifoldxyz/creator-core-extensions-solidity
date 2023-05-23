// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/libraries-solidity/contracts/access/AdminControlUpgradeable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./INiftyGatewayERC721NumberedEdition.sol";
import "../ERC721NumberedEditionBase.sol";

/**
 * Nifty Gateway ERC721 Numbered Edition Contract Implementation
 */
contract NiftyGatewayERC721NumberedEditionImplementation is ERC721NumberedEditionBase, AdminControlUpgradeable, INiftyGatewayERC721NumberedEdition {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _minters;
    address private _niftyOmnibusWallet;

    function initialize(address creator, uint256 maxSupply_, string[] memory uriParts) public initializer {
        __Ownable_init();
        _initialize(creator, maxSupply_, uriParts);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(AdminControlUpgradeable, ERC721NumberedEditionBase) returns (bool) {
        return interfaceId == type(INiftyGatewayERC721NumberedEdition).interfaceId || AdminControlUpgradeable.supportsInterface(interfaceId) || ERC721NumberedEditionBase.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IERC721NumberedEdition-activate}.
     */
    function activate(address[] calldata minters, address niftyOmnibusWallet) external override adminRequired {
        for (uint i = 0; i < minters.length; i++) {
            _minters.add(minters[i]);
        }
        _niftyOmnibusWallet = niftyOmnibusWallet;
    }

    /**
     * @dev See {IERC721NumberedEdition-updateURIParts}.
     */
    function updateURIParts(string[] calldata uriParts) external override adminRequired {
        _updateURIParts(uriParts);
    }

    /**
     * @dev See {IERC721NumberedEdition-mint}.
     */
    function mint(address recipient, uint16 count) external override adminRequired {
        _mint(recipient, count);
    }

    /**
     * @dev See {IERC721NumberedEdition-mint}.
     */
    function mint(address[] calldata recipients) external override adminRequired {
        _mint(recipients);
    }

    /**
     * @dev See {INiftyGatewayERC721NumberedEdition-mintNifty}.
     */
    function mintNifty(uint256 niftyType, uint16 count) external override {
        require(_minters.contains(msg.sender), "Unauthorized");
        require(niftyType == 1, "Only supported niftyType is 1");
        _mint(_niftyOmnibusWallet, uint16(count));
    }

    /**
     * @dev See {INiftyGatewayERC721NumberedEdition-_mintCount}.
     */
    function _mintCount(uint256 niftyType) external view override returns (uint256) {
        require(niftyType == 1, "Only supported niftyType is 1");
        return _totalSupply;
    }

}
