// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@manifoldxyz/creator-core-solidity/contracts/extensions/ERC721/IERC721CreatorExtensionApproveTransfer.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/ERC1155/IERC1155CreatorExtensionApproveTransfer.sol";
import "@manifoldxyz/libraries-solidity/contracts/access/IAdminControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract CreatorOperatorFilterer is IERC165 {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    error OperatorNotAllowed(address operator);
    error CodeHashFiltered(address account, bytes32 codeHash);

    mapping(address => EnumerableSet.AddressSet) private creatorBlockedOperators;
    mapping(address => EnumerableSet.Bytes32Set) private creatorFilteredCodeHashes;

    modifier creatorAdminRequired(address creatorContractAddress) {
        require(IAdminControl(creatorContractAddress).isAdmin(msg.sender), "Wallet is not an admin");
        _;
    }

    function getBlockedOperators(address creator) external view returns (address[] memory result) {
        EnumerableSet.AddressSet storage set = creatorBlockedOperators[creator];
        result = new address[](set.length());
        for (uint i; i < set.length(); i++) {
            result[i] = set.at(i);
        }
    }

    function getBlockedOperatorHashes(address creator) external view returns (bytes32[] memory result) {
        EnumerableSet.Bytes32Set storage set = creatorFilteredCodeHashes[creator];
        result = new bytes32[](set.length());
        for (uint i; i < set.length(); i++) {
            result[i] = set.at(i);
        }
    }

    function configureBlockedOperators(address creator, address[] memory newOperators, bool[] memory blocked) public creatorAdminRequired(creator) {
        require(newOperators.length == blocked.length, "Mismatch input length");

        for (uint i; i < newOperators.length; i++) {
            if (blocked[i]) {
                creatorBlockedOperators[creator].add(newOperators[i]);
            } else {
                creatorBlockedOperators[creator].remove(newOperators[i]);
            }
        }
    }

    function configureBlockedOperatorHashes(address creator, bytes32[] memory hashes, bool[] memory blocked) public creatorAdminRequired(creator) {
        require(hashes.length == blocked.length, "Mismatch input length");
        
        for (uint i; i < hashes.length; i++) {
            if (blocked[i]) {
                creatorFilteredCodeHashes[creator].add(hashes[i]);
            } else {
                creatorFilteredCodeHashes[creator].remove(hashes[i]);
            }
        }
    }

    function configureBlockedOperatorsAndHashes(address creator, address[] memory newOperators, bytes32[] memory hashes, bool[] memory blockedOperators, bool[] memory blockedHashes) public creatorAdminRequired(creator) {
        configureBlockedOperators(creator, newOperators, blockedOperators);
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
            if (creatorBlockedOperators[msg.sender].contains(operator)) {
                revert OperatorNotAllowed(operator);
            }

            if (operator.code.length > 0) {
                bytes32 codeHash = operator.codehash;
                if (creatorFilteredCodeHashes[msg.sender].contains(codeHash)) {
                    revert CodeHashFiltered(operator, codeHash);
                }
            }
        }

        return true;
    }
}
