// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/libraries-solidity/contracts/access/AdminControlUpgradeable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./INiftyGatewayERC721Edition.sol";
import "./ERC721EditionBase.sol";

/**
 * Nifty Gateway ERC721 Edition Contract Implementation
 */
contract NiftyGatewayERC721EditionImplementation is ERC721EditionBase, AdminControlUpgradeable, INiftyGatewayERC721Edition {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _minters;
    address private _niftyOmnibusWallet;

    function initialize(address creator, string[] memory uriParts) public initializer {
        __Ownable_init();
        _initialize(creator, uriParts);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(AdminControlUpgradeable, ERC721EditionBase) returns (bool) {
        return interfaceId == type(INiftyGatewayERC721Edition).interfaceId || AdminControlUpgradeable.supportsInterface(interfaceId) || ERC721EditionBase.supportsInterface(interfaceId);
    }

    /**
     * @dev See {INiftyGatewayERC721Edition-activate}.
     */
    function activate(uint256 total, address[] calldata minters, address niftyOmnibusWallet) external override adminRequired {
      for (uint i = 0; i < minters.length; i++) {
        _minters.add(minters[i]);
      }
      _niftyOmnibusWallet = niftyOmnibusWallet;
        _activate(total);
    }

    /**
     * @dev See {INiftyGatewayERC721Edition-updateURIParts}.
     */
    function updateURIParts(string[] calldata uriParts) external override adminRequired {
        _updateURIParts(uriParts);
    }

    /**
     * @dev See {INiftyGatewayERC721Edition-mintNifty}.
     */
    function mintNifty(uint256 niftyType, uint256 count) external override {
        require(_minters.contains(msg.sender), "Unauthorized");
        require(niftyType == 1, "Only supported niftyType is 1");
        _mint(_niftyOmnibusWallet, count);
    }

    /**
     * @dev See {INiftyGatewayERC721Edition-_mintCount}.
     */
    function _mintCount(uint256 niftyType) external view override returns (uint256) {
      require(niftyType == 1, "Only supported niftyType is 1");
      return _mintCount();
  }

}
