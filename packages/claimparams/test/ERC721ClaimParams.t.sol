// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC721Creator.sol";
import "@manifoldxyz/creator-core-solidity/contracts/core/IERC721CreatorCore.sol";
import "@manifoldxyz/creator-core-extensions-solidity/contracts/lazyclaim/ERC721LazyPayableClaim.sol";
import "@manifoldxyz/creator-core-extensions-solidity/contracts/lazyclaim/IERC721LazyPayableClaim.sol";
import "@manifoldxyz/creator-core-extensions-solidity/contracts/lazyclaim/ILazyPayableClaimCore.sol";
import "@manifoldxyz/creator-core-extensions-solidity/contracts/lazyUpdatableFeeClaim/ERC721LazyPayableClaimV2.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "../contracts/ERC721ClaimParams.sol";
import "../contracts/IERC721ClaimParams.sol";

/// @dev Minter contract that tries to mint again, or to set params, from onERC721Received.
contract ReentrantMinter is IERC721Receiver {
    ERC721ClaimParams public target;
    uint8 public mode; // 0 = none, 1 = re-enter mint, 2 = re-enter setParams
    bool public reentryReverted;
    bytes public reentryParams;

    constructor(ERC721ClaimParams target_) {
        target = target_;
    }

    function setMode(uint8 mode_, bytes calldata params) external {
        mode = mode_;
        reentryParams = params;
    }

    function mint(bytes calldata params) external payable {
        target.mint{value: msg.value}(params, 0, new bytes32[](0));
    }

    function onERC721Received(address, address, uint256 tokenId, bytes calldata) external override returns (bytes4) {
        uint8 m = mode;
        mode = 0;
        if (m == 1) {
            uint256 price = target.mintPrice();
            try target.mint{value: price}(reentryParams, 0, new bytes32[](0)) {}
            catch {
                reentryReverted = true;
            }
        } else if (m == 2) {
            try target.setParams(tokenId, reentryParams) {}
            catch {
                reentryReverted = true;
            }
        }
        return this.onERC721Received.selector;
    }

    receive() external payable {}
}

/// @dev Another extension on the same creator contract, minting with the same tokenData shape.
contract OtherExtension {
    function mint(address creator, address to, uint80 data) external returns (uint256) {
        return IERC721CreatorCore(creator).mintExtension(to, data);
    }
}

