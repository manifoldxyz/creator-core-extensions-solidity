// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ManifoldPacksSeaDropShim} from "../../contracts/manifoldpacks/ManifoldPacksSeaDropShim.sol";
import {IManifoldPacksSeaDropShim} from "../../contracts/manifoldpacks/IManifoldPacksSeaDropShim.sol";
import {ICreatorExtensionTokenURI} from
    "@manifoldxyz/creator-core-solidity/contracts/extensions/ICreatorExtensionTokenURI.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {ManifoldPacksTestBase} from "./ManifoldPacksTestBase.t.sol";

/**
 * @notice A minimal external metadata resolver implementing
 *         `ICreatorExtensionTokenURI`. Echoes the queried (creator, tokenId)
 *         into a deterministic string so tests can prove the pack delegated to
 *         it verbatim (both arguments are forwarded).
 */
contract MockTokenURIResolver is ICreatorExtensionTokenURI {
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(ICreatorExtensionTokenURI).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }

    function tokenURI(address creator, uint256 tokenId) external pure override returns (string memory) {
        return string(
            abi.encodePacked(
                "resolver://",
                _toHexString(creator),
                "/",
                _toString(tokenId)
            )
        );
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function _toHexString(address account) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes20 data = bytes20(account);
        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(data[i] >> 4)];
            str[3 + i * 2] = alphabet[uint8(data[i] & 0x0f)];
        }
        return string(str);
    }
}

/**
 * @notice A resolver that always reverts — proves delegation actually calls the
 *         external address (a bypassed folder-pattern path would not revert).
 */
contract RevertingTokenURIResolver is ICreatorExtensionTokenURI {
    error ResolverCalled();

    function supportsInterface(bytes4) external pure override returns (bool) {
        return true;
    }

    function tokenURI(address, uint256) external pure override returns (string memory) {
        revert ResolverCalled();
    }
}

/**
 * @title  ManifoldPacksTokenURIExtension
 * @notice Covers the optional external `tokenURIExtension` metadata resolver on
 *         `PackConfig`. When set, card `tokenURI` delegates verbatim to the
 *         external `ICreatorExtensionTokenURI` resolver; when unset (default
 *         `address(0)`) the built-in folder pattern is used. Mirrors
 *         lazy-claim's `StorageProtocol.ADDRESS` delegation.
 */
contract ManifoldPacksTokenURIExtension is ManifoldPacksTestBase {
    string internal constant LOCATION = "ipfs://QmFolder/";

    MockTokenURIResolver internal resolver;
    RevertingTokenURIResolver internal reverting;

    function setUp() public override {
        super.setUp();
        resolver = new MockTokenURIResolver();
        reverting = new RevertingTokenURIResolver();
    }

    /// @notice Default config has no extension -> folder pattern is used.
    function test_defaultUsesFolderPattern() public {
        _setCardsLocation(LOCATION);
        assertEq(
            packs.tokenURI(address(creator), startingCardTokenId),
            string(abi.encodePacked(LOCATION, "1")),
            "default folder pattern"
        );
    }

    /// @notice Setting a non-zero extension delegates verbatim to the resolver,
    ///         forwarding BOTH the creator and the tokenId.
    function test_extensionDelegatesVerbatim() public {
        // A folder location is ALSO set; the extension must take precedence.
        _setCardsLocation(LOCATION);
        _setTokenURIExtension(address(resolver));

        string memory expected = resolver.tokenURI(address(creator), startingCardTokenId);
        assertEq(
            packs.tokenURI(address(creator), startingCardTokenId),
            expected,
            "delegates to external resolver, folder location ignored"
        );
        // Prove the creator argument is actually forwarded (not hardcoded).
        assertEq(
            packs.tokenURI(address(0xBEEF), startingCardTokenId + 5),
            resolver.tokenURI(address(0xBEEF), startingCardTokenId + 5),
            "both args forwarded"
        );
    }

    /// @notice Delegation actually CALLS the external contract (a reverting
    ///         resolver bubbles up — the folder path would never revert).
    function test_extensionIsActuallyCalled() public {
        _setTokenURIExtension(address(reverting));
        vm.expectRevert(RevertingTokenURIResolver.ResolverCalled.selector);
        packs.tokenURI(address(creator), startingCardTokenId);
    }

    /// @notice Clearing the extension back to address(0) restores the folder
    ///         pattern (freely updatable in both directions).
    function test_extensionCanBeClearedBackToFolder() public {
        _setCardsLocation(LOCATION);
        _setTokenURIExtension(address(resolver));
        // Now clear it.
        _setTokenURIExtension(address(0));
        assertEq(
            packs.tokenURI(address(creator), startingCardTokenId),
            string(abi.encodePacked(LOCATION, "1")),
            "folder pattern restored after clearing extension"
        );
    }

    /// @notice The extension survives a round-trip through getConfig/updateConfig
    ///         and is exposed on the public config.
    function test_extensionPersistedInConfig() public {
        _setTokenURIExtension(address(resolver));
        assertEq(
            packs.getConfig().tokenURIExtension,
            address(resolver),
            "extension stored in config"
        );
    }

    // ------------------------------------------------------------------
    // Helper.
    // ------------------------------------------------------------------

    function _setTokenURIExtension(address ext) internal {
        IManifoldPacksSeaDropShim.PackConfig memory cfg = packs.getConfig();
        cfg.tokenURIExtension = ext;
        vm.prank(owner);
        packs.updateConfig(cfg);
    }
}
