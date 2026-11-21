// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../../contracts/onchainmetadata/OnchainMetadataStore.sol";
import "../../contracts/onchainmetadata/IOnchainMetadataStore.sol";

/// @dev shared helpers: option builders, fixtures and independent expected-URI construction (reference base64 below)
abstract contract OnchainMetadataStoreBase is Test {
    OnchainMetadataStore public store;

    address public owner = 0x6140F00e4Ff3936702E68744f2b5978885464cbB;
    address public other = 0xc78Dc443c126af6E4f6Ed540c1e740C1b5be09cd;
    address public other2 = 0x80AAC46bbd3C2FcE33681541a52CacBEd14bF425;
    address public other3 = 0x5174cD462b60c536eb51D4ceC1D561D3Ea31004F;

    // mirrored from IOnchainMetadataStore (emit Iface.Event is unsupported in solc 0.8.17)
    event TokenDataUpdated(address indexed creatorContract, uint256 indexed instanceId);

    string internal constant META = '"name": "Piece", "description": "On chain"';

    // 1476-byte SVG and its raw DEFLATE stream (python zlib.compressobj(9, DEFLATED, -15)), 343 bytes
    string internal constant SVG =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect x="0" y="0" width="10" height="10" fill="#000000"/><rect x="7" y="13" width="10" height="10" fill="#009e37"/><rect x="14" y="26" width="10" height="10" fill="#013c6e"/><rect x="21" y="39" width="10" height="10" fill="#01daa5"/><rect x="28" y="52" width="10" height="10" fill="#0278dc"/><rect x="35" y="65" width="10" height="10" fill="#031713"/><rect x="42" y="78" width="10" height="10" fill="#03b54a"/><rect x="49" y="1" width="10" height="10" fill="#045381"/><rect x="56" y="14" width="10" height="10" fill="#04f1b8"/><rect x="63" y="27" width="10" height="10" fill="#058fef"/><rect x="70" y="40" width="10" height="10" fill="#062e26"/><rect x="77" y="53" width="10" height="10" fill="#06cc5d"/><rect x="84" y="66" width="10" height="10" fill="#076a94"/><rect x="1" y="79" width="10" height="10" fill="#0808cb"/><rect x="8" y="2" width="10" height="10" fill="#08a702"/><rect x="15" y="15" width="10" height="10" fill="#094539"/><rect x="22" y="28" width="10" height="10" fill="#09e370"/><rect x="29" y="41" width="10" height="10" fill="#0a81a7"/><rect x="36" y="54" width="10" height="10" fill="#0b1fde"/><rect x="43" y="67" width="10" height="10" fill="#0bbe15"/><rect x="50" y="80" width="10" height="10" fill="#0c5c4c"/><rect x="57" y="3" width="10" height="10" fill="#0cfa83"/><rect x="64" y="16" width="10" height="10" fill="#0d98ba"/><rect x="71" y="29" width="10" height="10" fill="#0e36f1"/></svg>';
    bytes internal constant SVG_DEFLATED =
        hex"85d4cd8e832010c0f15731ecbdf235809bdac3be092054936ebb694dedbefd5ae6b0701a138d31fe6202fff1f8789ebbd7f7e5fa18d9bcae3f9f7dbf6ddb615387dbfddc4bce79bfbfc1bae792b6afdb6b64bce39de0e564a7e33dc5b57b3f65dd6fb96ecbb4ce2313fbed9c96f3bce27d5e2e97917df072b0fe1fda0285a2e59094ada5d0854a4352a1a2493595a25035d074f21e1aea0a05495269dd146baaa050032455c2ee2b52512d0bb58ea601b46fe8802b4c4a0dca895a8241a9699a457035350af7c692145c4eb9090253d2744b46a67df36b8a31011d938911a69a3a8cc9d03159e307dd74885b43b7e4b88ba1f9282e120dbde5b2f9249624e892867d5787a65f2c49d225bde7ad19558925693a25ef846f6655614a40a714449e9a59d59892a1530a21896656015372744a11a26e66153025baa498bd6b46d56049822e691a5c6846d5624a924e292993cbacbe7fcea73f";

    // ---------------------------------------------------------------- builders

    function _file(string memory mime, uint256 length, bool zipped, bool deflated)
        internal
        pure
        returns (IOnchainMetadataStore.File memory f)
    {
        f.mimeType = mime;
        f.length = length;
        f.zipped = zipped;
        f.deflated = deflated;
    }

    function _opts(string memory meta, IOnchainMetadataStore.File memory image, bool wrapped)
        internal
        pure
        returns (IOnchainMetadataStore.Options memory o)
    {
        o.metadata = meta;
        o.image = image;
        o.wrapped = wrapped;
    }

    function _optsAnim(
        string memory meta,
        IOnchainMetadataStore.File memory image,
        IOnchainMetadataStore.File memory animation,
        bool wrapped
    ) internal pure returns (IOnchainMetadataStore.Options memory o) {
        o.metadata = meta;
        o.image = image;
        o.animation = animation;
        o.wrapped = wrapped;
    }

    function _rawOpts(string memory meta) internal pure returns (IOnchainMetadataStore.Options memory) {
        return _opts(meta, _file("image/svg+xml", 0, false, false), false);
    }

    function _one(bytes memory a) internal pure returns (bytes[] memory arr) {
        arr = new bytes[](1);
        arr[0] = a;
    }

    function _two(bytes memory a, bytes memory b) internal pure returns (bytes[] memory arr) {
        arr = new bytes[](2);
        arr[0] = a;
        arr[1] = b;
    }

    function _none() internal pure returns (bytes[] memory) {
        return new bytes[](0);
    }

    // ---------------------------------------------------------------- expected output (independent of store code)

    /// @dev plain byte-by-byte RFC 4648 base64 (no assembly). OZ 4.8.1 Base64 reads dirty memory past the
    /// end of `data`, so it is not usable as an oracle on test-generated buffers.
    function _b64(bytes memory data) internal pure returns (string memory) {
        bytes memory tbl = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        uint256 n = data.length;
        bytes memory out = new bytes(((n + 2) / 3) * 4);
        uint256 o;
        for (uint256 i = 0; i < n; i += 3) {
            uint256 b0 = uint8(data[i]);
            uint256 b1 = i + 1 < n ? uint8(data[i + 1]) : 0;
            uint256 b2 = i + 2 < n ? uint8(data[i + 2]) : 0;
            out[o++] = tbl[b0 >> 2];
            out[o++] = tbl[((b0 & 3) << 4) | (b1 >> 4)];
            out[o++] = i + 1 < n ? tbl[((b1 & 15) << 2) | (b2 >> 6)] : bytes1("=");
            out[o++] = i + 2 < n ? tbl[b2 & 63] : bytes1("=");
        }
        return string(out);
    }

    function _expectedImageUri(string memory mime, bytes memory raw) internal pure returns (string memory) {
        return string(abi.encodePacked("data:", mime, ";base64,", _b64(raw)));
    }

    function _expectedUri(string memory meta, string memory mime, bytes memory raw)
        internal
        pure
        returns (string memory)
    {
        return string(
            abi.encodePacked("data:application/json;utf8,{", meta, ', "image": "', _expectedImageUri(mime, raw), '"}')
        );
    }

    function _expectedUriWithAnimation(
        string memory meta,
        string memory mime,
        bytes memory raw,
        string memory animMime,
        bytes memory animRaw
    ) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                "data:application/json;utf8,{",
                meta,
                ', "image": "',
                _expectedImageUri(mime, raw),
                '"',
                ',"animation_url": "',
                _expectedImageUri(animMime, animRaw),
                '"}'
            )
        );
    }

    function _expectedUriWrapped(string memory meta, string memory mime, bytes memory raw)
        internal
        pure
        returns (string memory)
    {
        bytes memory html = abi.encodePacked("<!DOCTYPE HTML>\n\n<html>\n<body>\n", raw, "</body>\n</html>\n");
        return string(
            abi.encodePacked(
                "data:application/json;utf8,{",
                meta,
                ', "image": "',
                _expectedImageUri(mime, raw),
                '"',
                ',"animation_url": "data:text/html;base64,',
                _b64(html),
                '"}'
            )
        );
    }

    // ---------------------------------------------------------------- data generators

    /// @dev pseudo-random (incompressible) bytes
    function _randomBytes(uint256 n, uint256 seed) internal pure returns (bytes memory b) {
        b = new bytes(n + 32);
        for (uint256 i = 0; i < n; i += 32) {
            bytes32 w = keccak256(abi.encode(seed, i));
            assembly {
                mstore(add(add(b, 32), i), w)
            }
        }
        assembly {
            mstore(b, n)
        }
    }

    /// @dev svg-like text with pseudo-random coordinates/colours (compressible, not trivially repetitive)
    function _textBlob(uint256 n, uint256 seed) internal pure returns (bytes memory b) {
        bytes memory acc = new bytes(0);
        bytes memory buf = new bytes(0);
        uint256 i;
        // build in 4 KB pieces to keep abi.encodePacked copies bounded
        while (acc.length < n) {
            buf = new bytes(0);
            for (uint256 k; k < 64 && acc.length + buf.length < n; k++) {
                uint256 h = uint256(keccak256(abi.encode(seed, i++)));
                buf = abi.encodePacked(
                    buf, '<rect x="', _dec2(h), '" y="', _dec2(h >> 8), '" width="10" height="10" fill="#', _hex6(h >> 16), '"/>'
                );
            }
            acc = abi.encodePacked(acc, buf);
        }
        b = new bytes(n);
        for (uint256 j; j < n; j++) {
            b[j] = acc[j];
        }
    }

    function _dec2(uint256 v) private pure returns (bytes memory r) {
        r = new bytes(2);
        r[0] = bytes1(uint8(48 + (v % 100) / 10));
        r[1] = bytes1(uint8(48 + v % 10));
    }

    function _hex6(uint256 v) private pure returns (bytes memory r) {
        bytes16 digits = "0123456789abcdef";
        r = new bytes(6);
        for (uint256 i; i < 6; i++) {
            r[5 - i] = digits[v & 0xf];
            v >>= 4;
        }
    }

    function _split(bytes memory data, uint256 chunkSize) internal pure returns (bytes[] memory chunks) {
        uint256 n = (data.length + chunkSize - 1) / chunkSize;
        chunks = new bytes[](n);
        for (uint256 i; i < n; i++) {
            uint256 start = i * chunkSize;
            uint256 end = start + chunkSize > data.length ? data.length : start + chunkSize;
            bytes memory c = new bytes(end - start);
            for (uint256 j; j < c.length; j++) {
                c[j] = data[start + j];
            }
            chunks[i] = c;
        }
    }
}
