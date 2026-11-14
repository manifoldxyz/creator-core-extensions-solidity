// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./OnchainMetadataStoreBase.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC1155Creator.sol";
import "../../contracts/libraries/onchain/LibZip.sol";
import "../../contracts/lazyclaim/IERC1155LazyPayableClaimMetadata.sol";
import "../../contracts/lazyclaim/IERC721LazyPayableClaimMetadata.sol";

contract OnchainMetadataStoreTest is OnchainMetadataStoreBase {
    ERC1155Creator public creatorA;
    ERC1155Creator public creatorB;

    string internal constant ADMIN_MSG = "Wallet is not an administrator for contract";
    string internal constant DNE_MSG = "Token metadata doesn't exist here";

    function setUp() public {
        store = new OnchainMetadataStore();
        vm.prank(owner);
        creatorA = new ERC1155Creator("A", "A");
        vm.prank(other);
        creatorB = new ERC1155Creator("B", "B");
    }

    // ------------------------------------------------------------------ rendering

    function testRawImage() public {
        bytes memory raw = bytes(SVG);
        vm.prank(owner);
        store.setToken(address(creatorA), 1, _rawOpts(META), _one(raw), _none());

        assertEq(store.tokenURI(address(creatorA), 0, 1), _expectedUri(META, "image/svg+xml", raw));
        assertEq(store.loadRawImage(address(creatorA), 1), raw);
        assertEq(store.loadImage(address(creatorA), 1), _expectedImageUri("image/svg+xml", raw));
        (uint256 img, uint256 anim) = store.chunkCounts(address(creatorA), 1);
        assertEq(img, 1);
        assertEq(anim, 0);
    }

    function testTokenURIOverloadsAgreeAndIgnoreTokenIdAndMintOrder() public {
        vm.prank(owner);
        store.setToken(address(creatorA), 1, _rawOpts(META), _one(bytes(SVG)), _none());

        string memory a = store.tokenURI(address(creatorA), 0, 1);
        assertEq(store.tokenURI(address(creatorA), 999, 1), a);
        assertEq(store.tokenURI(address(creatorA), 5, 1, 0), a);
        assertEq(store.tokenURI(address(creatorA), 6, 1, 77), a);
    }

    function testZippedImage() public {
        bytes memory raw = bytes(SVG);
        bytes memory zipped = LibZip.flzCompress(raw);
        assertLt(zipped.length, raw.length);

        vm.prank(owner);
        store.setToken(
            address(creatorA),
            1,
            _opts(META, _file("image/svg+xml", raw.length, true, false), false),
            _one(zipped),
            _none()
        );

        assertEq(store.loadRawImage(address(creatorA), 1), raw);
        assertEq(store.tokenURI(address(creatorA), 1, 1), _expectedUri(META, "image/svg+xml", raw));
    }

    function testDeflatedImageFromPythonZlibFixture() public {
        bytes memory raw = bytes(SVG);
        assertEq(raw.length, 1476);
        assertEq(SVG_DEFLATED.length, 343);

        vm.prank(owner);
        store.setToken(
            address(creatorA),
            1,
            _opts(META, _file("image/svg+xml", raw.length, false, true), false),
            _one(SVG_DEFLATED),
            _none()
        );

        assertEq(store.loadRawImage(address(creatorA), 1), raw);
        assertEq(store.tokenURI(address(creatorA), 1, 1), _expectedUri(META, "image/svg+xml", raw));
    }

    function testZippedWinsOverDeflatedWhenBothFlagsSet() public {
        // `zipped` is checked first, `deflated` only in the else branch
        bytes memory raw = bytes(SVG);
        vm.prank(owner);
        store.setToken(
            address(creatorA),
            1,
            _opts(META, _file("image/svg+xml", raw.length, true, true), false),
            _one(LibZip.flzCompress(raw)),
            _none()
        );
        assertEq(store.loadRawImage(address(creatorA), 1), raw);
    }

    function testWrappedHtml() public {
        bytes memory raw = bytes("<h1>hello</h1>");
        vm.prank(owner);
        store.setToken(address(creatorA), 1, _opts(META, _file("text/html", 0, false, false), true), _one(raw), _none());

        assertEq(store.tokenURI(address(creatorA), 1, 1), _expectedUriWrapped(META, "text/html", raw));
    }

    function testWrappedAndDeflated() public {
        bytes memory raw = bytes(SVG);
        vm.prank(owner);
        store.setToken(
            address(creatorA),
            1,
            _opts(META, _file("image/svg+xml", raw.length, false, true), true),
            _one(SVG_DEFLATED),
            _none()
        );
        assertEq(store.tokenURI(address(creatorA), 1, 1), _expectedUriWrapped(META, "image/svg+xml", raw));
    }

    function testAnimationPresent() public {
        bytes memory raw = bytes(SVG);
        bytes memory anim = bytes("<html><body>animated</body></html>");
        vm.prank(owner);
        store.setToken(
            address(creatorA),
            1,
            _optsAnim(
                META, _file("image/svg+xml", 0, false, false), _file("text/html", 0, false, false), false
            ),
            _one(raw),
            _one(anim)
        );

        assertEq(
            store.tokenURI(address(creatorA), 1, 1),
            _expectedUriWithAnimation(META, "image/svg+xml", raw, "text/html", anim)
        );
        assertEq(store.loadAnimation(address(creatorA), 1), _expectedImageUri("text/html", anim));
        (uint256 img, uint256 animChunks) = store.chunkCounts(address(creatorA), 1);
        assertEq(img, 1);
        assertEq(animChunks, 1);
    }

    function testAnimationTakesPrecedenceOverWrapped() public {
        bytes memory raw = bytes(SVG);
        bytes memory anim = bytes("<html>anim</html>");
        vm.prank(owner);
        store.setToken(
            address(creatorA),
            1,
            _optsAnim(META, _file("image/svg+xml", 0, false, false), _file("text/html", 0, false, false), true),
            _one(raw),
            _one(anim)
        );
        assertEq(
            store.tokenURI(address(creatorA), 1, 1),
            _expectedUriWithAnimation(META, "image/svg+xml", raw, "text/html", anim)
        );
    }

    function testAnimationZippedAndDeflated() public {
        bytes memory raw = bytes(SVG);
        // zipped animation
        vm.prank(owner);
        store.setToken(
            address(creatorA),
            1,
            _optsAnim(
                META,
                _file("image/svg+xml", 0, false, false),
                _file("image/svg+xml", raw.length, true, false),
                false
            ),
            _one(raw),
            _one(LibZip.flzCompress(raw))
        );
        assertEq(
            store.tokenURI(address(creatorA), 1, 1),
            _expectedUriWithAnimation(META, "image/svg+xml", raw, "image/svg+xml", raw)
        );

        // deflated animation
        vm.prank(owner);
        store.setToken(
            address(creatorA),
            2,
            _optsAnim(
                META,
                _file("image/svg+xml", 0, false, false),
                _file("image/svg+xml", raw.length, false, true),
                false
            ),
            _one(raw),
            _one(SVG_DEFLATED)
        );
        assertEq(
            store.tokenURI(address(creatorA), 1, 2),
            _expectedUriWithAnimation(META, "image/svg+xml", raw, "image/svg+xml", raw)
        );
    }

    function testRevertsWhenNoImageChunks() public {
        vm.expectRevert(bytes(DNE_MSG));
        store.tokenURI(address(creatorA), 1, 1);
        vm.expectRevert(bytes(DNE_MSG));
        store.tokenURI(address(creatorA), 1, 1, 1);

        // metadata alone (no image chunks) is still "does not exist"
        vm.prank(owner);
        store.setToken(address(creatorA), 1, _rawOpts(META), _none(), _none());
        vm.expectRevert(bytes(DNE_MSG));
        store.tokenURI(address(creatorA), 1, 1);
    }

    // ------------------------------------------------------------------ keying

    function testInstanceIdKeying() public {
        bytes memory rawA = bytes(SVG);
        bytes memory rawB = bytes("<svg>different</svg>");
        vm.startPrank(owner);
        store.setToken(address(creatorA), 1, _rawOpts('"name": "one"'), _one(rawA), _none());
        store.setToken(address(creatorA), 2, _rawOpts('"name": "two"'), _one(rawB), _none());
        vm.stopPrank();

        assertEq(store.tokenURI(address(creatorA), 1, 1), _expectedUri('"name": "one"', "image/svg+xml", rawA));
        assertEq(store.tokenURI(address(creatorA), 1, 2), _expectedUri('"name": "two"', "image/svg+xml", rawB));
        // an unwritten instance on the same contract does not exist
        vm.expectRevert(bytes(DNE_MSG));
        store.tokenURI(address(creatorA), 1, 3);
    }

    function testContractKeying() public {
        // owner is admin of A only, other is admin of B only
        vm.prank(owner);
        store.setToken(address(creatorA), 1, _rawOpts('"name": "A"'), _one("aaa"), _none());
        vm.prank(other);
        store.setToken(address(creatorB), 1, _rawOpts('"name": "B"'), _one("bbb"), _none());

        assertEq(store.tokenURI(address(creatorA), 1, 1), _expectedUri('"name": "A"', "image/svg+xml", "aaa"));
        assertEq(store.tokenURI(address(creatorB), 1, 1), _expectedUri('"name": "B"', "image/svg+xml", "bbb"));
    }

    // ------------------------------------------------------------------ multi-chunk

    function testMultiChunkSetTokenThenAppendPreservesOrder() public {
        bytes memory raw = _randomBytes(24576 * 3 + 1000, 7);
        bytes[] memory chunks = _split(raw, 24576);
        assertEq(chunks.length, 4);

        bytes[] memory first = new bytes[](2);
        first[0] = chunks[0];
        first[1] = chunks[1];
        bytes[] memory rest = new bytes[](2);
        rest[0] = chunks[2];
        rest[1] = chunks[3];

        vm.startPrank(owner);
        store.setToken(address(creatorA), 1, _rawOpts(META), first, _none());
        (uint256 img,) = store.chunkCounts(address(creatorA), 1);
        assertEq(img, 2);

        store.appendChunks(address(creatorA), 1, rest);
        vm.stopPrank();

        (img,) = store.chunkCounts(address(creatorA), 1);
        assertEq(img, 4);
        assertEq(store.loadRawImage(address(creatorA), 1), raw);
        assertEq(store.tokenURI(address(creatorA), 1, 1), _expectedUri(META, "image/svg+xml", raw));
    }

    function testAppendOneChunkAtATimeResumeUpload() public {
        bytes memory raw = _randomBytes(24576 * 2 + 5, 11);
        bytes[] memory chunks = _split(raw, 24576);
        vm.startPrank(owner);
        store.setToken(address(creatorA), 1, _rawOpts(META), _one(chunks[0]), _none());
        for (uint256 i = 1; i < chunks.length; i++) {
            (uint256 have,) = store.chunkCounts(address(creatorA), 1);
            assertEq(have, i);
            store.appendChunks(address(creatorA), 1, _one(chunks[i]));
        }
        vm.stopPrank();
        assertEq(store.loadRawImage(address(creatorA), 1), raw);
    }

    function testAppendAnimationChunks() public {
        bytes memory anim = _randomBytes(24576 + 10, 3);
        bytes[] memory chunks = _split(anim, 24576);
        vm.startPrank(owner);
        store.setToken(
            address(creatorA),
            1,
            _optsAnim(META, _file("image/png", 0, false, false), _file("text/html", 0, false, false), false),
            _one("img"),
            _one(chunks[0])
        );
        store.appendAnimationChunks(address(creatorA), 1, _one(chunks[1]));
        vm.stopPrank();

        (uint256 img, uint256 animCount) = store.chunkCounts(address(creatorA), 1);
        assertEq(img, 1, "append animation must not touch image chunks");
        assertEq(animCount, 2);
        assertEq(store.loadAnimation(address(creatorA), 1), _expectedImageUri("text/html", anim));
        assertEq(store.loadRawImage(address(creatorA), 1), bytes("img"));
    }

    function testAppendImageDoesNotTouchAnimation() public {
        vm.startPrank(owner);
        store.setToken(
            address(creatorA),
            1,
            _optsAnim(META, _file("image/png", 0, false, false), _file("text/html", 0, false, false), false),
            _one("img1"),
            _one("anim1")
        );
        store.appendChunks(address(creatorA), 1, _one("img2"));
        vm.stopPrank();

        (uint256 img, uint256 anim) = store.chunkCounts(address(creatorA), 1);
        assertEq(img, 2);
        assertEq(anim, 1);
        assertEq(store.loadRawImage(address(creatorA), 1), bytes("img1img2"));
    }

    function testZippedSplitAcrossChunksDecompressesAfterConcat() public {
        bytes memory raw = _textBlob(60000, 5);
        bytes memory zipped = LibZip.flzCompress(raw);
        bytes[] memory chunks = _split(zipped, 1000);
        assertGt(chunks.length, 1);

        vm.prank(owner);
        store.setToken(
            address(creatorA),
            1,
            _opts(META, _file("image/svg+xml", raw.length, true, false), false),
            chunks,
            _none()
        );
        assertEq(store.loadRawImage(address(creatorA), 1), raw);
    }

    // ------------------------------------------------------------------ access control

    function testNonAdminCannotWrite() public {
        vm.startPrank(other2);
        vm.expectRevert(bytes(ADMIN_MSG));
        store.setToken(address(creatorA), 1, _rawOpts(META), _one("x"), _none());
        vm.expectRevert(bytes(ADMIN_MSG));
        store.appendChunks(address(creatorA), 1, _one("x"));
        vm.expectRevert(bytes(ADMIN_MSG));
        store.appendAnimationChunks(address(creatorA), 1, _one("x"));
        vm.stopPrank();
    }

    function testAdminOfOneContractCannotWriteAnother() public {
        // owner administers A, not B
        vm.startPrank(owner);
        vm.expectRevert(bytes(ADMIN_MSG));
        store.setToken(address(creatorB), 1, _rawOpts(META), _one("x"), _none());
        vm.expectRevert(bytes(ADMIN_MSG));
        store.appendChunks(address(creatorB), 1, _one("x"));
        vm.expectRevert(bytes(ADMIN_MSG));
        store.appendAnimationChunks(address(creatorB), 1, _one("x"));
        vm.stopPrank();

        (uint256 img, uint256 anim) = store.chunkCounts(address(creatorB), 1);
        assertEq(img + anim, 0);
    }

    function testApprovedAdminCanWriteAndRevokedCannot() public {
        vm.prank(owner);
        creatorA.approveAdmin(other3);

        vm.prank(other3);
        store.setToken(address(creatorA), 1, _rawOpts(META), _one("x"), _none());

        vm.prank(owner);
        creatorA.revokeAdmin(other3);

        vm.prank(other3);
        vm.expectRevert(bytes(ADMIN_MSG));
        store.appendChunks(address(creatorA), 1, _one("y"));
    }

    function testWriteToNonAdminControlAddressReverts() public {
        // an EOA / non-AdminControl address cannot pass the check
        vm.prank(owner);
        vm.expectRevert();
        store.setToken(other2, 1, _rawOpts(META), _one("x"), _none());
    }

    // ------------------------------------------------------------------ updates

    function testSetTokenReplacesImageChunksAndChangesURI() public {
        vm.startPrank(owner);
        store.setToken(address(creatorA), 1, _rawOpts('"name": "v1"'), _two("aaaa", "bbbb"), _none());
        string memory v1 = store.tokenURI(address(creatorA), 1, 1);
        assertEq(v1, _expectedUri('"name": "v1"', "image/svg+xml", "aaaabbbb"));

        store.setToken(address(creatorA), 1, _rawOpts('"name": "v2"'), _one("cc"), _none());
        vm.stopPrank();

        string memory v2 = store.tokenURI(address(creatorA), 1, 1);
        assertEq(v2, _expectedUri('"name": "v2"', "image/svg+xml", "cc"));
        assertTrue(keccak256(bytes(v1)) != keccak256(bytes(v2)));
        (uint256 img,) = store.chunkCounts(address(creatorA), 1);
        assertEq(img, 1, "old chunks must be deleted");
    }

    function testSetTokenWithEmptyArraysKeepsExistingChunks() public {
        vm.startPrank(owner);
        store.setToken(
            address(creatorA),
            1,
            _optsAnim(META, _file("image/png", 0, false, false), _file("text/html", 0, false, false), false),
            _one("img"),
            _one("anim")
        );
        // metadata-only update
        store.setToken(address(creatorA), 1, _rawOpts('"name": "renamed"'), _none(), _none());
        vm.stopPrank();

        (uint256 img, uint256 anim) = store.chunkCounts(address(creatorA), 1);
        assertEq(img, 1);
        assertEq(anim, 1);
        assertEq(
            store.tokenURI(address(creatorA), 1, 1),
            _expectedUriWithAnimation('"name": "renamed"', "image/svg+xml", "img", "text/html", "anim")
        );
    }

    function testSetTokenReplacesAnimationChunks() public {
        vm.startPrank(owner);
        IOnchainMetadataStore.Options memory o =
            _optsAnim(META, _file("image/png", 0, false, false), _file("text/html", 0, false, false), false);
        store.setToken(address(creatorA), 1, o, _one("img"), _two("a1", "a2"));
        store.setToken(address(creatorA), 1, o, _none(), _one("b1"));
        vm.stopPrank();

        (uint256 img, uint256 anim) = store.chunkCounts(address(creatorA), 1);
        assertEq(img, 1);
        assertEq(anim, 1);
        assertEq(store.loadAnimation(address(creatorA), 1), _expectedImageUri("text/html", "b1"));
    }

    function testEmptyMetadataAndMimeDoNotOverwrite() public {
        vm.startPrank(owner);
        store.setToken(address(creatorA), 1, _opts(META, _file("image/png", 0, false, false), false), _one("x"), _none());
        // empty metadata + empty mime: previous values retained
        store.setToken(address(creatorA), 1, _opts("", _file("", 0, false, false), false), _none(), _none());
        vm.stopPrank();
        assertEq(store.tokenURI(address(creatorA), 1, 1), _expectedUri(META, "image/png", "x"));
    }

    function testSwitchRawToDeflatedViaSetToken() public {
        vm.startPrank(owner);
        store.setToken(address(creatorA), 1, _rawOpts(META), _one("tiny"), _none());
        store.setToken(
            address(creatorA),
            1,
            _opts(META, _file("image/svg+xml", bytes(SVG).length, false, true), false),
            _one(SVG_DEFLATED),
            _none()
        );
        vm.stopPrank();
        assertEq(store.loadRawImage(address(creatorA), 1), bytes(SVG));
    }

    // ------------------------------------------------------------------ events

    function testEventsOnEveryWrite() public {
        vm.startPrank(owner);

        vm.expectEmit(true, true, false, false, address(store));
        emit TokenDataUpdated(address(creatorA), 9);
        store.setToken(address(creatorA), 9, _rawOpts(META), _one("x"), _none());

        vm.expectEmit(true, true, false, false, address(store));
        emit TokenDataUpdated(address(creatorA), 9);
        store.appendChunks(address(creatorA), 9, _one("y"));

        vm.expectEmit(true, true, false, false, address(store));
        emit TokenDataUpdated(address(creatorA), 9);
        store.appendAnimationChunks(address(creatorA), 9, _one("z"));

        vm.stopPrank();
    }

    // ------------------------------------------------------------------ interfaces / misc

    function testSupportsInterface() public {
        assertTrue(store.supportsInterface(type(IERC165).interfaceId));
        assertTrue(store.supportsInterface(type(IERC1155LazyPayableClaimMetadata).interfaceId));
        assertTrue(store.supportsInterface(type(IERC721LazyPayableClaimMetadata).interfaceId));
        assertFalse(store.supportsInterface(0xffffffff));
        assertFalse(store.supportsInterface(0x12345678));
    }

    function testStoreHoldsNoEthAndRejectsEth() public {
        assertEq(address(store).balance, 0);
        vm.deal(owner, 1 ether);
        vm.prank(owner);
        (bool ok,) = address(store).call{value: 1}("");
        assertFalse(ok, "no receive/fallback: plain ETH must be rejected");
        // payable-less write functions reject value
        vm.prank(owner);
        (ok,) = address(store).call{value: 1}(
            abi.encodeWithSelector(store.appendChunks.selector, address(creatorA), 1, _one("x"))
        );
        assertFalse(ok);
        assertEq(address(store).balance, 0);
    }

    function testTokenDataPublicGetter() public {
        bytes memory raw = bytes(SVG);
        vm.prank(owner);
        store.setToken(
            address(creatorA),
            1,
            _opts(META, _file("image/svg+xml", raw.length, false, true), true),
            _one(SVG_DEFLATED),
            _none()
        );
        (
            string memory metadata,
            IOnchainMetadataStore.File memory image,
            IOnchainMetadataStore.File memory animation,
            bool wrapped
        ) = store.tokenData(address(creatorA), 1);
        assertEq(metadata, META);
        assertEq(image.mimeType, "image/svg+xml");
        assertEq(image.length, raw.length);
        assertEq(image.chunks.length, 1);
        assertFalse(image.zipped);
        assertTrue(image.deflated);
        assertEq(animation.chunks.length, 0);
        assertTrue(wrapped);
    }
}
