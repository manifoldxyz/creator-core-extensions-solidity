// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "./opensea/IOperatorFilterRegistry.sol";
import "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";

abstract contract OperatorFilter is AdminControl {
    error OperatorNotAllowed(address operator);

    IOperatorFilterRegistry internal _operatorFilterRegistry;

    constructor(address operatorFilterRegistry) {
        _operatorFilterRegistry = IOperatorFilterRegistry(operatorFilterRegistry);
    }

    modifier creatorAdminRequired(address creator) {
        require(IAdminControl(creator).isAdmin(msg.sender), "Must be owner or admin of creator contract");
        _;
    }

    modifier onlyAllowedOperator(address creator, address operator, address from) virtual {
        if (from == operator) {
            _;
            return;
        }

        if (!_operatorFilterRegistry.isOperatorAllowed(creator, operator)) {
            revert OperatorNotAllowed(operator);
        }
    }

    function register(address creator, address subscriptionOrRegistrantToCopy, bool subscribe)
        external
        creatorAdminRequired(creator)
    {
        if (subscribe) {
            _operatorFilterRegistry.registerAndSubscribe(creator, subscriptionOrRegistrantToCopy);
        } else {
            if (subscriptionOrRegistrantToCopy != address(0)) {
                _operatorFilterRegistry.registerAndCopyEntries(creator, subscriptionOrRegistrantToCopy);
            } else {
                _operatorFilterRegistry.register(creator);
            }
        }
    }

    function unregister(address creator) external creatorAdminRequired(creator) {
        if (address(_operatorFilterRegistry).code.length > 0) {
            _operatorFilterRegistry.unregister(creator);
        }
    }

    function isRegistered(address creator) external returns (bool) {
        return _operatorFilterRegistry.isRegistered(creator);
    }
}
