// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC721Creator.sol";
import "@manifoldxyz/creator-core-extensions-solidity/contracts/lazyclaim/ERC721LazyPayableClaim.sol";
import "@manifoldxyz/creator-core-extensions-solidity/contracts/lazyclaim/IERC721LazyPayableClaim.sol";
import "@manifoldxyz/creator-core-extensions-solidity/contracts/lazyclaim/ILazyPayableClaimCore.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "../contracts/ERC721ClaimSecretReveal.sol";
import "../contracts/IERC721ClaimSecretReveal.sol";

contract ERC721ClaimSecretRevealTest is Test {
    using Strings for uint256;

    event Revealed(bytes32 secret);

    address internal owner = address(0xA11CE);
    address internal collector = address(0xC011);
    address internal other = address(0xB0B);
    address payable internal receiver = payable(address(0x5E11));

    uint256 internal constant INSTANCE_ID = 1234;
    uint24 internal constant SUPPLY = 100;
    uint256 internal constant COST = 0.01 ether;
    string internal constant KEY_PREFIX = "key-v1:";

    // Test secret (random, used only here) and its SHA-256
    bytes32 internal constant SECRET = 0xd711c815a6fe15f8c628758a0a3c4c98de3c08081ca75bb769346711f7de8c1d;
    bytes32 internal constant COMMIT = 0xf7662ad1de0218254a94420e9cf9dfdf6d51024e30214dfbb4fb51ed5a8f91ef;

    ERC721Creator internal creator;
    ERC721LazyPayableClaim internal claim;
    ERC721ClaimSecretReveal internal sr;

    // Reference vectors for editions 1, 9, 10, 99, 100, made off-chain:
    //   key  = HMAC-SHA256(SECRET, "key-v1:" + edition) with node:crypto createHmac
    //   hash = keccak256(SECRET ++ uint256(edition)) with cast keccak
    //   payload = base64 of {"hash":"<hash>","editionNumber":<edition>,"key":"<key hex>"} with python base64
    uint256[5] internal editions = [uint256(1), 9, 10, 99, 100];
    bytes32[5] internal keys;
    bytes32[5] internal hashes;
    string[5] internal payloads;

    function setUp() public {
        keys[0] = 0xf887a8f18acf88c28aded7114edf99ad8f066a970e8a53b7921c334385a9a5a8;
        keys[1] = 0x2e2d1b57509362a0c48be14436d0a4c6dd40ba4b0f9817230d284e5c634db16d;
        keys[2] = 0xe2039029c6f798f54f312d12ff3b971f7784db22d6eff7daa19221f7ec28cdac;
        keys[3] = 0x428603f0e71954bb7e32370696420951bf832e077a2dc2c82fa3052c230ffeed;
        keys[4] = 0x322d993020f93d02561fc640e90bd04fa8267539ee6387855add0566d8d1138c;
        hashes[0] = 0xd810e79dc65731a1362dbef796a8980ea2331bfc8b56c0350379dcfc278b08c3;
        hashes[1] = 0x3abafbdf4cb155c9ea28b2de2520fd81fe5433afc74b9778ec75d1bc59c74ce4;
        hashes[2] = 0x19c3347ff54892b9d8aced14a393d707b0317cb1325daef1ea9c365ffc142a4e;
        hashes[3] = 0xf9824ffbcfe64bb8f5e258e839cf30501aac0651bb6b854ef40021b61ea3a90e;
        hashes[4] = 0x87dac95d2d60b7930e02e035390d87631e93179fe3f1c1f7358cc8661ee0fa88;
        payloads[0] =
            "eyJoYXNoIjoiMHhkODEwZTc5ZGM2NTczMWExMzYyZGJlZjc5NmE4OTgwZWEyMzMxYmZjOGI1NmMwMzUwMzc5ZGNmYzI3OGIwOGMzIiwiZWRpdGlvbk51bWJlciI6MSwia2V5IjoiZjg4N2E4ZjE4YWNmODhjMjhhZGVkNzExNGVkZjk5YWQ4ZjA2NmE5NzBlOGE1M2I3OTIxYzMzNDM4NWE5YTVhOCJ9";
        payloads[1] =
            "eyJoYXNoIjoiMHgzYWJhZmJkZjRjYjE1NWM5ZWEyOGIyZGUyNTIwZmQ4MWZlNTQzM2FmYzc0Yjk3NzhlYzc1ZDFiYzU5Yzc0Y2U0IiwiZWRpdGlvbk51bWJlciI6OSwia2V5IjoiMmUyZDFiNTc1MDkzNjJhMGM0OGJlMTQ0MzZkMGE0YzZkZDQwYmE0YjBmOTgxNzIzMGQyODRlNWM2MzRkYjE2ZCJ9";
        payloads[2] =
            "eyJoYXNoIjoiMHgxOWMzMzQ3ZmY1NDg5MmI5ZDhhY2VkMTRhMzkzZDcwN2IwMzE3Y2IxMzI1ZGFlZjFlYTljMzY1ZmZjMTQyYTRlIiwiZWRpdGlvbk51bWJlciI6MTAsImtleSI6ImUyMDM5MDI5YzZmNzk4ZjU0ZjMxMmQxMmZmM2I5NzFmNzc4NGRiMjJkNmVmZjdkYWExOTIyMWY3ZWMyOGNkYWMifQ==";
        payloads[3] =
            "eyJoYXNoIjoiMHhmOTgyNGZmYmNmZTY0YmI4ZjVlMjU4ZTgzOWNmMzA1MDFhYWMwNjUxYmI2Yjg1NGVmNDAwMjFiNjFlYTNhOTBlIiwiZWRpdGlvbk51bWJlciI6OTksImtleSI6IjQyODYwM2YwZTcxOTU0YmI3ZTMyMzcwNjk2NDIwOTUxYmY4MzJlMDc3YTJkYzJjODJmYTMwNTJjMjMwZmZlZWQifQ==";
        payloads[4] =
            "eyJoYXNoIjoiMHg4N2RhYzk1ZDJkNjBiNzkzMGUwMmUwMzUzOTBkODc2MzFlOTMxNzlmZTNmMWMxZjczNThjYzg2NjFlZTBmYTg4IiwiZWRpdGlvbk51bWJlciI6MTAwLCJrZXkiOiIzMjJkOTkzMDIwZjkzZDAyNTYxZmM2NDBlOTBiZDA0ZmE4MjY3NTM5ZWU2Mzg3ODU1YWRkMDU2NmQ4ZDExMzhjIn0=";

        vm.startPrank(owner);
        creator = new ERC721Creator("Token", "NFT");
        claim = new ERC721LazyPayableClaim(owner, address(0xD1), address(0xD2));
        creator.registerExtension(address(claim), "");
        sr = new ERC721ClaimSecretReveal(address(creator), COMMIT, SUPPLY, KEY_PREFIX, _renderer());
        claim.initializeClaim(address(creator), INSTANCE_ID, _claimParameters(bytes32(0)));
        vm.stopPrank();

        vm.deal(collector, 10 ether);
        vm.deal(other, 10 ether);
    }

    // ------------------------------------------------------------------ helpers

    function _renderer() internal pure returns (IERC721ClaimSecretReveal.Renderer memory) {
        return IERC721ClaimSecretReveal.Renderer({
            name: "Piece",
            description: "A generated piece",
            imageURI: "https://arweave.net/cover.png",
            animationURI: "https://arweave.net/generator/index.html"
        });
    }

    /// The claim points at the reveal contract from the start (StorageProtocol.ADDRESS, 20 raw bytes).
    function _claimParameters(bytes32 merkleRoot)
        internal
        view
        returns (IERC721LazyPayableClaim.ClaimParameters memory)
    {
        return IERC721LazyPayableClaim.ClaimParameters({
            totalMax: SUPPLY,
            walletMax: 0,
            startDate: uint48(block.timestamp),
            endDate: 0,
            storageProtocol: ILazyPayableClaimCore.StorageProtocol.ADDRESS,
            identical: false,
            merkleRoot: merkleRoot,
            location: string(abi.encodePacked(address(sr))),
            cost: COST,
            paymentReceiver: receiver,
            erc20: address(0),
            signingAddress: address(0)
        });
    }

    function _coverJSON(uint256 mintOrder) internal pure returns (bytes memory) {
        return abi.encodePacked(
            '{"name":"Piece #',
            mintOrder.toString(),
            '","description":"A generated piece","image":"https://arweave.net/cover.png"'
        );
    }

    function _coverURI(uint256 mintOrder) internal pure returns (string memory) {
        return _dataURI(abi.encodePacked(_coverJSON(mintOrder), "}"));
    }

    function _revealedURI(uint256 mintOrder, string memory payload) internal pure returns (string memory) {
        return _dataURI(
            abi.encodePacked(
                _coverJSON(mintOrder),
                ',"animation_url":"https://arweave.net/generator/index.html?payload=',
                payload,
                '"}'
            )
        );
    }

    function _dataURI(bytes memory json) internal pure returns (string memory) {
        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(json)));
    }

    function _mint(address who) internal {
        uint256 price = COST + claim.MINT_FEE();
        vm.prank(who);
        claim.mint{value: price}(address(creator), INSTANCE_ID, 0, new bytes32[](0), who);
    }

    function _reveal() internal {
        vm.prank(owner);
        sr.reveal(SECRET);
    }

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    // ------------------------------------------------------------------ deploy

    function testConstructorStoresSettings() public view {
        assertEq(sr.CREATOR_CONTRACT(), address(creator));
        assertEq(sr.COMMIT(), COMMIT);
        assertEq(uint256(sr.SUPPLY()), SUPPLY);
        assertEq(sr.keyPrefix(), KEY_PREFIX);
        (string memory name, string memory description, string memory imageURI, string memory animationURI) =
            sr.renderer();
        assertEq(name, "Piece");
        assertEq(description, "A generated piece");
        assertEq(imageURI, "https://arweave.net/cover.png");
        assertEq(animationURI, "https://arweave.net/generator/index.html");
        assertFalse(sr.revealed());
        assertEq(sr.secret(), bytes32(0));
    }

    function testConstructorRejectsZeroSupply() public {
        vm.expectRevert(IERC721ClaimSecretReveal.InvalidSupply.selector);
        new ERC721ClaimSecretReveal(address(creator), COMMIT, 0, KEY_PREFIX, _renderer());
    }

    function testSupportsInterface() public view {
        assertTrue(sr.supportsInterface(type(IERC721LazyPayableClaimMetadata).interfaceId));
        assertTrue(sr.supportsInterface(type(IERC721ClaimSecretReveal).interfaceId));
        assertTrue(sr.supportsInterface(0x01ffc9a7));
        assertFalse(sr.supportsInterface(0xffffffff));
    }

    // ------------------------------------------------------------------ before the reveal

    function testCoverBeforeReveal() public {
        _mint(collector);
        _mint(other);
        assertEq(creator.ownerOf(2), other);
        assertEq(creator.tokenURI(1), _coverURI(1));
        assertEq(creator.tokenURI(2), _coverURI(2));
    }

    function testEditionViewsRevertBeforeReveal() public {
        vm.expectRevert(IERC721ClaimSecretReveal.NotRevealed.selector);
        sr.editionKey(1);
        vm.expectRevert(IERC721ClaimSecretReveal.NotRevealed.selector);
        sr.editionHash(1);
    }

    // ------------------------------------------------------------------ reveal

    function testRevealRequiresCreatorAdmin() public {
        vm.prank(other);
        vm.expectRevert(IERC721ClaimSecretReveal.NotCreatorAdmin.selector);
        sr.reveal(SECRET);
        assertFalse(sr.revealed());
    }

    function testCreatorAdminCanReveal() public {
        vm.prank(owner);
        creator.approveAdmin(other);
        vm.prank(other);
        sr.reveal(SECRET);
        assertTrue(sr.revealed());
    }

    function testRevealRejectsWrongSecret() public {
        vm.startPrank(owner);
        vm.expectRevert(IERC721ClaimSecretReveal.InvalidSecret.selector);
        sr.reveal(bytes32(uint256(SECRET) ^ 1));
        vm.expectRevert(IERC721ClaimSecretReveal.InvalidSecret.selector);
        sr.reveal(COMMIT);
        vm.stopPrank();
        assertFalse(sr.revealed());
        assertEq(sr.secret(), bytes32(0));
    }

    function testRevealOnce() public {
        vm.expectEmit(false, false, false, true, address(sr));
        emit Revealed(SECRET);
        _reveal();
        assertTrue(sr.revealed());
        assertEq(sr.secret(), SECRET);

        vm.prank(owner);
        vm.expectRevert(IERC721ClaimSecretReveal.AlreadyRevealed.selector);
        sr.reveal(SECRET);
    }

    // ------------------------------------------------------------------ after the reveal

    function testKeysMatchReferenceVectors() public {
        _reveal();
        for (uint256 i; i < editions.length; i++) {
            assertEq(sr.editionKey(editions[i]), keys[i], "key");
            assertEq(sr.editionHash(editions[i]), hashes[i], "hash");
        }
    }

    function testRevealedTokenURIMatchesReference() public {
        _reveal();
        for (uint256 i; i < editions.length; i++) {
            assertEq(
                sr.tokenURI(address(creator), editions[i], INSTANCE_ID, uint24(editions[i])),
                _revealedURI(editions[i], payloads[i])
            );
        }
    }

    function testMintedTokensRevealThroughClaim() public {
        _mint(collector);
        _mint(other);
        assertEq(creator.tokenURI(1), _coverURI(1));
        _reveal();
        assertEq(creator.tokenURI(1), _revealedURI(1, payloads[0]));
        // minted after the reveal: revealed straight away
        for (uint256 i = 3; i <= 9; i++) {
            _mint(collector);
        }
        assertEq(creator.tokenURI(9), _revealedURI(9, payloads[1]));
    }

    function testOutOfRangeMintOrderKeepsCover() public {
        _reveal();
        assertEq(sr.tokenURI(address(creator), 0, INSTANCE_ID, 0), _coverURI(0));
        assertEq(sr.tokenURI(address(creator), 101, INSTANCE_ID, SUPPLY + 1), _coverURI(SUPPLY + 1));
        assertEq(sr.tokenURI(address(creator), 100, INSTANCE_ID, SUPPLY), _revealedURI(SUPPLY, payloads[4]));
    }

    /// The payload JSON only uses characters whose base64 never contains '+' or '/'. Checked for every edition.
    function testPayloadIsQuerySafeForEveryEdition() public {
        _reveal();
        for (uint256 n = 1; n <= SUPPLY; n++) {
            bytes memory payload = bytes(
                Base64.encode(
                    abi.encodePacked(
                        '{"hash":"',
                        uint256(sr.editionHash(n)).toHexString(32),
                        '","editionNumber":',
                        n.toString(),
                        ',"key":"',
                        _bare(uint256(sr.editionKey(n)).toHexString(32)),
                        '"}'
                    )
                )
            );
            for (uint256 j; j < payload.length; j++) {
                assertTrue(payload[j] != "+" && payload[j] != "/", "query-unsafe base64");
            }
            // and that is exactly what the contract puts in animation_url
            assertEq(sr.tokenURI(address(creator), n, INSTANCE_ID, uint24(n)), _revealedURI(n, string(payload)));
        }
    }

    function _bare(string memory hex0x) internal pure returns (string memory) {
        bytes memory b = bytes(hex0x);
        bytes memory out = new bytes(b.length - 2);
        for (uint256 i; i < out.length; i++) {
            out[i] = b[i + 2];
        }
        return string(out);
    }

    // ------------------------------------------------------------------ allowlist and airdrop

    function testAllowlistAndAirdropFollowMintOrder() public {
        bytes32 leaf0 = keccak256(abi.encodePacked(collector, uint32(0)));
        bytes32 leaf1 = keccak256(abi.encodePacked(other, uint32(1)));
        bytes32 root = _hashPair(leaf0, leaf1);
        vm.prank(owner);
        claim.initializeClaim(address(creator), 7, _claimParameters(root));

        bytes32[] memory proof0 = new bytes32[](1);
        proof0[0] = leaf1;
        bytes32[] memory proof1 = new bytes32[](1);
        proof1[0] = leaf0;
        uint256 price = COST + claim.MINT_FEE_MERKLE();

        vm.prank(collector);
        claim.mint{value: price}(address(creator), 7, 0, proof0, collector);

        address[] memory recipients = new address[](1);
        recipients[0] = owner;
        uint16[] memory amounts = new uint16[](1);
        amounts[0] = 7;
        vm.prank(owner);
        claim.airdrop(address(creator), 7, recipients, amounts);

        vm.prank(other);
        claim.mint{value: price}(address(creator), 7, 1, proof1, other);

        // mint orders 1 (allowlist), 2-8 (airdrop), 9 (allowlist)
        assertEq(creator.ownerOf(1), collector);
        assertEq(creator.ownerOf(9), other);
        assertEq(creator.tokenURI(9), _coverURI(9));
        _reveal();
        assertEq(creator.tokenURI(1), _revealedURI(1, payloads[0]));
        assertEq(creator.tokenURI(9), _revealedURI(9, payloads[1]));
        // airdropped tokens reveal by their own mint order too
        assertEq(creator.tokenURI(2), sr.tokenURI(address(creator), 2, 7, 2));
        assertTrue(keccak256(bytes(creator.tokenURI(2))) != keccak256(bytes(_coverURI(2))));
    }

    // ------------------------------------------------------------------ gas

    function testGasTokenURI() public {
        _mint(collector);
        uint256 g0 = gasleft();
        creator.tokenURI(1);
        emit log_named_uint("tokenURI gas before reveal", g0 - gasleft());
        _reveal();
        g0 = gasleft();
        creator.tokenURI(1);
        emit log_named_uint("tokenURI gas after reveal", g0 - gasleft());

        vm.prank(owner);
        sr = new ERC721ClaimSecretReveal(address(creator), COMMIT, SUPPLY, KEY_PREFIX, _renderer());
        vm.prank(owner);
        g0 = gasleft();
        sr.reveal(SECRET);
        emit log_named_uint("reveal gas", g0 - gasleft());
    }
}
