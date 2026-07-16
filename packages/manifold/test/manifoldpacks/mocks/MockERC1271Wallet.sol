// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title  MockERC1271Wallet
 * @notice Minimal EIP-1271 smart-contract wallet for tests. Holds a single
 *         owner EOA; `isValidSignature(hash, sig)` returns the ERC-1271 magic
 *         value `0x1626ba7e` iff `sig` is a valid ECDSA signature over `hash`
 *         by that owner. Also accepts ERC721/ERC1155 transfers so it can hold a
 *         pack and receive ripped cards. Proves the ManifoldPacksSeaDropShim
 *         `SignatureChecker` EIP-1271 path (Safe/smart-wallet holders can rip).
 */
contract MockERC1271Wallet is IERC721Receiver, IERC1155Receiver {
    bytes4 internal constant MAGICVALUE = 0x1626ba7e;

    address public immutable signer;

    constructor(address signer_) {
        signer = signer_;
    }

    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4) {
        if (ECDSA.recover(hash, signature) == signer) {
            return MAGICVALUE;
        }
        return 0xffffffff;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return
            interfaceId == type(IERC1155Receiver).interfaceId ||
            interfaceId == type(IERC721Receiver).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }
}
