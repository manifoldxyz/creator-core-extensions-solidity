// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./OnchainMetadataStoreBase.sol";
import "../../contracts/lazyclaim/ERC1155LazyPayableClaim.sol";
import "../../contracts/lazyclaim/IERC1155LazyPayableClaim.sol";
import "../../contracts/lazyclaim/ERC721LazyPayableClaim.sol";
import "../../contracts/lazyclaim/IERC721LazyPayableClaim.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC1155Creator.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC721Creator.sol";
import "../mocks/delegation-registry/DelegationRegistry.sol";
import "../mocks/delegation-registry/DelegationRegistryV2.sol";
import "../mocks/Mock.sol";
import "../../contracts/libraries/onchain/LibZip.sol";

/// @dev Real claim + creator contracts, claim location = store address (StorageProtocol.ADDRESS)
contract OnchainMetadataStoreIntegrationTest is OnchainMetadataStoreBase {
    ERC1155LazyPayableClaim public claim1155;
    ERC721LazyPayableClaim public claim721;
    ERC1155Creator public creator1155;
    ERC721Creator public creator721;
    DelegationRegistry public delegationRegistry;
    DelegationRegistryV2 public delegationRegistryV2;
    MockManifoldMembership public manifoldMembership;

    function setUp() public {
        store = new OnchainMetadataStore();

        vm.startPrank(owner);
        creator1155 = new ERC1155Creator("Token", "NFT");
        creator721 = new ERC721Creator("Token", "NFT");
        delegationRegistry = new DelegationRegistry();
        delegationRegistryV2 = new DelegationRegistryV2();
        manifoldMembership = new MockManifoldMembership();

        claim1155 = new ERC1155LazyPayableClaim(owner, address(delegationRegistry), address(delegationRegistryV2));
        claim1155.setMembershipAddress(address(manifoldMembership));
        creator1155.registerExtension(address(claim1155), "override");

        claim721 = new ERC721LazyPayableClaim(owner, address(delegationRegistry), address(delegationRegistryV2));
        claim721.setMembershipAddress(address(manifoldMembership));
        creator721.registerExtension(address(claim721), "override");

        vm.deal(owner, 10 ether);
        vm.deal(other, 10 ether);
        vm.deal(other2, 10 ether);
        vm.deal(other3, 10 ether);
        vm.stopPrank();
    }

    // ------------------------------------------------------------------ helpers

    function _init1155(uint256 instanceId, uint32 totalMax, uint32 walletMax) internal {
        IERC1155LazyPayableClaim.ClaimParameters memory p = IERC1155LazyPayableClaim.ClaimParameters({
            merkleRoot: "",
            location: string(abi.encodePacked(address(store))),
            totalMax: totalMax,
            walletMax: walletMax,
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + 1000),
            storageProtocol: ILazyPayableClaimCore.StorageProtocol.ADDRESS,
            cost: 1,
            paymentReceiver: payable(owner),
            erc20: address(0),
            signingAddress: address(0)
        });
        vm.prank(owner);
        claim1155.initializeClaim(address(creator1155), instanceId, p);
    }

    function _init721(uint256 instanceId, uint32 totalMax, uint32 walletMax) internal {
        IERC721LazyPayableClaim.ClaimParameters memory p = IERC721LazyPayableClaim.ClaimParameters({
            totalMax: totalMax,
            walletMax: walletMax,
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + 1000),
            storageProtocol: ILazyPayableClaimCore.StorageProtocol.ADDRESS,
            identical: true,
            merkleRoot: "",
            location: string(abi.encodePacked(address(store))),
            cost: 1,
            paymentReceiver: payable(owner),
            erc20: address(0),
            signingAddress: address(0)
        });
        vm.prank(owner);
        claim721.initializeClaim(address(creator721), instanceId, p);
    }

    function _mint1155(address minter, uint256 instanceId) internal {
        bytes32[] memory proof = new bytes32[](0);
        uint256 fee = claim1155.MINT_FEE();
        vm.prank(minter);
        claim1155.mint{value: fee + 1}(address(creator1155), instanceId, 0, proof, minter);
    }

    function _mint721(address minter, uint256 instanceId) internal {
        bytes32[] memory proof = new bytes32[](0);
        uint256 fee = claim721.MINT_FEE();
        vm.prank(minter);
        claim721.mint{value: fee + 1}(address(creator721), instanceId, 0, proof, minter);
    }

    // ------------------------------------------------------------------ 1155 edition

    function testEdition1155() public {
        bytes memory raw = bytes(SVG);
        _init1155(1, 10, 0);
        vm.prank(owner);
        store.setToken(address(creator1155), 1, _rawOpts(META), _one(raw), _none());

        _mint1155(other, 1);
        _mint1155(other2, 1);
        _mint1155(other2, 1);

        string memory expected = _expectedUri(META, "image/svg+xml", raw);
        assertEq(creator1155.balanceOf(other, 1), 1);
        assertEq(creator1155.balanceOf(other2, 1), 2);
        assertEq(creator1155.uri(1), expected);
        assertEq(creator1155.uri(1), store.tokenURI(address(creator1155), 1, 1));
        assertEq(store.loadRawImage(address(creator1155), 1), raw);
    }

    function testEdition1155UpdateAfterMintChangesURI() public {
        bytes memory raw = bytes(SVG);
        _init1155(1, 10, 0);
        vm.prank(owner);
        store.setToken(address(creator1155), 1, _rawOpts('"name": "v1"'), _one(raw), _none());
        _mint1155(other, 1);
        assertEq(creator1155.uri(1), _expectedUri('"name": "v1"', "image/svg+xml", raw));

        vm.prank(owner);
        store.setToken(address(creator1155), 1, _rawOpts('"name": "v2"'), _one("new art"), _none());
        assertEq(creator1155.uri(1), _expectedUri('"name": "v2"', "image/svg+xml", "new art"));
    }

    function testEdition1155DeflatedViaClaim() public {
        bytes memory raw = bytes(SVG);
        _init1155(1, 10, 0);
        vm.prank(owner);
        store.setToken(
            address(creator1155),
            1,
            _opts(META, _file("image/svg+xml", raw.length, false, true), false),
            _one(SVG_DEFLATED),
            _none()
        );
        _mint1155(other, 1);
        assertEq(creator1155.uri(1), _expectedUri(META, "image/svg+xml", raw));
    }

    function testTwoInstancesOnOne1155ContractGetOwnArt() public {
        _init1155(1, 10, 0);
        _init1155(2, 10, 0);
        vm.startPrank(owner);
        store.setToken(address(creator1155), 1, _rawOpts('"name": "one"'), _one("art-one"), _none());
        store.setToken(address(creator1155), 2, _rawOpts('"name": "two"'), _one("art-two"), _none());
        vm.stopPrank();
        _mint1155(other, 1);
        _mint1155(other, 2);

        // claim mints token ids 1 and 2 in order of first mint
        assertEq(creator1155.uri(1), _expectedUri('"name": "one"', "image/svg+xml", "art-one"));
        assertEq(creator1155.uri(2), _expectedUri('"name": "two"', "image/svg+xml", "art-two"));
    }

    // ------------------------------------------------------------------ 1155 1/1

    function testOneOfOne1155() public {
        bytes memory raw = bytes(SVG);
        _init1155(1, 1, 0);
        vm.prank(owner);
        store.setToken(address(creator1155), 1, _rawOpts(META), _one(raw), _none());

        _mint1155(other, 1);
        assertEq(creator1155.balanceOf(other, 1), 1);
        assertEq(creator1155.uri(1), _expectedUri(META, "image/svg+xml", raw));

        // supply 1: a second mint is refused by the claim
        bytes32[] memory proof = new bytes32[](0);
        uint256 fee = claim1155.MINT_FEE();
        vm.prank(other2);
        vm.expectRevert(ILazyPayableClaimCore.TooManyRequested.selector);
        claim1155.mint{value: fee + 1}(address(creator1155), 1, 0, proof, other2);
    }

    // ------------------------------------------------------------------ 721

    function testClaim721SeveralMintsShareArt() public {
        bytes memory raw = bytes(SVG);
        _init721(1, 10, 0);
        vm.prank(owner);
        store.setToken(address(creator721), 1, _rawOpts(META), _one(raw), _none());

        _mint721(other, 1);
        _mint721(other2, 1);
        _mint721(other3, 1);
        _mint721(other, 1);

        string memory expected = _expectedUri(META, "image/svg+xml", raw);
        for (uint256 t = 1; t <= 4; t++) {
            assertEq(creator721.tokenURI(t), expected);
            assertEq(creator721.tokenURI(t), store.tokenURI(address(creator721), t, 1, uint24(t)));
        }
        assertEq(creator721.ownerOf(1), other);
        assertEq(creator721.ownerOf(2), other2);
        assertEq(creator721.ownerOf(3), other3);
        assertEq(creator721.ownerOf(4), other);
        assertEq(store.loadRawImage(address(creator721), 1), raw);
    }

    function testClaim721ZippedAndWrapped() public {
        bytes memory raw = bytes("<h1>on chain html</h1>");
        _init721(1, 10, 0);
        vm.prank(owner);
        store.setToken(
            address(creator721),
            1,
            _opts(META, _file("text/html", raw.length, true, false), true),
            _one(LibZip.flzCompress(raw)),
            _none()
        );
        _mint721(other, 1);
        assertEq(creator721.tokenURI(1), _expectedUriWrapped(META, "text/html", raw));
    }

    function testClaim721UpdateAfterMintChangesURIForAllTokens() public {
        _init721(1, 10, 0);
        vm.prank(owner);
        store.setToken(address(creator721), 1, _rawOpts('"name": "v1"'), _one("old"), _none());
        _mint721(other, 1);
        _mint721(other2, 1);

        vm.prank(owner);
        store.setToken(address(creator721), 1, _rawOpts('"name": "v2"'), _one("new"), _none());
        assertEq(creator721.tokenURI(1), _expectedUri('"name": "v2"', "image/svg+xml", "new"));
        assertEq(creator721.tokenURI(2), _expectedUri('"name": "v2"', "image/svg+xml", "new"));
    }

    function testOneOfOne721() public {
        bytes memory raw = bytes(SVG);
        _init721(1, 1, 0);
        vm.prank(owner);
        store.setToken(address(creator721), 1, _rawOpts(META), _one(raw), _none());

        _mint721(other, 1);
        assertEq(creator721.ownerOf(1), other);
        assertEq(creator721.tokenURI(1), _expectedUri(META, "image/svg+xml", raw));

        bytes32[] memory proof = new bytes32[](0);
        uint256 fee = claim721.MINT_FEE();
        vm.prank(other2);
        vm.expectRevert(ILazyPayableClaimCore.TooManyRequested.selector);
        claim721.mint{value: fee + 1}(address(creator721), 1, 0, proof, other2);
    }

    function testClaim721MultiChunkViaClaim() public {
        bytes memory raw = _randomBytes(24576 * 2 + 17, 21);
        bytes[] memory chunks = _split(raw, 24576);
        _init721(1, 10, 0);
        vm.startPrank(owner);
        store.setToken(address(creator721), 1, _rawOpts(META), _one(chunks[0]), _none());
        store.appendChunks(address(creator721), 1, _two(chunks[1], chunks[2]));
        vm.stopPrank();
        _mint721(other, 1);
        assertEq(creator721.tokenURI(1), _expectedUri(META, "image/svg+xml", raw));
    }

    // ------------------------------------------------------------------ claim-before-art

    function testTokenURIRevertsUntilArtStored() public {
        _init1155(1, 10, 0);
        _mint1155(other, 1);
        vm.expectRevert(bytes("Token metadata doesn't exist here"));
        creator1155.uri(1);

        vm.prank(owner);
        store.setToken(address(creator1155), 1, _rawOpts(META), _one("late"), _none());
        assertEq(creator1155.uri(1), _expectedUri(META, "image/svg+xml", "late"));
    }

    function testTwoInstancesOnOne721ContractGetOwnArt() public {
        _init721(3, 10, 0);
        _init721(7, 10, 0);
        vm.startPrank(owner);
        store.setToken(address(creator721), 3, _rawOpts('"name": "three"'), _one("art-three"), _none());
        store.setToken(address(creator721), 7, _rawOpts('"name": "seven"'), _one("art-seven"), _none());
        vm.stopPrank();

        _mint721(other, 7); // token 1 -> instance 7
        _mint721(other, 3); // token 2 -> instance 3
        _mint721(other2, 7); // token 3 -> instance 7

        assertEq(creator721.tokenURI(1), _expectedUri('"name": "seven"', "image/svg+xml", "art-seven"));
        assertEq(creator721.tokenURI(2), _expectedUri('"name": "three"', "image/svg+xml", "art-three"));
        assertEq(creator721.tokenURI(3), _expectedUri('"name": "seven"', "image/svg+xml", "art-seven"));
    }
}
