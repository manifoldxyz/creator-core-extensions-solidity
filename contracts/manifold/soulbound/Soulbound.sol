// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@manifoldxyz/libraries-solidity/contracts/access/IAdminControl.sol";

/**
 * @title Soulbound token
 * @author manifold.xyz
 * @notice Soulbound shared extension for Manifold Creator contracts.
 *         Default - Tokens are soulbound but burnable
 *         Tokens are burnable if they are burnable at the contract level OR the token level
 *         Tokens are soulbound if they are soulbound at the contract level OR the token level
 */
abstract contract Soulbound {

    // Mapping of whether a specific token is no longer soulbound (soulbound by default)
    mapping(address => mapping(uint256 => bool)) internal _tokenNonSoulbound; 
    // Mapping of whether a specific token is not burnable (burnable by default)
    mapping(address => mapping(uint256 => bool)) internal _tokenNonBurnable;
    // Mapping of whether or not all tokens of a contract is not burnable (burnable by default)
    mapping(address => bool) internal _contractNonSoulbound;
    // Mapping of whether or not all tokens of a contract is not burnable (burnable by default)
    mapping(address => bool) internal _contractNonBurnable;

    /**
     * @notice This extension is shared, not single-creator. So we must ensure
     * that a burn redeems's initializer is an admin on the creator contract
     * @param creatorContractAddress    the address of the creator contract to check the admin against
     */
    modifier creatorAdminRequired(address creatorContractAddress) {
        require(IAdminControl(creatorContractAddress).isAdmin(msg.sender), "Must be owner or admin");
        _;
    }

    /**
     * @dev Set whether or not all tokens of a contract are soulbound/burnable
     */
    function _configureContract(address creatorContractAddress, bool soulbound, bool burnable) internal {
        _contractNonSoulbound[creatorContractAddress] = !soulbound;
        _contractNonBurnable[creatorContractAddress] = !burnable;
    }

    /**
     * @dev Set whether or not a token is soulbound/burnable
     */
    function configureToken(address creatorContractAddress, uint256 tokenId, bool soulbound, bool burnable) external creatorAdminRequired(creatorContractAddress) {
        _tokenNonSoulbound[creatorContractAddress][tokenId] = !soulbound;
        _tokenNonBurnable[creatorContractAddress][tokenId] = !burnable;
    }

    /**
     * @dev Set whether or not a set of tokens are soulbound/burnable
     */
    function configureToken(address creatorContractAddress, uint256[] memory tokenIds, bool soulbound, bool burnable) external creatorAdminRequired(creatorContractAddress) {
        for (uint i; i < tokenIds.length;) {
            _tokenNonSoulbound[creatorContractAddress][tokenIds[i]] = !soulbound;
            _tokenNonBurnable[creatorContractAddress][tokenIds[i]] = !burnable;
            unchecked { ++i; }
        }
    }

}
