// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./OnchainMetadataStoreBase.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC1155Creator.sol";
import "../../contracts/libraries/onchain/LibZip.sol";

/// @dev Gas measurements. Numbers are logged (run with -vv); assertions only check correctness.
contract OnchainMetadataStoreGasTest is OnchainMetadataStoreBase {
    ERC1155Creator public creator;

    function setUp() public {
        store = new OnchainMetadataStore();
        vm.prank(owner);
        creator = new ERC1155Creator("A", "A");
    }

    /// @dev setToken with `data` split in 24576-byte chunks; returns gas used by the call
    function _store(uint256 id, bytes memory data, bool zipped, uint256 rawLength) internal returns (uint256 used) {
        bytes[] memory chunks = _split(data, 24576);
        IOnchainMetadataStore.Options memory o =
            _opts(META, _file("image/svg+xml", rawLength, zipped, false), false);
        vm.prank(owner);
        uint256 g = gasleft();
        store.setToken(address(creator), id, o, chunks, _none());
        used = g - gasleft();
        emit log_named_uint(string(abi.encodePacked("  chunks for id ", _u(id))), chunks.length);
    }

    function _u(uint256 v) private pure returns (string memory) {
        return Strings.toString(v);
    }

    function _render(uint256 id) internal view returns (uint256 used, uint256 uriLen) {
        uint256 g = gasleft();
        string memory uri = store.tokenURI(address(creator), 1, id);
        used = g - gasleft();
        uriLen = bytes(uri).length;
    }

    function _logStore(string memory label, uint256 stored, uint256 used) internal {
        emit log_string(label);
        emit log_named_uint("  stored bytes", stored);
        emit log_named_uint("  setToken gas", used);
    }

    // ---------------------------------------------------------------- store

    function testGasStore24KBRaw() public {
        bytes memory d = _textBlob(24576, 1);
        uint256 used = _store(1, d, false, 0);
        _logStore("STORE 24KB raw", d.length, used);
        assertEq(store.loadRawImage(address(creator), 1), d);
    }

    function testGasStore24KBCompressed() public {
        bytes memory raw = _textBlob(24576, 1);
        bytes memory z = LibZip.flzCompress(raw);
        uint256 used = _store(1, z, true, raw.length);
        _logStore("STORE 24KB-source compressed (FastLZ)", z.length, used);
        assertEq(store.loadRawImage(address(creator), 1), raw);
    }

    function testGasStore100KBRaw() public {
        bytes memory d = _textBlob(100 * 1024, 2);
        uint256 used = _store(1, d, false, 0);
        _logStore("STORE 100KB raw", d.length, used);
        assertEq(store.loadRawImage(address(creator), 1), d);
    }

    function testGasStore100KBCompressed() public {
        bytes memory raw = _textBlob(100 * 1024, 2);
        bytes memory z = LibZip.flzCompress(raw);
        uint256 used = _store(1, z, true, raw.length);
        _logStore("STORE 100KB-source compressed (FastLZ)", z.length, used);
        assertEq(store.loadRawImage(address(creator), 1), raw);
    }

    function testGasStore1MBRawPerChunk() public {
        bytes memory d = _randomBytes(1024 * 1024, 3);
        uint256 used = _store(1, d, false, 0);
        _logStore("STORE 1MB raw", d.length, used);
    }

    // ---------------------------------------------------------------- tokenURI (eth_call) read gas

    function _readCase(string memory label, uint256 size, bool compressed) internal {
        bytes memory raw = _randomBytes(size, size);
        if (compressed) {
            bytes memory z = LibZip.flzCompress(raw);
            _store(1, z, true, raw.length);
            emit log_named_uint("  compressed bytes stored", z.length);
        } else {
            _store(1, raw, false, 0);
        }
        (uint256 used, uint256 len) = _render(1);
        emit log_string(label);
        emit log_named_uint("  image bytes", size);
        emit log_named_uint("  tokenURI gas", used);
        emit log_named_uint("  tokenURI string length", len);
        assertEq(store.loadRawImage(address(creator), 1), raw);
    }

    function testGasRead100KB() public {
        _readCase("READ 100KB raw", 100 * 1024, false);
    }

    function testGasRead500KB() public {
        _readCase("READ 500KB raw", 500 * 1024, false);
    }

    /// @dev the 1 MB read alone needs ~2.04e9 gas, above forge's default 2^30 (1.07e9) test gas limit, so it
    /// only runs when invoked with e.g. `forge test --match-test testGasRead1MB --gas-limit 20000000000 -vv`.
    function testGasRead1MB() public {
        if (gasleft() < 6_000_000_000) {
            emit log_string("READ 1MB raw: SKIPPED (needs --gas-limit 20000000000)");
            return;
        }
        _readCase("READ 1MB raw", 1024 * 1024, false);
    }

    function testGasRead100KBZipped() public {
        _readCase("READ 100KB FastLZ-compressed (random bytes: ~incompressible)", 100 * 1024, true);
    }

    function testGasRead100KBZippedText() public {
        bytes memory raw = _textBlob(100 * 1024, 9);
        bytes memory z = LibZip.flzCompress(raw);
        _store(1, z, true, raw.length);
        (uint256 used, uint256 len) = _render(1);
        emit log_string("READ 100KB FastLZ-compressed text");
        emit log_named_uint("  compressed bytes stored", z.length);
        emit log_named_uint("  tokenURI gas", used);
        emit log_named_uint("  tokenURI string length", len);
        assertEq(store.loadRawImage(address(creator), 1), raw);
    }

    function testGasReadDeflatedFixture() public {
        bytes memory raw = bytes(SVG);
        IOnchainMetadataStore.Options memory o = _opts(META, _file("image/svg+xml", raw.length, false, true), false);
        vm.prank(owner);
        store.setToken(address(creator), 1, o, _one(SVG_DEFLATED), _none());
        (uint256 used, uint256 len) = _render(1);
        emit log_string("READ 1476-byte SVG DEFLATE (343 B stored)");
        emit log_named_uint("  tokenURI gas", used);
        emit log_named_uint("  tokenURI string length", len);
    }
}
