// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "operator-filter-registry/src/IOperatorFilterRegistry.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";

/**
 * @title  CreatorOperatorFilterer
 * @notice This is a port of https://github.com/ProjectOpenSea/operator-filter-registry/blob/0968789ad7e78418b9fa7cf7aff012f2e883120b/src/OperatorFilterer.sol
 *         Abstract contract whose constructor automatically registers and optionally subscribes to or copies another
 *         registrant's entries in the OperatorFilterRegistry.
 * @dev    This smart contract is meant to be inherited by token contracts so they can use the following:
 *         - `onlyAllowedOperator` modifier for `transferFrom` and `safeTransferFrom` methods.
 *         - `onlyAllowedOperatorApproval` modifier for `approve` and `setApprovalForAll` methods.
 */
abstract contract CreatorOperatorFilterer is AdminControl {
    error OperatorNotAllowed(address operator);

    IOperatorFilterRegistry internal _operatorFilterRegistry;

    constructor(address operatorFilterRegistry, address subscriptionOrRegistrantToCopy, bool subscribe) {
        switchRegistry(operatorFilterRegistry, subscriptionOrRegistrantToCopy, subscribe);
    }

    function switchRegistry(address operatorFilterRegistry, address subscriptionOrRegistrantToCopy, bool subscribe)
        public
        adminRequired
    {
        require(operatorFilterRegistry.code.length > 0, "IOperatorFilterRegistry not found");

        if (address(_operatorFilterRegistry).code.length > 0) {
            _operatorFilterRegistry.unregister(address(this));
        }

        _operatorFilterRegistry = IOperatorFilterRegistry(operatorFilterRegistry);

        if (subscribe) {
            _operatorFilterRegistry.registerAndSubscribe(address(this), subscriptionOrRegistrantToCopy);
        } else {
            if (subscriptionOrRegistrantToCopy != address(0)) {
                _operatorFilterRegistry.registerAndCopyEntries(address(this), subscriptionOrRegistrantToCopy);
            } else {
                _operatorFilterRegistry.register(address(this));
            }
        }
    }

    function _checkFilterOperator(address operator) internal view virtual {
        // Check registry code length to facilitate testing in environments without a deployed registry.
        if (address(_operatorFilterRegistry).code.length > 0) {
            if (!_operatorFilterRegistry.isOperatorAllowed(address(this), operator)) {
                revert OperatorNotAllowed(operator);
            }
        }
    }

    modifier creatorAdminRequired(address creator) {
        require(IAdminControl(creator).isAdmin(msg.sender), "Must be owner or admin of creator contract");
        _;
    }

    modifier onlyAllowedOperator(address operator, address from) {
        // Allow spending tokens from addresses with balance
        // Note that this still allows listings and marketplaces with escrow to transfer tokens if transferred
        // from an EOA.
        if (from != operator) {
            _checkFilterOperator(operator);
        }
        _;
    }

    modifier onlyAllowedOperatorApproval(address operator) {
        _checkFilterOperator(operator);
        _;
    }
}
