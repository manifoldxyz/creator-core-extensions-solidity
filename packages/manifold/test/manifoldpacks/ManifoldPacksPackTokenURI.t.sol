// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ManifoldPacksTestBase} from "./ManifoldPacksTestBase.t.sol";

/**
 * @title  ManifoldPacksPackTokenURI
 * @notice Coverage for the PACK-side `tokenURI` (stock ERC721SeaDrop metadata,
 *         NOT overridden by the shim — the shim only overrides the CARD-side
 *         ICreatorExtensionTokenURI surface). Stock behavior:
 *           - empty baseURI            -> returns ""
 *           - baseURI WITHOUT slash    -> returns baseURI verbatim for every id
 *           - baseURI WITH trailing /  -> returns baseURI + tokenId
 *           - nonexistent id           -> reverts URIQueryForNonexistentToken
 *
 *         `setBaseURI` is `_onlyOwnerOrSelf` on ERC721ContractMetadata.
 */
contract ManifoldPacksPackTokenURI is ManifoldPacksTestBase {
    function test_emptyBaseURIReturnsEmpty() public {
        // No baseURI set in setUp -> pack tokenURI is empty.
        assertEq(bytes(packs.tokenURI(1)).length, 0, "empty baseURI -> empty tokenURI");
    }

    function test_baseURIWithoutSlashReturnsFlat() public {
        vm.prank(owner);
        packs.setBaseURI("https://example.pack");

        // No trailing slash -> same URI for every token, id NOT appended.
        assertEq(packs.tokenURI(1), "https://example.pack", "flat URI for token 1");
        assertEq(packs.tokenURI(2), "https://example.pack", "flat URI for token 2");
    }

    function test_baseURIWithSlashAppendsTokenId() public {
        vm.prank(owner);
        packs.setBaseURI("https://example.pack/");

        assertEq(packs.tokenURI(1), "https://example.pack/1", "appends id 1");
        assertEq(packs.tokenURI(2), "https://example.pack/2", "appends id 2");
        assertEq(
            packs.tokenURI(FIXTURE_PACK_COUNT),
            string(abi.encodePacked("https://example.pack/", _toStr(FIXTURE_PACK_COUNT))),
            "appends last fixture id"
        );
    }

    function test_tokenURINonexistentReverts() public {
        vm.prank(owner);
        packs.setBaseURI("https://example.pack/");

        // Token id beyond minted supply does not exist.
        vm.expectRevert();
        packs.tokenURI(FIXTURE_PACK_COUNT + 1);
    }

    function test_setBaseURIOnlyOwner() public {
        vm.prank(collector);
        vm.expectRevert();
        packs.setBaseURI("https://malicious/");
    }

    function test_baseURIUpdatable() public {
        vm.prank(owner);
        packs.setBaseURI("https://old.pack/");
        assertEq(packs.tokenURI(1), "https://old.pack/1", "old base");

        vm.prank(owner);
        packs.setBaseURI("https://new.pack/");
        assertEq(packs.tokenURI(1), "https://new.pack/1", "updated base");
    }

    /// @dev Minimal uint->string for the assertion above.
    function _toStr(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        uint256 j = v;
        uint256 len;
        while (j != 0) { len++; j /= 10; }
        bytes memory b = new bytes(len);
        while (v != 0) { len--; b[len] = bytes1(uint8(48 + v % 10)); v /= 10; }
        return string(b);
    }
}
