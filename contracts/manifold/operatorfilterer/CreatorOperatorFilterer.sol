// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@manifoldxyz/creator-core-solidity/contracts/extensions/ERC721/IERC721CreatorExtensionApproveTransfer.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/ERC1155/IERC1155CreatorExtensionApproveTransfer.sol";
import "@manifoldxyz/libraries-solidity/contracts/access/IAdminControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @author: manifold.xyz

/**
 * Creator controlled Operator Filter for Manifold Creator contracts
 */
contract CreatorOperatorFilterer is IERC165 {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    error OperatorNotAllowed(address operator);
    error CodeHashFiltered(address account, bytes32 codeHash);
    event OperatorUpdated(address indexed registrant, address indexed operator, bool indexed filtered);
    event CodeHashUpdated(address indexed registrant, bytes32 indexed codeHash, bool indexed filtered);

    mapping(address => EnumerableSet.AddressSet) private _creatorBlockedOperators;
    mapping(address => EnumerableSet.Bytes32Set) private _creatorFilteredCodeHashes;

    modifier creatorAdminRequired(address creatorContractAddress) {
        require(IAdminControl(creatorContractAddress).isAdmin(msg.sender), "Wallet is not an admin");
        _;
    }

    /**
     * @dev Get list of blocked operator addresses for a given creator contract
     */
    function getBlockedOperators(address creatorContractAddress) external view returns (address[] memory result) {
        EnumerableSet.AddressSet storage set = _creatorBlockedOperators[creatorContractAddress];
        result = new address[](set.length());
        for (uint i; i < set.length(); ++i) {
            result[i] = set.at(i);
        }
    }

    /**
     * @dev Get list of blocked operator code hashes for a given creator contract
     */
    function getBlockedOperatorHashes(address creatorContractAddress) external view returns (bytes32[] memory result) {
        EnumerableSet.Bytes32Set storage set = _creatorFilteredCodeHashes[creatorContractAddress];
        result = new bytes32[](set.length());
        for (uint i; i < set.length(); ++i) {
            result[i] = set.at(i);
        }
    }

    /**
     * @dev Configure list of operator addresses for a given creator contract
     *      Only an admin of the creator contract can make this call
     */
    function configureBlockedOperators(address creator, address[] memory operators, bool[] memory blocked) public creatorAdminRequired(creator) {
        require(operators.length == blocked.length, "Mismatch input length");

        for (uint i; i < operators.length; ++i) {
            address operator = operators[i];
            bool blockedValue = blocked[i];
            if (blockedValue) {
                _creatorBlockedOperators[creator].add(operator);
            } else {
                _creatorBlockedOperators[creator].remove(operator);
            }
            emit OperatorUpdated(creator, operator, blockedValue);
        }
    }

    /**
     * @dev Configure list of operator code hashes for a given creator contract
     *      Only an admin of the creator contract can make this call
     */
    function configureBlockedOperatorHashes(address creator, bytes32[] memory hashes, bool[] memory blocked) public creatorAdminRequired(creator) {
        require(hashes.length == blocked.length, "Mismatch input length");
        
        for (uint i; i < hashes.length; ++i) {
            bytes32 hash_ = hashes[i];
            bool blockedValue = blocked[i];
            if (blockedValue) {
                _creatorFilteredCodeHashes[creator].add(hash_);
            } else {
                _creatorFilteredCodeHashes[creator].remove(hash_);
            }
            emit CodeHashUpdated(creator, hash_, blockedValue);
        }
    }

    /**
     * @dev Configure list of operator addresses and code hashes for a given creator contract
     *      Only an admin of the creator contract can make this call
     */
    function configureBlockedOperatorsAndHashes(address creator, address[] memory operators, bool[] memory blockedOperators, bytes32[] memory hashes, bool[] memory blockedHashes) public creatorAdminRequired(creator) {
        configureBlockedOperators(creator, operators, blockedOperators);
        configureBlockedOperatorHashes(creator, hashes, blockedHashes);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override (IERC165) returns (bool) {
        return interfaceId == type(IERC721CreatorExtensionApproveTransfer).interfaceId
            || interfaceId == type(IERC1155CreatorExtensionApproveTransfer).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }

    /**
     * @dev ERC1155: Called by creator contract to approve a transfer
     */
    function approveTransfer(address operator, address from, address, uint256[] calldata, uint256[] calldata)
        external
        view
        returns (bool)
    {
        return isOperatorAllowed(operator, from);
    }

    /**
     * @dev ERC721: Called by creator contract to approve a transfer
     */
    function approveTransfer(address operator, address from, address, uint256) external view returns (bool) {
        return isOperatorAllowed(operator, from);
    }

    /**
     * @dev Check OperatorFiltererRegistry to see if operator is approved
     */
    function isOperatorAllowed(address operator, address from) internal view returns (bool) {
        if (from != operator) {
            if (_creatorBlockedOperators[msg.sender].contains(operator)) {
                revert OperatorNotAllowed(operator);
            }

            if (operator.code.length > 0) {
                bytes32 codeHash = operator.codehash;
                if (_creatorFilteredCodeHashes[msg.sender].contains(codeHash)) {
                    revert CodeHashFiltered(operator, codeHash);
                }
            }
        }

        return true;
    }
}