contract ERC721ClaimParamsTest is Test {
    using Strings for uint256;

    event RendererUpdated();
    event RendererLocked();
    event ParamsSet(uint24 indexed mintOrder, bytes params);

    address internal owner = address(0xA11CE);
    address internal collector = address(0xC011);
    address internal other = address(0xB0B);
    address payable internal receiver = payable(address(0x5E11));

    uint256 internal constant INSTANCE_ID = 1234;
    uint16 internal constant PARAMS_LENGTH = 64;
    uint256 internal constant COST = 0.01 ether;

    ERC721Creator internal creator;
    ERC721LazyPayableClaim internal claim;
    ERC721ClaimParams internal cp;

    function setUp() public {
        vm.startPrank(owner);
        creator = new ERC721Creator("Token", "NFT");
        claim = new ERC721LazyPayableClaim(owner, address(0xD1), address(0xD2));
        creator.registerExtension(address(claim), "");
        vm.stopPrank();

        cp = _setUpClaim(address(claim), INSTANCE_ID, bytes32(0), 0, 0);

        vm.deal(collector, 10 ether);
        vm.deal(other, 10 ether);
    }

    // ------------------------------------------------------------------ helpers

    function _claimParameters(bytes32 merkleRoot, uint32 walletMax, uint32 totalMax)
        internal
        view
        returns (IERC721LazyPayableClaim.ClaimParameters memory)
    {
        return IERC721LazyPayableClaim.ClaimParameters({
            totalMax: totalMax,
            walletMax: walletMax,
            startDate: uint48(block.timestamp),
            endDate: 0,
            storageProtocol: ILazyPayableClaimCore.StorageProtocol.ARWEAVE,
            identical: true,
            merkleRoot: merkleRoot,
            location: "placeholder",
            cost: COST,
            paymentReceiver: receiver,
            erc20: address(0),
            signingAddress: address(0)
        });
    }

    /// Initialize a claim, deploy a params contract for it, set the renderer and point the claim at it.
    function _setUpClaim(
        address claimAddress,
        uint256 instanceId,
        bytes32 merkleRoot,
        uint32 walletMax,
        uint32 totalMax
    ) internal returns (ERC721ClaimParams params) {
        vm.startPrank(owner);
        IERC721LazyPayableClaim(claimAddress)
            .initializeClaim(address(creator), instanceId, _claimParameters(merkleRoot, walletMax, totalMax));
        params = new ERC721ClaimParams(claimAddress, address(creator), instanceId, PARAMS_LENGTH);
        params.setRenderer(_renderer());
        IERC721LazyPayableClaim(claimAddress)
            .updateTokenURIParams(
                address(creator),
                instanceId,
                ILazyPayableClaimCore.StorageProtocol.ADDRESS,
                false,
                string(abi.encodePacked(address(params)))
            );
        vm.stopPrank();
    }

    function _renderer() internal pure returns (IERC721ClaimParams.Renderer memory) {
        return IERC721ClaimParams.Renderer({
            name: "Piece",
            description: "A configurable piece",
            imageURI: "https://arweave.net/preview.png",
            animationURI: "https://arweave.net/renderer/index.html"
        });
    }

    function _params(uint8 seed) internal pure returns (bytes memory p) {
        p = new bytes(PARAMS_LENGTH);
        for (uint256 i; i < PARAMS_LENGTH; i++) {
            p[i] = bytes1(uint8(seed + i));
        }
    }

    function _hex(bytes memory data) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory out = new bytes(2 + data.length * 2);
        out[0] = "0";
        out[1] = "x";
        for (uint256 i; i < data.length; i++) {
            out[2 + i * 2] = alphabet[uint8(data[i]) >> 4];
            out[3 + i * 2] = alphabet[uint8(data[i]) & 0x0f];
        }
        return string(out);
    }

    function _expectedURI(uint256 mintOrder, bytes memory p) internal pure returns (string memory) {
        string memory order = mintOrder.toString();
        bytes memory json = abi.encodePacked(
            '{"name":"Piece #',
            order,
            '","description":"A configurable piece","image":"https://arweave.net/preview.png",',
            '"animation_url":"https://arweave.net/renderer/index.html?params=',
            _hex(p),
            "&mintOrder=",
            order,
            '"}'
        );
        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(json)));
    }

    function _mint(address who, bytes memory p) internal {
        uint256 price = cp.mintPrice();
        vm.prank(who);
        cp.mint{value: price}(p, 0, new bytes32[](0));
    }

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    // ------------------------------------------------------------------ mint

    function testMintStoresParams() public {
        bytes memory p = _params(1);
        uint256 price = cp.mintPrice();
        assertEq(price, COST + claim.MINT_FEE());

        vm.expectEmit(true, false, false, true, address(cp));
        emit ParamsSet(1, p);
        vm.prank(collector);
        cp.mint{value: price}(p, 0, new bytes32[](0));

        assertEq(creator.ownerOf(1), collector);
        assertEq(cp.getParams(1), p);
        assertEq(creator.tokenURI(1), _expectedURI(1, p));
        assertEq(address(cp).balance, 0);
        assertEq(receiver.balance, COST);
        assertEq(address(claim).balance, claim.MINT_FEE());
    }

    function testSequentialMintsUseMintOrder() public {
        bytes memory p1 = _params(1);
        bytes memory p2 = _params(2);
        _mint(collector, p1);
        _mint(other, p2);
        assertEq(creator.ownerOf(2), other);
        assertEq(cp.getParams(1), p1);
        assertEq(cp.getParams(2), p2);
        assertEq(creator.tokenURI(2), _expectedURI(2, p2));
    }

    function testExactPrice() public {
        bytes memory p = _params(1);
        uint256 price = cp.mintPrice();

        vm.startPrank(collector);
        vm.expectRevert(IERC721ClaimParams.InvalidPayment.selector);
        cp.mint{value: price + 1}(p, 0, new bytes32[](0));
        vm.expectRevert(IERC721ClaimParams.InvalidPayment.selector);
        cp.mint{value: price - 1}(p, 0, new bytes32[](0));
        vm.stopPrank();

        assertEq(cp.getParams(1).length, 0);
    }

    function testParamsLength() public {
        uint256 price = cp.mintPrice();
        vm.startPrank(collector);
        vm.expectRevert(IERC721ClaimParams.InvalidParamsLength.selector);
        cp.mint{value: price}(new bytes(PARAMS_LENGTH - 1), 0, new bytes32[](0));
        vm.expectRevert(IERC721ClaimParams.InvalidParamsLength.selector);
        cp.mint{value: price}(new bytes(PARAMS_LENGTH + 1), 0, new bytes32[](0));
        vm.expectRevert(IERC721ClaimParams.InvalidParamsLength.selector);
        cp.mint{value: price}("", 0, new bytes32[](0));
        vm.stopPrank();
    }

    function testConstructorRejectsZeroLength() public {
        vm.expectRevert(IERC721ClaimParams.InvalidParamsLength.selector);
        new ERC721ClaimParams(address(claim), address(creator), INSTANCE_ID, 0);
    }

    // ------------------------------------------------------------------ claim rules

    function testWalletMax() public {
        cp = _setUpClaim(address(claim), 2, bytes32(0), 1, 0);
        _mint(collector, _params(1));
        uint256 price = cp.mintPrice();
        vm.prank(collector);
        vm.expectRevert(ILazyPayableClaimCore.TooManyRequested.selector);
        cp.mint{value: price}(_params(2), 0, new bytes32[](0));
        // another wallet can still mint
        _mint(other, _params(3));
    }

    function testTotalMax() public {
        cp = _setUpClaim(address(claim), 2, bytes32(0), 0, 1);
        _mint(collector, _params(1));
        uint256 price = cp.mintPrice();
        vm.prank(other);
        vm.expectRevert(ILazyPayableClaimCore.TooManyRequested.selector);
        cp.mint{value: price}(_params(2), 0, new bytes32[](0));
    }

    function testClaimDates() public {
        IERC721LazyPayableClaim.ClaimParameters memory cpm = _claimParameters(bytes32(0), 0, 0);
        cpm.storageProtocol = ILazyPayableClaimCore.StorageProtocol.ADDRESS;
        cpm.location = string(abi.encodePacked(address(cp)));
        cpm.identical = false;

        // not started
        cpm.startDate = uint48(block.timestamp + 100);
        vm.prank(owner);
        claim.updateClaim(address(creator), INSTANCE_ID, cpm);
        uint256 price = cp.mintPrice();
        vm.prank(collector);
        vm.expectRevert(ILazyPayableClaimCore.ClaimInactive.selector);
        cp.mint{value: price}(_params(1), 0, new bytes32[](0));

        // ended
        vm.warp(block.timestamp + 1000);
        cpm.startDate = uint48(block.timestamp - 500);
        cpm.endDate = uint48(block.timestamp - 1);
        vm.prank(owner);
        claim.updateClaim(address(creator), INSTANCE_ID, cpm);
        vm.prank(collector);
        vm.expectRevert(ILazyPayableClaimCore.ClaimInactive.selector);
        cp.mint{value: price}(_params(1), 0, new bytes32[](0));
    }

    function testUnconfiguredInstanceReverts() public {
        ERC721ClaimParams stray = new ERC721ClaimParams(address(claim), address(creator), 999, PARAMS_LENGTH);
        vm.prank(collector);
        vm.expectRevert(ILazyPayableClaimCore.ClaimNotInitialized.selector);
        stray.mint{value: 1 ether}(_params(1), 0, new bytes32[](0));
    }

    // ------------------------------------------------------------------ allowlist

    function testAllowlist() public {
        bytes32 leaf0 = keccak256(abi.encodePacked(collector, uint32(0)));
        bytes32 leaf1 = keccak256(abi.encodePacked(other, uint32(1)));
        bytes32 root = _hashPair(leaf0, leaf1);
        cp = _setUpClaim(address(claim), 3, root, 0, 0);

        uint256 price = cp.mintPrice();
        assertEq(price, COST + claim.MINT_FEE_MERKLE());

        bytes32[] memory proof0 = new bytes32[](1);
        proof0[0] = leaf1;
        bytes32[] memory proof1 = new bytes32[](1);
        proof1[0] = leaf0;

        // someone else's leaf
        vm.prank(collector);
        vm.expectRevert("Could not verify merkle proof");
        cp.mint{value: price}(_params(1), 1, proof1);

        // bad proof
        vm.prank(collector);
        vm.expectRevert("Could not verify merkle proof");
        cp.mint{value: price}(_params(1), 0, proof1);

        // the non-merkle fee is not enough
        uint256 openPrice = COST + claim.MINT_FEE();
        vm.prank(collector);
        vm.expectRevert(IERC721ClaimParams.InvalidPayment.selector);
        cp.mint{value: openPrice}(_params(1), 0, proof0);

        // valid
        vm.prank(collector);
        cp.mint{value: price}(_params(1), 0, proof0);
        assertEq(creator.ownerOf(1), collector);
        assertEq(cp.getParams(1), _params(1));
        assertEq(address(claim).balance, claim.MINT_FEE_MERKLE());

        // index already used
        vm.prank(collector);
        vm.expectRevert("Already minted");
        cp.mint{value: price}(_params(2), 0, proof0);

        // second entry
        vm.prank(other);
        cp.mint{value: price}(_params(2), 1, proof1);
        assertEq(cp.getParams(2), _params(2));
    }

    // ------------------------------------------------------------------ re-entry

    function testReentrantMintReverts() public {
        ReentrantMinter minter = new ReentrantMinter(cp);
        vm.deal(address(minter), 1 ether);
        minter.setMode(1, _params(2));

        uint256 price = cp.mintPrice();
        minter.mint{value: price}(_params(1));

        // creator contract mints are nonReentrant: the inner mint reverted and its write rolled back
        assertTrue(minter.reentryReverted());
        assertEq(creator.balanceOf(address(minter)), 1);
        assertEq(cp.getParams(1), _params(1));
        assertEq(cp.getParams(2).length, 0);
        assertEq(address(cp).balance, 0);
    }

    function testReentrantSetParamsReverts() public {
        ReentrantMinter minter = new ReentrantMinter(cp);
        minter.setMode(2, _params(9));

        uint256 price = cp.mintPrice();
        minter.mint{value: price}(_params(1));

        assertTrue(minter.reentryReverted());
        assertEq(cp.getParams(1), _params(1));
    }

    // ------------------------------------------------------------------ setParams

    function testHolderSetsParamsOnDirectMint() public {
        // direct mint on the claim, bypassing this contract
        uint256 price = COST + claim.MINT_FEE();
        vm.prank(collector);
        claim.mint{value: price}(address(creator), INSTANCE_ID, 0, new bytes32[](0), collector);
        assertEq(cp.getParams(1).length, 0);
        assertEq(creator.tokenURI(1), _expectedURI(1, ""));

        // non-holder
        vm.prank(other);
        vm.expectRevert(IERC721ClaimParams.NotTokenOwner.selector);
        cp.setParams(1, _params(1));

        // wrong length
        vm.prank(collector);
        vm.expectRevert(IERC721ClaimParams.InvalidParamsLength.selector);
        cp.setParams(1, new bytes(1));

        vm.expectEmit(true, false, false, true, address(cp));
        emit ParamsSet(1, _params(1));
        vm.prank(collector);
        cp.setParams(1, _params(1));
        assertEq(creator.tokenURI(1), _expectedURI(1, _params(1)));

        // once only
        vm.prank(collector);
        vm.expectRevert(IERC721ClaimParams.ParamsAlreadySet.selector);
        cp.setParams(1, _params(2));
    }

    function testHolderSetsParamsOnAirdrop() public {
        address[] memory recipients = new address[](1);
        recipients[0] = collector;
        uint16[] memory amounts = new uint16[](1);
        amounts[0] = 2;
        vm.prank(owner);
        claim.airdrop(address(creator), INSTANCE_ID, recipients, amounts);

        vm.prank(collector);
        cp.setParams(2, _params(2));
        assertEq(cp.getParams(2), _params(2));
        assertEq(cp.getParams(1).length, 0);

        // the next mint through this contract takes mint order 3
        _mint(other, _params(3));
        assertEq(cp.getParams(3), _params(3));
        assertEq(creator.ownerOf(3), other);
    }

    function testSetParamsCannotOverwriteMint() public {
        _mint(collector, _params(1));
        vm.prank(collector);
        vm.expectRevert(IERC721ClaimParams.ParamsAlreadySet.selector);
        cp.setParams(1, _params(2));
        assertEq(cp.getParams(1), _params(1));
    }

    function testSetParamsRejectsOtherExtension() public {
        OtherExtension ext = new OtherExtension();
        vm.prank(owner);
        creator.registerExtension(address(ext), "");
        // same tokenData shape as this claim: instance INSTANCE_ID, mint order 1
        ext.mint(address(creator), collector, uint80(INSTANCE_ID << 24 | 1));

        vm.prank(collector);
        vm.expectRevert(IERC721ClaimParams.InvalidToken.selector);
        cp.setParams(1, _params(1));
    }

    function testSetParamsRejectsOtherClaimInstance() public {
        vm.prank(owner);
        claim.initializeClaim(address(creator), 77, _claimParameters(bytes32(0), 0, 0));
        uint256 price = COST + claim.MINT_FEE();
        vm.prank(collector);
        claim.mint{value: price}(address(creator), 77, 0, new bytes32[](0), collector);

        vm.prank(collector);
        vm.expectRevert(IERC721ClaimParams.InvalidToken.selector);
        cp.setParams(1, _params(1));
    }

    function testSetParamsNonexistentToken() public {
        vm.prank(collector);
        vm.expectRevert();
        cp.setParams(42, _params(1));
    }

    // ------------------------------------------------------------------ renderer

    function testRendererAdmin() public {
        IERC721ClaimParams.Renderer memory r = _renderer();
        r.name = "Renamed";

        vm.startPrank(other);
        vm.expectRevert(IERC721ClaimParams.NotCreatorAdmin.selector);
        cp.setRenderer(r);
        vm.expectRevert(IERC721ClaimParams.NotCreatorAdmin.selector);
        cp.lockRenderer();
        vm.stopPrank();

        vm.expectEmit(false, false, false, false, address(cp));
        emit RendererUpdated();
        vm.prank(owner);
        cp.setRenderer(r);
        (string memory name,,,) = cp.renderer();
        assertEq(name, "Renamed");

        vm.expectEmit(false, false, false, false, address(cp));
        emit RendererLocked();
        vm.prank(owner);
        cp.lockRenderer();
        assertTrue(cp.locked());

        vm.prank(owner);
        vm.expectRevert(IERC721ClaimParams.RendererIsLocked.selector);
        cp.setRenderer(_renderer());

        // params still work after lock
        _mint(collector, _params(1));
        assertEq(cp.getParams(1), _params(1));
    }

    function testCreatorAdminCanManage() public {
        vm.prank(owner);
        creator.approveAdmin(other);
        vm.prank(other);
        cp.setRenderer(_renderer());
    }

    function testEmptyParamsURI() public view {
        string memory uri = cp.tokenURI(address(creator), 1, INSTANCE_ID, 5);
        assertEq(uri, _expectedURI(5, ""));
    }

    function testSupportsInterface() public view {
        assertTrue(cp.supportsInterface(type(IERC721LazyPayableClaimMetadata).interfaceId));
        assertTrue(cp.supportsInterface(type(IERC721ClaimParams).interfaceId));
        assertTrue(cp.supportsInterface(0x01ffc9a7));
        assertFalse(cp.supportsInterface(0xffffffff));
    }

    // ------------------------------------------------------------------ updatable fee claim (V2)

    function testUpdatableFeeClaim() public {
        ERC721LazyPayableClaimV2 claimV2 = new ERC721LazyPayableClaimV2(owner, address(0xD1), address(0xD2));
        vm.prank(owner);
        creator.registerExtension(address(claimV2), "");
        cp = _setUpClaim(address(claimV2), 5, bytes32(0), 0, 0);

        // fees start at 0
        assertEq(cp.mintPrice(), COST);
        _mint(collector, _params(1));
        assertEq(cp.getParams(1), _params(1));

        // fee raised mid-sale: the price follows it
        vm.prank(owner);
        claimV2.setMintFees(0.001 ether, 0.002 ether);
        assertEq(cp.mintPrice(), COST + 0.001 ether);
        uint256 stale = COST;
        vm.prank(other);
        vm.expectRevert(IERC721ClaimParams.InvalidPayment.selector);
        cp.mint{value: stale}(_params(2), 0, new bytes32[](0));
        _mint(other, _params(2));
        assertEq(creator.ownerOf(2), other);
        assertEq(address(claimV2).balance, 0.001 ether);
    }

    // ------------------------------------------------------------------ gas

    function testGasMintVsDirect() public {
        bytes memory p = _params(1);
        uint256 price = cp.mintPrice();

        // warm both paths once so neither pays first-touch costs the other doesn't
        _mint(other, _params(7));

        vm.prank(collector);
        uint256 g0 = gasleft();
        claim.mint{value: price}(address(creator), INSTANCE_ID, 0, new bytes32[](0), collector);
        uint256 direct = g0 - gasleft();

        vm.prank(collector);
        g0 = gasleft();
        cp.mint{value: price}(p, 0, new bytes32[](0));
        uint256 withParams = g0 - gasleft();

        emit log_named_uint("direct claim mint gas", direct);
        emit log_named_uint("mint with 64-byte params gas", withParams);
        emit log_named_uint("extra gas", withParams - direct);
    }
}
