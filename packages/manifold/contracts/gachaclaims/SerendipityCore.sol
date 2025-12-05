// SPDX-License-Identifier: MIT
// solhint-disable reason-string
pragma solidity ^0.8.0;

import "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "./ISerendipityCore.sol";

/**
 * @title Serendipity Core
 * @author manifold.xyz
 * @notice Base contract for Serendipity claims
 */
abstract contract SerendipityCore is ISerendipityCore, AdminControl {
    using EnumerableSet for EnumerableSet.AddressSet;
    using ECDSA for bytes32;

    string internal constant ARWEAVE_PREFIX = "https://arweave.net/";
    string internal constant IPFS_PREFIX = "ipfs://";
    address internal _signingAddress;

    uint256 internal constant MAX_UINT_8 = 0xff;
    uint256 internal constant MAX_UINT_32 = 0xffffffff;
    uint256 internal constant MAX_UINT_48 = 0xffffffffffff;
    uint256 internal constant MAX_UINT_56 = 0xffffffffffffff;
    uint256 internal constant MAX_UINT_80 = 0xffffffffffffffffffff;
    uint256 internal constant MAX_UINT_96 = 0xffffffffffffffffffffffff;
    address internal constant ADDRESS_ZERO = 0x0000000000000000000000000000000000000000;

    bool public deprecated;

    // { contractAddress => { instanceId => { walletAddress => UserMintDetails } } }
    mapping(address => mapping(uint256 => mapping(address => UserMintDetails))) internal _mintDetailsPerWallet;

    // Tracks used nonces to prevent replay attacks
    mapping(bytes32 => bool) internal _usedNonces;

    /**
     * @notice This extension is shared, not single-creator. So we must ensure
     * that a claim's initializer is an admin on the creator contract
     * @param creatorContractAddress    the address of the creator contract to check the admin against
     */
    modifier creatorAdminRequired(address creatorContractAddress) {
        AdminControl creatorCoreContract = AdminControl(creatorContractAddress);
        require(creatorCoreContract.isAdmin(msg.sender), "Wallet is not an administrator for contract");
        _;
    }

    constructor(address initialOwner) {
        _transferOwnership(initialOwner);
    }

    /**
     * Admin function to deprecate the contract
     */
    function deprecate(bool _deprecated) external adminRequired {
        deprecated = _deprecated;
    }

    /**
     * See {ISerendipity-setSigner}.
     */
    function setSigner(address signer) external override adminRequired {
        _signingAddress = signer;
    }

    function _validateMintSignature(
        address signingAddress,
        bytes calldata signature,
        bytes32 nonce,
        uint256 expiration
    ) internal view {
        if (signingAddress == address(0)) revert ISerendipityCore.InvalidSignature();
        if (signature.length == 0) revert ISerendipityCore.InvalidInput();
        // Check expiration
        if (block.timestamp > expiration) revert ISerendipityCore.ExpiredSignature();
        // Check nonce hasn't been used
        if (_usedNonces[nonce]) revert ISerendipityCore.CannotReplayTransaction();
    }

    function _checkSignatureAndUpdate(
        address signingAddress,
        ISerendipityCore.ClaimMint[] calldata mints,
        bytes calldata signature,
        bytes32 message,
        bytes32 nonce,
        uint256 expiration
    ) internal {
        // Verify valid message based on input variables
        bytes32 expectedMessage = keccak256(abi.encode(mints, nonce, expiration));
        // The message passed in should be the raw hash, we convert to eth signed message hash for recovery
        bytes32 ethSignedMessage = ECDSA.toEthSignedMessageHash(message);
        address signer = ECDSA.recover(ethSignedMessage, signature);
        if (message != expectedMessage || signer != signingAddress) revert ISerendipityCore.InvalidSignature();
        // Mark nonce as used
        _usedNonces[nonce] = true;
    }

    function _getUserMints(
        address minter,
        address creatorContractAddress,
        uint256 instanceId
    ) internal view returns (UserMintDetails memory) {
        return (_mintDetailsPerWallet[creatorContractAddress][instanceId][minter]);
    }
}
