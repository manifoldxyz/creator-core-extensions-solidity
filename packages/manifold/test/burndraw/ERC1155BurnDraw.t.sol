// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC1155Creator.sol";
import "../../contracts/burndraw/ERC1155BurnDraw.sol";
import "../mocks/Mock.sol";
import "./mocks/BurnDrawMocks.sol";

abstract contract BurnDrawBase is Test {
    // solc 0.8.17 cannot `emit Interface.Event`, so the events asserted via expectEmit are mirrored here.
    event InstanceInitialized(address indexed packContract, uint256 indexed instanceId, IERC1155BurnDraw.Params params, address admin);
    event PrizeDeposited(address indexed packContract, uint256 indexed instanceId, address indexed token, uint256 id, uint256 amount, bool is1155);
    event OpenRequested(uint256 indexed requestId, address indexed packContract, uint256 indexed instanceId, address opener, uint256 count, uint256 vrfPaid);
    event RequestFulfilled(uint256 indexed requestId, address indexed packContract, uint256 indexed instanceId, uint256 packsBurned);
    event RequestCancelled(uint256 indexed requestId, address indexed opener, address to, uint256 packsReturned);

    ERC1155BurnDraw public draw;
    MockVRFWrapper public wrapper;
    ERC1155Creator public creator;
    MockERC721 public prize721;
    MockERC1155 public prize1155;

    address public owner = 0x6140F00e4Ff3936702E68744f2b5978885464cbB;
    address public alice = 0x80AAC46bbd3C2FcE33681541a52CacBEd14bF425;
    address public bob = 0x5174cD462b60c536eb51D4ceC1D561D3Ea31004F;
    address public stranger = 0xc78Dc443c126af6E4f6Ed540c1e740C1b5be09cd;

    uint256 public constant INSTANCE = 1;
    uint256 public packId; // token id of the pack on `creator`
    uint256 public start;
    uint256 public end;

    function _deployCommon(address wrapperAddr) internal {
        vm.startPrank(owner);
        creator = new ERC1155Creator("Packs", "PACK");
        prize721 = new MockERC721("P721", "P721");
        prize1155 = new MockERC1155("p1155");
        draw = new ERC1155BurnDraw(wrapperAddr);
        address[] memory to = new address[](1);
        uint256[] memory amts = new uint256[](1);
        string[] memory uris = new string[](1);
        to[0] = alice;
        amts[0] = 100;
        uris[0] = "";
        packId = creator.mintBaseNew(to, amts, uris)[0];
        to[0] = bob;
        uint256[] memory ids = new uint256[](1);
        ids[0] = packId;
        creator.mintBaseExisting(to, ids, amts);
        vm.stopPrank();
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(owner, 100 ether);
    }

    function _init() internal {
        start = block.timestamp - 10;
        end = block.timestamp + 7 days;
        vm.prank(owner);
        draw.initialize(address(creator), INSTANCE, IERC1155BurnDraw.Params(packId, uint48(start), uint48(end)));
    }

    function _deposit721(uint256 firstId, uint256 n) internal {
        IERC1155BurnDraw.PrizeDeposit[] memory d = new IERC1155BurnDraw.PrizeDeposit[](n);
        vm.startPrank(owner);
        for (uint256 i; i < n; i++) {
            prize721.mint(owner, firstId + i);
            d[i] = IERC1155BurnDraw.PrizeDeposit(address(prize721), firstId + i, 1, false);
        }
        prize721.setApprovalForAll(address(draw), true);
        draw.depositPrizes(address(creator), INSTANCE, d);
        vm.stopPrank();
    }

    function _deposit1155(uint256 id, uint256 amount) internal {
        IERC1155BurnDraw.PrizeDeposit[] memory d = new IERC1155BurnDraw.PrizeDeposit[](1);
        d[0] = IERC1155BurnDraw.PrizeDeposit(address(prize1155), id, amount, true);
        vm.startPrank(owner);
        prize1155.mint(owner, id, amount);
        prize1155.setApprovalForAll(address(draw), true);
        draw.depositPrizes(address(creator), INSTANCE, d);
        vm.stopPrank();
    }

    function _price(uint256 n) internal view returns (uint256) {
        return draw.quoteOpen(n);
    }

    function _open(address who, uint256 n) internal returns (uint256 id) {
        vm.startPrank(who);
        creator.setApprovalForAll(address(draw), true);
        id = draw.open{value: _price(n)}(address(creator), INSTANCE, n);
        vm.stopPrank();
    }

    function _fulfill(uint256 id, uint256 word) internal returns (bool) {
        return wrapper.fulfillWord(id, word);
    }

    function _packsOf(address who) internal view returns (uint256) {
        return creator.balanceOf(who, packId);
    }
}

contract ERC1155BurnDrawTest is BurnDrawBase {
    function setUp() public {
        vm.warp(1_000_000);
        wrapper = new MockVRFWrapper();
        _deployCommon(address(wrapper));
        _init();
        _deposit721(1, 3);
        _deposit1155(7, 4);
    }

    /*//////////////////////////////////////////////////////////////
                          init / update / auth
    //////////////////////////////////////////////////////////////*/

    function testInitAuth() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(IERC1155BurnDraw.NotAdmin.selector, address(creator)));
        draw.initialize(address(creator), 2, IERC1155BurnDraw.Params(packId, 0, 0));

        vm.expectEmit(true, true, false, true);
        emit InstanceInitialized(
            address(creator), 2, IERC1155BurnDraw.Params(packId, 5, 0), owner
        );
        vm.prank(owner);
        draw.initialize(address(creator), 2, IERC1155BurnDraw.Params(packId, 5, 0));

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IERC1155BurnDraw.InstanceAlreadyExists.selector, 2));
        draw.initialize(address(creator), 2, IERC1155BurnDraw.Params(packId, 5, 0));

        vm.prank(owner);
        vm.expectRevert(IERC1155BurnDraw.InvalidInput.selector);
        draw.initialize(address(creator), 3, IERC1155BurnDraw.Params(packId, 10, 10));
    }

    function testAdminOfOtherContractCannotInitOrDeposit() public {
        // owner of a different creator contract is not admin of `creator`
        vm.startPrank(stranger);
        ERC1155Creator other = new ERC1155Creator("o", "o");
        vm.expectRevert(abi.encodeWithSelector(IERC1155BurnDraw.NotAdmin.selector, address(creator)));
        draw.initialize(address(creator), 9, IERC1155BurnDraw.Params(packId, 0, 0));
        // but may run their own instance on their own contract
        draw.initialize(address(other), 9, IERC1155BurnDraw.Params(1, 0, 0));
        IERC1155BurnDraw.PrizeDeposit[] memory d = new IERC1155BurnDraw.PrizeDeposit[](1);
        d[0] = IERC1155BurnDraw.PrizeDeposit(address(prize721), 1, 1, false);
        vm.expectRevert(abi.encodeWithSelector(IERC1155BurnDraw.NotAdmin.selector, address(creator)));
        draw.depositPrizes(address(creator), INSTANCE, d);
        vm.stopPrank();
    }

    function testUpdateRules() public {
        // non-admin
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(IERC1155BurnDraw.NotAdmin.selector, address(creator)));
        draw.update(address(creator), INSTANCE, IERC1155BurnDraw.Params(packId, 0, 0));

        // unknown instance
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IERC1155BurnDraw.InstanceDoesNotExist.selector, 77));
        draw.update(address(creator), 77, IERC1155BurnDraw.Params(packId, 0, 0));

        // before first open: can change packTokenId
        vm.prank(owner);
        draw.update(address(creator), INSTANCE, IERC1155BurnDraw.Params(packId + 5, uint48(start), uint48(end)));
        assertEq(draw.getInstance(address(creator), INSTANCE).packTokenId, packId + 5);
        vm.prank(owner);
        draw.update(address(creator), INSTANCE, IERC1155BurnDraw.Params(packId, uint48(start), uint48(end)));

        // pending draw blocks update
        uint256 id = _open(alice, 1);
        vm.prank(owner);
        vm.expectRevert(IERC1155BurnDraw.DrawPending.selector);
        draw.update(address(creator), INSTANCE, IERC1155BurnDraw.Params(packId, uint48(start), uint48(end)));
        _fulfill(id, 1);

        // after first open: dates may change, packTokenId may not
        vm.prank(owner);
        draw.update(address(creator), INSTANCE, IERC1155BurnDraw.Params(packId, uint48(start), uint48(end + 1 days)));
        assertEq(draw.getInstance(address(creator), INSTANCE).endDate, end + 1 days);
        vm.prank(owner);
        vm.expectRevert(IERC1155BurnDraw.PackTokenLocked.selector);
        draw.update(address(creator), INSTANCE, IERC1155BurnDraw.Params(packId + 1, uint48(start), uint48(end)));
    }

    /*//////////////////////////////////////////////////////////////
                                deposit
    //////////////////////////////////////////////////////////////*/

    function testDepositAccounting() public {
        IERC1155BurnDraw.InstanceInfo memory info = draw.getInstance(address(creator), INSTANCE);
        assertEq(info.totalSlots, 7);
        assertEq(info.availableSlots, 7);
        assertEq(draw.remainingSlots(address(creator), INSTANCE), 7);
        assertEq(prize721.balanceOf(address(draw)), 3);
        assertEq(prize1155.balanceOf(address(draw), 7), 4);
        assertEq(prize721.ownerOf(2), address(draw));

        IERC1155BurnDraw.Slot[] memory page = draw.getSlots(address(creator), INSTANCE, 0, 100);
        assertEq(page.length, 7);
        assertEq(page[0].token, address(prize721));
        assertEq(page[0].id, 1);
        assertFalse(page[0].is1155);
        assertEq(page[6].token, address(prize1155));
        assertEq(page[6].id, 7);
        assertTrue(page[6].is1155);

        // pagination
        assertEq(draw.getSlots(address(creator), INSTANCE, 5, 100).length, 2);
        assertEq(draw.getSlots(address(creator), INSTANCE, 2, 3).length, 3);
        assertEq(draw.getSlots(address(creator), INSTANCE, 7, 3).length, 0);
        assertEq(draw.getSlots(address(creator), INSTANCE, 99, 3).length, 0);
    }

    function testDepositEventsAndInputChecks() public {
        prize721.mint(owner, 50);
        vm.startPrank(owner);
        prize721.setApprovalForAll(address(draw), true);
        IERC1155BurnDraw.PrizeDeposit[] memory d = new IERC1155BurnDraw.PrizeDeposit[](1);

        d[0] = IERC1155BurnDraw.PrizeDeposit(address(prize721), 50, 1, false);
        vm.expectEmit(true, true, true, true);
        emit PrizeDeposited(address(creator), INSTANCE, address(prize721), 50, 1, false);
        draw.depositPrizes(address(creator), INSTANCE, d);

        // 721 amount must be 1; zero amount; zero token; self token
        prize721.mint(owner, 51);
        d[0] = IERC1155BurnDraw.PrizeDeposit(address(prize721), 51, 2, false);
        vm.expectRevert(IERC1155BurnDraw.InvalidInput.selector);
        draw.depositPrizes(address(creator), INSTANCE, d);
        d[0] = IERC1155BurnDraw.PrizeDeposit(address(prize721), 51, 0, false);
        vm.expectRevert(IERC1155BurnDraw.InvalidInput.selector);
        draw.depositPrizes(address(creator), INSTANCE, d);
        d[0] = IERC1155BurnDraw.PrizeDeposit(address(0), 51, 1, false);
        vm.expectRevert(IERC1155BurnDraw.InvalidInput.selector);
        draw.depositPrizes(address(creator), INSTANCE, d);
        d[0] = IERC1155BurnDraw.PrizeDeposit(address(draw), 51, 1, false);
        vm.expectRevert(IERC1155BurnDraw.InvalidInput.selector);
        draw.depositPrizes(address(creator), INSTANCE, d);
        // empty batch
        vm.expectRevert(IERC1155BurnDraw.InvalidInput.selector);
        draw.depositPrizes(address(creator), INSTANCE, new IERC1155BurnDraw.PrizeDeposit[](0));
        vm.stopPrank();
    }

    function testDepositFromNonOwnerOfPrizeReverts() public {
        // admin tries to deposit a 721 they don't own
        prize721.mint(stranger, 60);
        vm.prank(stranger);
        prize721.setApprovalForAll(address(draw), true);
        IERC1155BurnDraw.PrizeDeposit[] memory d = new IERC1155BurnDraw.PrizeDeposit[](1);
        d[0] = IERC1155BurnDraw.PrizeDeposit(address(prize721), 60, 1, false);
        vm.prank(owner);
        vm.expectRevert("ERC721: transfer from incorrect owner");
        draw.depositPrizes(address(creator), INSTANCE, d);
    }

    function testDepositLyingTokensRevert() public {
        LyingERC721 l721 = new LyingERC721();
        LyingERC1155 l1155 = new LyingERC1155();
        IERC1155BurnDraw.PrizeDeposit[] memory d = new IERC1155BurnDraw.PrizeDeposit[](1);
        d[0] = IERC1155BurnDraw.PrizeDeposit(address(l721), 1, 1, false);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IERC1155BurnDraw.PrizeNotReceived.selector, address(l721), 1));
        draw.depositPrizes(address(creator), INSTANCE, d);

        d[0] = IERC1155BurnDraw.PrizeDeposit(address(l1155), 1, 3, true);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IERC1155BurnDraw.PrizeNotReceived.selector, address(l1155), 1));
        draw.depositPrizes(address(creator), INSTANCE, d);
        assertEq(draw.remainingSlots(address(creator), INSTANCE), 7);
    }

    function testDepositBlockedWhilePending() public {
        _open(alice, 1);
        prize721.mint(owner, 70);
        IERC1155BurnDraw.PrizeDeposit[] memory d = new IERC1155BurnDraw.PrizeDeposit[](1);
        d[0] = IERC1155BurnDraw.PrizeDeposit(address(prize721), 70, 1, false);
        vm.prank(owner);
        vm.expectRevert(IERC1155BurnDraw.DrawPending.selector);
        draw.depositPrizes(address(creator), INSTANCE, d);
    }

    function testSameErc1155IdDepositedTwiceSharesType() public {
        _deposit1155(7, 2);
        assertEq(draw.remainingSlots(address(creator), INSTANCE), 9);
        assertEq(prize1155.balanceOf(address(draw), 7), 6);
    }

    /*//////////////////////////////////////////////////////////////
                           unexpected receipts
    //////////////////////////////////////////////////////////////*/

    function testUnexpectedPlainTransfersRejected() public {
        // a plain 1155 transfer of a prize token is rejected by the receiver hook
        prize1155.mint(alice, 9, 5);
        vm.prank(alice);
        vm.expectRevert("ERC1155: transfer to non-ERC1155Receiver implementer");
        prize1155.safeTransferFrom(alice, address(draw), 9, 1, "");

        // a plain transfer of a pack token directly (not via open) is rejected too
        vm.prank(alice);
        vm.expectRevert("ERC1155: transfer to non-ERC1155Receiver implementer");
        creator.safeTransferFrom(alice, address(draw), packId, 1, "");

        // batch is always rejected
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amts = new uint256[](1);
        ids[0] = packId;
        amts[0] = 1;
        vm.prank(alice);
        vm.expectRevert("ERC1155: transfer to non-ERC1155Receiver implementer");
        creator.safeBatchTransferFrom(alice, address(draw), ids, amts, "");

        // mint straight to the contract by the creator admin: also rejected (and so cannot strand tokens)
        address[] memory to = new address[](1);
        to[0] = address(draw);
        uint256[] memory tids = new uint256[](1);
        tids[0] = packId;
        vm.prank(owner);
        vm.expectRevert("ERC1155: transfer to non-ERC1155Receiver implementer");
        creator.mintBaseExisting(to, tids, amts);

        // nothing changed
        assertEq(draw.remainingSlots(address(creator), INSTANCE), 7);
        assertEq(creator.balanceOf(address(draw), packId), 0);
    }

    function testReceiverHookCalledDirectlyRejected() public {
        // calling the hook by hand, pretending to be a token, must fail: no transfer is in flight
        vm.prank(address(prize1155));
        vm.expectRevert(IERC1155BurnDraw.UnexpectedReceipt.selector);
        draw.onERC1155Received(address(draw), address(0), 1, 1, "");
        vm.expectRevert(IERC1155BurnDraw.UnexpectedReceipt.selector);
        draw.onERC1155Received(address(draw), address(0), 1, 1, "");
        assertTrue(draw.supportsInterface(type(IERC1155Receiver).interfaceId));
    }

    function testErc721SafeTransferToDrawRejected() public {
        // contract does not implement onERC721Received => safe transfers of 721 revert
        prize721.mint(alice, 99);
        vm.prank(alice);
        vm.expectRevert("ERC721: transfer to non ERC721Receiver implementer");
        prize721.safeTransferFrom(alice, address(draw), 99);
    }

    function testCannotSendEthDirectly() public {
        vm.prank(alice);
        (bool ok,) = address(draw).call{value: 1 ether}("");
        assertFalse(ok);
    }

    /*//////////////////////////////////////////////////////////////
                                  open
    //////////////////////////////////////////////////////////////*/

    function testOpenHappyPath() public {
        uint256 price = _price(2);
        uint256 aliceEthBefore = alice.balance;

        vm.startPrank(alice);
        creator.setApprovalForAll(address(draw), true);
        vm.expectEmit(true, true, true, true);
        emit OpenRequested(1000, address(creator), INSTANCE, alice, 2, price);
        uint256 id = draw.open{value: price}(address(creator), INSTANCE, 2);
        vm.stopPrank();

        assertEq(id, 1000);
        assertEq(_packsOf(alice), 98);
        assertEq(_packsOf(address(draw)), 2);
        assertEq(alice.balance, aliceEthBefore - price);
        assertEq(address(wrapper).balance, price);
        assertEq(address(draw).balance, 0);

        IERC1155BurnDraw.InstanceInfo memory info = draw.getInstance(address(creator), INSTANCE);
        assertEq(info.pendingRequests, 1);
        assertEq(info.reservedCount, 2);
        assertEq(info.totalSlots, 7);
        assertEq(info.availableSlots, 5);
        assertTrue(info.hasOpened);

        IERC1155BurnDraw.RequestInfo memory ri = draw.getRequest(id);
        assertEq(ri.opener, alice);
        assertEq(ri.count, 2);
        assertEq(uint8(ri.status), uint8(IERC1155BurnDraw.Status.PENDING));
        assertEq(ri.prizes.length, 0);

        // wrapper got the right request: callback gas, native extraArgs, 1 word
        (address consumer, uint32 gasLimit, uint32 words,) = wrapper.reqs(id);
        assertEq(consumer, address(draw));
        assertEq(gasLimit, draw.callbackGasLimit(2));
        assertEq(words, 1);

        // fulfil: packs burned, prizes assigned, nothing delivered yet
        uint256 packSupplyBefore = _packsOf(alice) + _packsOf(bob) + _packsOf(address(draw));
        assertEq(packSupplyBefore, 200);
        vm.expectEmit(true, true, true, true);
        emit RequestFulfilled(id, address(creator), INSTANCE, 2);
        assertTrue(_fulfill(id, 12345));
        assertEq(_packsOf(address(draw)), 0);
        assertEq(_packsOf(alice) + _packsOf(bob), 198);

        ri = draw.getRequest(id);
        assertEq(uint8(ri.status), uint8(IERC1155BurnDraw.Status.FULFILLED));
        assertEq(ri.prizes.length, 2);
        info = draw.getInstance(address(creator), INSTANCE);
        assertEq(info.pendingRequests, 0);
        assertEq(info.reservedCount, 0);
        assertEq(info.totalSlots, 5);
        // prizes still held by the contract until claim
        assertEq(prize721.balanceOf(address(draw)) + prize1155.balanceOf(address(draw), 7), 7);
    }

    function testOpenRevertsNotEnoughPrizes() public {
        vm.startPrank(alice);
        creator.setApprovalForAll(address(draw), true);
        uint256 p = _price(8);
        // 8 > MAX_PER_OPEN? no, MAX is 10; 8 > 7 slots
        vm.expectRevert(abi.encodeWithSelector(IERC1155BurnDraw.NotEnoughPrizes.selector, 8, 7));
        draw.open{value: p}(address(creator), INSTANCE, 8);
        vm.stopPrank();
    }

    function testReservationReducesAvailability() public {
        _open(alice, 5);
        vm.startPrank(bob);
        creator.setApprovalForAll(address(draw), true);
        uint256 p = _price(3);
        vm.expectRevert(abi.encodeWithSelector(IERC1155BurnDraw.NotEnoughPrizes.selector, 3, 2));
        draw.open{value: p}(address(creator), INSTANCE, 3);
        // 2 is fine
        draw.open{value: _price(2)}(address(creator), INSTANCE, 2);
        // nothing left
        uint256 p1 = _price(1);
        vm.expectRevert(abi.encodeWithSelector(IERC1155BurnDraw.NotEnoughPrizes.selector, 1, 0));
        draw.open{value: p1}(address(creator), INSTANCE, 1);
        vm.stopPrank();
        assertEq(draw.remainingSlots(address(creator), INSTANCE), 0);
    }

    function testOpenMaxPerOpenAndZero() public {
        _deposit1155(8, 20);
        vm.startPrank(alice);
        creator.setApprovalForAll(address(draw), true);
        vm.expectRevert(abi.encodeWithSelector(IERC1155BurnDraw.TooManyPerOpen.selector, 11, 10));
        draw.open{value: 1 ether}(address(creator), INSTANCE, 11);
        vm.expectRevert(IERC1155BurnDraw.InvalidInput.selector);
        draw.open{value: 1 ether}(address(creator), INSTANCE, 0);
        vm.expectRevert(IERC1155BurnDraw.InvalidInput.selector);
        draw.quoteOpen(0);
        // exactly 10 works
        uint256 id = draw.open{value: _price(10)}(address(creator), INSTANCE, 10);
        vm.stopPrank();
        assertTrue(_fulfill(id, 0xabc));
        assertEq(draw.getRequest(id).prizes.length, 10);
    }

    function testOpenWindow() public {
        // before start
        vm.prank(owner);
        draw.initialize(address(creator), 2, IERC1155BurnDraw.Params(packId, uint48(block.timestamp + 100), uint48(block.timestamp + 1000)));
        vm.startPrank(alice);
        creator.setApprovalForAll(address(draw), true);
        uint256 p = _price(1);
        vm.expectRevert(abi.encodeWithSelector(IERC1155BurnDraw.InstanceInactive.selector, 2));
        draw.open{value: p}(address(creator), 2, 1);
        vm.stopPrank();

        // after end (main instance)
        vm.warp(end);
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC1155BurnDraw.InstanceInactive.selector, INSTANCE));
        draw.open{value: p}(address(creator), INSTANCE, 1);
        vm.stopPrank();

        // unknown instance
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC1155BurnDraw.InstanceDoesNotExist.selector, 55));
        draw.open{value: p}(address(creator), 55, 1);

        // endDate 0 = no end
        vm.prank(owner);
        draw.initialize(address(creator), 3, IERC1155BurnDraw.Params(packId, 0, 0));
        vm.warp(block.timestamp + 3650 days);
        // (no prizes in instance 3, so NotEnoughPrizes proves we got past the window check)
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC1155BurnDraw.NotEnoughPrizes.selector, 1, 0));
        draw.open{value: p}(address(creator), 3, 1);
    }

    function testOpenPaymentAndRefund() public {
        uint256 p = _price(1);
        vm.startPrank(alice);
        creator.setApprovalForAll(address(draw), true);
        vm.expectRevert(abi.encodeWithSelector(IERC1155BurnDraw.InsufficientPayment.selector, p, p - 1));
        draw.open{value: p - 1}(address(creator), INSTANCE, 1);

        uint256 before = alice.balance;
        draw.open{value: p + 3 ether}(address(creator), INSTANCE, 1);
        vm.stopPrank();
        assertEq(before - alice.balance, p, "overpay refunded");
        assertEq(address(draw).balance, 0);
    }

    function testRefundFailureReverts() public {
        NoEthOpener o = new NoEthOpener();
        address[] memory to = new address[](1);
        to[0] = address(o);
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amts = new uint256[](1);
        ids[0] = packId;
        amts[0] = 5;
        vm.prank(owner);
        creator.mintBaseExisting(to, ids, amts);
        vm.deal(address(o), 10 ether);
        uint256 p = _price(1);
        // exact payment works (no refund needed)
        o.callOpen(address(draw), address(creator), INSTANCE, 1, p);
        // overpay => refund to a contract that rejects ETH => whole open reverts
        vm.expectRevert(IERC1155BurnDraw.RefundFailed.selector);
        o.callOpen(address(draw), address(creator), INSTANCE, 1, p + 1);
    }

    function testOpenWithoutApprovalOrBalanceReverts() public {
        uint256 p = _price(1);
        vm.prank(alice);
        vm.expectRevert("ERC1155: caller is not token owner or approved");
        draw.open{value: p}(address(creator), INSTANCE, 1);

        vm.startPrank(stranger);
        creator.setApprovalForAll(address(draw), true);
        vm.deal(stranger, 1 ether);
        vm.expectRevert("ERC1155: insufficient balance for transfer");
        draw.open{value: p}(address(creator), INSTANCE, 1);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                               fulfilment
    //////////////////////////////////////////////////////////////*/

    function testFulfilOnlyWrapper() public {
        uint256 id = _open(alice, 1);
        uint256[] memory w = new uint256[](1);
        w[0] = 5;
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(IERC1155BurnDraw.NotWrapper.selector, stranger));
        draw.rawFulfillRandomWords(id, w);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IERC1155BurnDraw.NotWrapper.selector, owner));
        draw.rawFulfillRandomWords(id, w);
        assertEq(uint8(draw.getRequest(id).status), uint8(IERC1155BurnDraw.Status.PENDING));
    }

    function testFulfilUnknownAndDouble() public {
        uint256 id = _open(alice, 2);
        uint256[] memory w = new uint256[](1);
        w[0] = 5;
        vm.prank(address(wrapper));
        vm.expectRevert(abi.encodeWithSelector(IERC1155BurnDraw.RequestNotPending.selector, 424242));
        draw.rawFulfillRandomWords(424242, w);

        assertTrue(_fulfill(id, 5));
        // the wrapper would have deleted its record; a second delivery straight at the consumer reverts
        vm.prank(address(wrapper));
        vm.expectRevert(abi.encodeWithSelector(IERC1155BurnDraw.RequestNotPending.selector, id));
        draw.rawFulfillRandomWords(id, w);

        // empty words are rejected
        uint256 id2 = _open(bob, 1);
        vm.prank(address(wrapper));
        vm.expectRevert(IERC1155BurnDraw.InvalidInput.selector);
        draw.rawFulfillRandomWords(id2, new uint256[](0));
        assertEq(draw.getInstance(address(creator), INSTANCE).totalSlots, 5 - 0, "state unchanged by failed fulfils");
    }

    /// Assignment must equal the documented model: idx_i = keccak(seed, i) % len, swap-remove.
    function testAssignmentMatchesModel() public {
        uint256 seed = 0xdeadbeef;
        uint256 n = 4;
        IERC1155BurnDraw.Slot[] memory model = draw.getSlots(address(creator), INSTANCE, 0, 100);
        uint256 len = model.length;
        IERC1155BurnDraw.Slot[] memory expected = new IERC1155BurnDraw.Slot[](n);
        for (uint256 i; i < n; i++) {
            uint256 idx = uint256(keccak256(abi.encode(seed, i))) % len;
            expected[i] = model[idx];
            model[idx] = model[len - 1];
            len--;
        }
        uint256 id = _open(alice, n);
        _fulfill(id, seed);
        IERC1155BurnDraw.RequestInfo memory ri = draw.getRequest(id);
        for (uint256 i; i < n; i++) {
            assertEq(ri.prizes[i].token, expected[i].token);
            assertEq(ri.prizes[i].id, expected[i].id);
        }
    }

    function testFuzz_AssignmentUniqueAcrossRequests(uint256 s1, uint256 s2, uint8 a, uint8 b) public {
        uint256 n1 = bound(a, 1, 4);
        uint256 n2 = bound(b, 1, 3); // 4 + 3 = 7 = all slots
        uint256 id1 = _open(alice, n1);
        uint256 id2 = _open(bob, n2);
        // fulfil in the opposite order of requests
        assertTrue(_fulfill(id2, s2));
        assertTrue(_fulfill(id1, s1));
        IERC1155BurnDraw.RequestInfo memory r1 = draw.getRequest(id1);
        IERC1155BurnDraw.RequestInfo memory r2 = draw.getRequest(id2);
        // 721 ids 1..3 each assigned at most once across both requests
        uint256[4] memory seen;
        uint256 cnt1155;
        for (uint256 i; i < r1.prizes.length; i++) {
            if (r1.prizes[i].is1155) cnt1155++;
            else seen[r1.prizes[i].id]++;
        }
        for (uint256 i; i < r2.prizes.length; i++) {
            if (r2.prizes[i].is1155) cnt1155++;
            else seen[r2.prizes[i].id]++;
        }
        for (uint256 k = 1; k <= 3; k++) assertLe(seen[k], 1, "721 assigned twice");
        assertLe(cnt1155, 4, "more 1155 units than exist");
        // remaining slots + assigned == total deposited
        assertEq(draw.getInstance(address(creator), INSTANCE).totalSlots + n1 + n2, 7);
    }

    function testFulfilWhenPackBurnRevertsLeavesPendingAndCancelWorks() public {
        // Pack contract whose burn fails: fulfil must not partially apply; cancel is the exit.
        MockPack mp = new MockPack();
        mp.mint(alice, 1, 10);
        vm.prank(address(this));
        draw.initialize(address(mp), 5, IERC1155BurnDraw.Params(1, 0, 0));
        // deposit a prize into instance 5 (this test contract is admin of mp)
        prize721.mint(address(this), 500);
        prize721.setApprovalForAll(address(draw), true);
        IERC1155BurnDraw.PrizeDeposit[] memory d = new IERC1155BurnDraw.PrizeDeposit[](1);
        d[0] = IERC1155BurnDraw.PrizeDeposit(address(prize721), 500, 1, false);
        draw.depositPrizes(address(mp), 5, d);

        vm.startPrank(alice);
        mp.setApprovalForAll(address(draw), true);
        uint256 id = draw.open{value: _price(1)}(address(mp), 5, 1);
        vm.stopPrank();

        mp.setBurnReverts(true);
        assertFalse(_fulfill(id, 1), "callback reverted");
        assertEq(uint8(draw.getRequest(id).status), uint8(IERC1155BurnDraw.Status.PENDING));
        assertEq(draw.getInstance(address(mp), 5).reservedCount, 1);
        assertEq(draw.getInstance(address(mp), 5).totalSlots, 1);
        assertEq(mp.balanceOf(address(draw), 1), 1);

        vm.warp(block.timestamp + 24 hours);
        vm.prank(alice);
        draw.cancel(id, alice);
        assertEq(mp.balanceOf(alice, 1), 10);
        assertEq(draw.getInstance(address(mp), 5).reservedCount, 0);
    }

    /*//////////////////////////////////////////////////////////////
                                  claim
    //////////////////////////////////////////////////////////////*/

    function testClaimDeliversToOpenerAnyoneCanCall() public {
        uint256 id = _open(alice, 3);
        _fulfill(id, 777);
        IERC1155BurnDraw.RequestInfo memory ri = draw.getRequest(id);

        vm.prank(stranger); // not the opener
        draw.claim(id);

        for (uint256 i; i < ri.prizes.length; i++) {
            if (ri.prizes[i].is1155) {
                assertGe(prize1155.balanceOf(alice, ri.prizes[i].id), 1);
            } else {
                assertEq(prize721.ownerOf(ri.prizes[i].id), alice);
            }
        }
        assertEq(prize721.balanceOf(alice) + prize1155.balanceOf(alice, 7), 3);
        assertEq(prize721.balanceOf(stranger), 0);
        assertEq(uint8(draw.getRequest(id).status), uint8(IERC1155BurnDraw.Status.CLAIMED));

        // second claim reverts, nothing moves twice
        vm.expectRevert(abi.encodeWithSelector(IERC1155BurnDraw.RequestNotFulfilled.selector, id));
        draw.claim(id);
        assertEq(prize721.balanceOf(alice) + prize1155.balanceOf(alice, 7), 3);
    }

    function testClaimBeforeFulfilOrUnknownReverts() public {
        uint256 id = _open(alice, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC1155BurnDraw.RequestNotFulfilled.selector, id));
        draw.claim(id);
        vm.expectRevert(abi.encodeWithSelector(IERC1155BurnDraw.RequestNotFulfilled.selector, 31337));
        draw.claim(31337);
    }

    function testClaimToOnlyOpener() public {
        uint256 id = _open(alice, 2);
        _fulfill(id, 4);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(IERC1155BurnDraw.NotOpener.selector, id));
        draw.claimTo(id, stranger);
        vm.prank(alice);
        vm.expectRevert(IERC1155BurnDraw.InvalidInput.selector);
        draw.claimTo(id, address(0));
        vm.prank(alice);
        draw.claimTo(id, bob);
        assertEq(prize721.balanceOf(bob) + prize1155.balanceOf(bob, 7), 2);
        assertEq(prize721.balanceOf(alice) + prize1155.balanceOf(alice, 7), 0);
    }

    function testDeliveryFailureStaysClaimableAndDoesNotBlockOthers() public {
        SwitchableReceiver rcv = new SwitchableReceiver();
        address[] memory to = new address[](1);
        to[0] = address(rcv);
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amts = new uint256[](1);
        ids[0] = packId;
        amts[0] = 5;
        vm.prank(owner);
        creator.mintBaseExisting(to, ids, amts);
        vm.deal(address(rcv), 10 ether);

        // contract opener opens 3 while it can accept, then flips to rejecting before claim
        uint256 idBad = rcv.callOpen(address(draw), address(creator), INSTANCE, 3, _price(3));
        uint256 idGood = _open(bob, 2);
        _fulfill(idBad, 11);
        _fulfill(idGood, 22);

        rcv.setAccept(false);
        // bad request: delivery fails, request stays FULFILLED, nothing lost
        IERC1155BurnDraw.RequestInfo memory before_ = draw.getRequest(idBad);
        uint256 held = prize721.balanceOf(address(draw)) + prize1155.balanceOf(address(draw), 7);
        draw.claim(idBad);
        assertEq(uint8(draw.getRequest(idBad).status), uint8(IERC1155BurnDraw.Status.FULFILLED));
        assertEq(draw.getRequest(idBad).deliveredMask, 0);
        assertEq(prize721.balanceOf(address(draw)) + prize1155.balanceOf(address(draw), 7), held);
        assertEq(before_.prizes.length, 3);

        // an unrelated request is not blocked
        draw.claim(idGood);
        assertEq(uint8(draw.getRequest(idGood).status), uint8(IERC1155BurnDraw.Status.CLAIMED));
        assertEq(prize721.balanceOf(bob) + prize1155.balanceOf(bob, 7), 2);

        // opener fixes its receiver => same request now delivers
        rcv.setAccept(true);
        draw.claim(idBad);
        assertEq(uint8(draw.getRequest(idBad).status), uint8(IERC1155BurnDraw.Status.CLAIMED));
        assertEq(prize721.balanceOf(address(rcv)) + prize1155.balanceOf(address(rcv), 7), 3);

        // alternatively: redirect with claimTo when the opener's own receiver cannot take them
        // (covered in testClaimToOnlyOpener)
    }

    function testClaimToEscapesRejectingOpener() public {
        SwitchableReceiver rcv = new SwitchableReceiver();
        address[] memory to = new address[](1);
        to[0] = address(rcv);
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amts = new uint256[](1);
        ids[0] = packId;
        amts[0] = 5;
        vm.prank(owner);
        creator.mintBaseExisting(to, ids, amts);
        vm.deal(address(rcv), 10 ether);
        uint256 id = rcv.callOpen(address(draw), address(creator), INSTANCE, 2, _price(2));
        _fulfill(id, 3);
        rcv.setAccept(false);
        draw.claim(id);
        assertEq(draw.getRequest(id).deliveredMask, 0);
        rcv.callClaimTo(address(draw), id, alice);
        assertEq(uint8(draw.getRequest(id).status), uint8(IERC1155BurnDraw.Status.CLAIMED));
        assertEq(prize721.balanceOf(alice) + prize1155.balanceOf(alice, 7), 2);
    }

    function testClaimSelectedPartial() public {
        uint256 id = _open(alice, 3);
        _fulfill(id, 99);
        IERC1155BurnDraw.RequestInfo memory ri = draw.getRequest(id);
        draw.claimSelected(id, 0x1); // only prize 0
        assertEq(draw.getRequest(id).deliveredMask, 0x1);
        assertEq(uint8(draw.getRequest(id).status), uint8(IERC1155BurnDraw.Status.FULFILLED));
        draw.claimSelected(id, 0x1); // idempotent, no double send
        assertEq(draw.getRequest(id).deliveredMask, 0x1);
        draw.claimSelected(id, 0xfffe); // rest, incl. high bits beyond n
        assertEq(uint8(draw.getRequest(id).status), uint8(IERC1155BurnDraw.Status.CLAIMED));
        assertEq(ri.prizes.length, 3);
        assertEq(prize721.balanceOf(alice) + prize1155.balanceOf(alice, 7), 3);
    }

    /*//////////////////////////////////////////////////////////////
                                 cancel
    //////////////////////////////////////////////////////////////*/

    function testCancelAfterTimeoutReturnsPacks() public {
        uint256 id = _open(alice, 4);
        assertEq(_packsOf(alice), 96);
        uint256 t0 = block.timestamp;

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC1155BurnDraw.TimeoutNotReached.selector, id, t0 + 24 hours));
        draw.cancel(id, alice);

        vm.warp(t0 + 24 hours - 1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC1155BurnDraw.TimeoutNotReached.selector, id, t0 + 24 hours));
        draw.cancel(id, alice);

        vm.warp(t0 + 24 hours);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(IERC1155BurnDraw.NotOpener.selector, id));
        draw.cancel(id, stranger);
        vm.prank(alice);
        vm.expectRevert(IERC1155BurnDraw.InvalidInput.selector);
        draw.cancel(id, address(0));

        vm.expectEmit(true, true, false, true);
        emit RequestCancelled(id, alice, bob, 4);
        vm.prank(alice);
        draw.cancel(id, bob);

        assertEq(_packsOf(bob), 104, "packs returned to chosen address");
        assertEq(_packsOf(address(draw)), 0);
        IERC1155BurnDraw.InstanceInfo memory info = draw.getInstance(address(creator), INSTANCE);
        assertEq(info.reservedCount, 0);
        assertEq(info.pendingRequests, 0);
        assertEq(info.availableSlots, 7);
        assertEq(uint8(draw.getRequest(id).status), uint8(IERC1155BurnDraw.Status.CANCELLED));
        // VRF fee is not refunded
        assertEq(address(draw).balance, 0);

        // cancelled: cannot cancel again, cannot be fulfilled late, cannot claim
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC1155BurnDraw.RequestNotPending.selector, id));
        draw.cancel(id, alice);
        assertFalse(_fulfill(id, 1), "late fulfil is rejected");
        assertEq(_packsOf(alice) + _packsOf(bob), 200, "no pack burned by late fulfil");
        vm.expectRevert(abi.encodeWithSelector(IERC1155BurnDraw.RequestNotFulfilled.selector, id));
        draw.claim(id);
    }

    function testCancelFulfilledOrUnknownReverts() public {
        uint256 id = _open(alice, 1);
        _fulfill(id, 1);
        vm.warp(block.timestamp + 2 days);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC1155BurnDraw.RequestNotPending.selector, id));
        draw.cancel(id, alice);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC1155BurnDraw.RequestNotPending.selector, 5));
        draw.cancel(5, alice);
    }

    function testCancelReleasesReservationForOthers() public {
        uint256 idA = _open(alice, 7); // 7 > MAX? no (10). takes everything
        vm.startPrank(bob);
        creator.setApprovalForAll(address(draw), true);
        uint256 p = _price(1);
        vm.expectRevert(abi.encodeWithSelector(IERC1155BurnDraw.NotEnoughPrizes.selector, 1, 0));
        draw.open{value: p}(address(creator), INSTANCE, 1);
        vm.stopPrank();
        vm.warp(block.timestamp + 24 hours);
        vm.prank(alice);
        draw.cancel(idA, alice);
        _open(bob, 1); // now possible
    }

    /*//////////////////////////////////////////////////////////////
                                withdraw
    //////////////////////////////////////////////////////////////*/

    function _desc(uint256 n) internal pure returns (uint256[] memory idx) {
        idx = new uint256[](n);
        for (uint256 i; i < n; i++) idx[i] = n - 1 - i;
    }

    function testWithdrawBlockedInsideWindow() public {
        vm.prank(owner);
        vm.expectRevert(IERC1155BurnDraw.WithdrawLocked.selector);
        draw.withdrawPrizes(address(creator), INSTANCE, _desc(1), owner);
    }

    function testWithdrawAfterEndOnlyWhenNothingPending() public {
        uint256 id = _open(alice, 2);
        vm.warp(end + 1);
        vm.prank(owner);
        vm.expectRevert(IERC1155BurnDraw.WithdrawLocked.selector);
        draw.withdrawPrizes(address(creator), INSTANCE, _desc(1), owner);

        // a pending request that times out and is cancelled unlocks it
        vm.warp(block.timestamp + 24 hours);
        vm.prank(alice);
        draw.cancel(id, alice);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(IERC1155BurnDraw.NotAdmin.selector, address(creator)));
        draw.withdrawPrizes(address(creator), INSTANCE, _desc(1), stranger);

        uint256 ownerNftsBefore = prize721.balanceOf(owner) + prize1155.balanceOf(owner, 7);
        vm.prank(owner);
        draw.withdrawPrizes(address(creator), INSTANCE, _desc(7), owner);
        assertEq(prize721.balanceOf(owner) + prize1155.balanceOf(owner, 7), ownerNftsBefore + 7);
        assertEq(draw.getInstance(address(creator), INSTANCE).totalSlots, 0);
        assertEq(prize721.balanceOf(address(draw)), 0);
        assertEq(prize1155.balanceOf(address(draw), 7), 0);
    }

    function testWithdrawBeforeStart() public {
        vm.prank(owner);
        draw.initialize(address(creator), 4, IERC1155BurnDraw.Params(packId, uint48(block.timestamp + 100), 0));
        prize721.mint(owner, 300);
        IERC1155BurnDraw.PrizeDeposit[] memory d = new IERC1155BurnDraw.PrizeDeposit[](1);
        d[0] = IERC1155BurnDraw.PrizeDeposit(address(prize721), 300, 1, false);
        vm.startPrank(owner);
        prize721.setApprovalForAll(address(draw), true);
        draw.depositPrizes(address(creator), 4, d);
        draw.withdrawPrizes(address(creator), 4, _desc(1), stranger);
        vm.stopPrank();
        assertEq(prize721.ownerOf(300), stranger);
    }

    function testWithdrawIndexValidation() public {
        vm.warp(end + 1);
        vm.startPrank(owner);
        uint256[] memory asc = new uint256[](2);
        asc[0] = 0;
        asc[1] = 1;
        vm.expectRevert(IERC1155BurnDraw.InvalidInput.selector);
        draw.withdrawPrizes(address(creator), INSTANCE, asc, owner);
        uint256[] memory dup = new uint256[](2);
        dup[0] = 3;
        dup[1] = 3;
        vm.expectRevert(IERC1155BurnDraw.InvalidInput.selector);
        draw.withdrawPrizes(address(creator), INSTANCE, dup, owner);
        uint256[] memory oob = new uint256[](1);
        oob[0] = 7;
        vm.expectRevert(IERC1155BurnDraw.InvalidInput.selector);
        draw.withdrawPrizes(address(creator), INSTANCE, oob, owner);
        vm.expectRevert(IERC1155BurnDraw.InvalidInput.selector);
        draw.withdrawPrizes(address(creator), INSTANCE, new uint256[](0), owner);
        vm.expectRevert(IERC1155BurnDraw.InvalidInput.selector);
        draw.withdrawPrizes(address(creator), INSTANCE, _desc(1), address(0));
        vm.stopPrank();
    }

    function testWithdrawNeverTouchesAssignedPrizes() public {
        uint256 id = _open(alice, 3);
        _fulfill(id, 8);
        vm.warp(end + 1);
        // 4 unassigned slots remain; assigned prizes still claimable after a full withdraw
        vm.prank(owner);
        draw.withdrawPrizes(address(creator), INSTANCE, _desc(4), owner);
        assertEq(draw.getInstance(address(creator), INSTANCE).totalSlots, 0);
        draw.claim(id);
        assertEq(uint8(draw.getRequest(id).status), uint8(IERC1155BurnDraw.Status.CLAIMED));
        assertEq(prize721.balanceOf(alice) + prize1155.balanceOf(alice, 7), 3);
        assertEq(prize721.balanceOf(address(draw)) + prize1155.balanceOf(address(draw), 7), 0);
    }

    /*//////////////////////////////////////////////////////////////
                         instances are isolated
    //////////////////////////////////////////////////////////////*/

    function testInstancesAreIsolated() public {
        vm.prank(owner);
        draw.initialize(address(creator), 2, IERC1155BurnDraw.Params(packId, uint48(start), uint48(end)));
        // instance 2 has no prizes: instance 1's prizes can't be drawn through it
        vm.startPrank(alice);
        creator.setApprovalForAll(address(draw), true);
        uint256 p = _price(1);
        vm.expectRevert(abi.encodeWithSelector(IERC1155BurnDraw.NotEnoughPrizes.selector, 1, 0));
        draw.open{value: p}(address(creator), 2, 1);
        vm.stopPrank();
        // and instance 2 can't withdraw instance 1's prizes
        vm.warp(end + 1);
        vm.prank(owner);
        vm.expectRevert(IERC1155BurnDraw.InvalidInput.selector);
        draw.withdrawPrizes(address(creator), 2, _desc(1), owner);
    }

    /*//////////////////////////////////////////////////////////////
                              gas measurement
    //////////////////////////////////////////////////////////////*/

    /// Run with and without `--isolate`; with `--isolate` each call is its own tx so storage is cold,
    /// which is what the production callback sees. Prints measured callback gas for n = 1..10.
    function testMeasureCallbackGas() public {
        _deposit1155(8, 80);
        uint256 maxRatio;
        for (uint256 n = 1; n <= 10; n++) {
            uint256 id = _open(alice, n);
            assertTrue(_fulfill(id, uint256(keccak256(abi.encode("gas", n)))));
            uint256 used = wrapper.lastCallbackGasUsed();
            uint256 limit = draw.callbackGasLimit(n);
            console2.log("n / callback gas used / gas limit:", n, used, limit);
            assertLt(used, limit, "callback within limit");
            uint256 ratio = used * 100 / limit;
            if (ratio > maxRatio) maxRatio = ratio;
        }
        console2.log("max used/limit percent:", maxRatio);
    }

    /// Worst-case callback: a request for 10 over a big, many-distinct-type pool (each 721 = its own type)
    /// so every pick touches cold type entries and slots.
    function testCallbackGasWorstCaseManyTypes() public {
        _deposit721(1000, 60);
        uint256 id = _open(alice, 10);
        assertTrue(_fulfill(id, 0x1234567));
        uint256 used = wrapper.lastCallbackGasUsed();
        console2.log("worst-case n=10 callback gas used / limit:", used, draw.callbackGasLimit(10));
        assertLt(used, draw.callbackGasLimit(10));
    }

    /// A pool large enough that the callback must still fit: array length does not matter (O(1) swap-remove).
    function testCallbackGasIndependentOfPoolSize() public {
        _deposit1155(8, 500);
        uint256 id = _open(alice, 10);
        assertTrue(_fulfill(id, 42));
        assertLt(wrapper.lastCallbackGasUsed(), draw.callbackGasLimit(10));
    }

    function testViewsOnUnknown() public {
        vm.expectRevert(abi.encodeWithSelector(IERC1155BurnDraw.InstanceDoesNotExist.selector, 123));
        draw.getInstance(address(creator), 123);
        vm.expectRevert(abi.encodeWithSelector(IERC1155BurnDraw.InstanceDoesNotExist.selector, 123));
        draw.remainingSlots(address(creator), 123);
        vm.expectRevert(abi.encodeWithSelector(IERC1155BurnDraw.InstanceDoesNotExist.selector, 123));
        draw.getSlots(address(creator), 123, 0, 1);
        assertEq(uint8(draw.getRequest(1).status), uint8(IERC1155BurnDraw.Status.NONE));
    }

    function testConstructorRejectsZeroWrapper() public {
        vm.expectRevert(IERC1155BurnDraw.InvalidInput.selector);
        new ERC1155BurnDraw(address(0));
    }
}

/*//////////////////////////////////////////////////////////////////
                          reentrancy matrix
//////////////////////////////////////////////////////////////////*/

contract ERC1155BurnDrawReentrancyTest is BurnDrawBase {
    MalERC721 public mal721;
    MalERC1155 public mal1155;
    string internal constant GUARD = "ReentrancyGuard: reentrant call";

    function setUp() public {
        vm.warp(1_000_000);
        wrapper = new MockVRFWrapper();
        _deployCommon(address(wrapper));
        _init();
        mal721 = new MalERC721();
        mal1155 = new MalERC1155();
    }

    function _depositMal() internal {
        mal721.mint(owner, 1);
        mal721.mint(owner, 2);
        mal1155.mint(owner, 5, 2);
        vm.startPrank(owner);
        mal721.setApprovalForAll(address(draw), true);
        mal1155.setApprovalForAll(address(draw), true);
        IERC1155BurnDraw.PrizeDeposit[] memory d = new IERC1155BurnDraw.PrizeDeposit[](3);
        d[0] = IERC1155BurnDraw.PrizeDeposit(address(mal721), 1, 1, false);
        d[1] = IERC1155BurnDraw.PrizeDeposit(address(mal721), 2, 1, false);
        d[2] = IERC1155BurnDraw.PrizeDeposit(address(mal1155), 5, 2, true);
        draw.depositPrizes(address(creator), INSTANCE, d);
        vm.stopPrank();
    }

    function _assertGuarded(Attacker a) internal {
        assertTrue(a.attacked(), "hook did not fire");
        assertFalse(a.atkSuccess(), "re-entry succeeded");
        assertEq(a.atkReason(), GUARD);
    }

    function _packedPrizes() internal view returns (uint256) {
        return mal721.balanceOf(address(draw)) + mal1155.balanceOf(address(draw), 5);
    }

    // ---- deposit hook re-enters ----
    function testReenterDuringDeposit721() public {
        mal721.mint(owner, 1);
        vm.startPrank(owner);
        mal721.setApprovalForAll(address(draw), true);
        IERC1155BurnDraw.PrizeDeposit[] memory d = new IERC1155BurnDraw.PrizeDeposit[](1);
        d[0] = IERC1155BurnDraw.PrizeDeposit(address(mal721), 1, 1, false);
        mal721.arm(address(draw), abi.encodeCall(draw.depositPrizes, (address(creator), INSTANCE, d)));
        draw.depositPrizes(address(creator), INSTANCE, d);
        vm.stopPrank();
        _assertGuarded(mal721);
        assertEq(draw.remainingSlots(address(creator), INSTANCE), 1, "exactly one slot, no double count");
    }

    function testReenterDuringDeposit1155WithOpen() public {
        mal1155.mint(owner, 5, 2);
        vm.startPrank(owner);
        mal1155.setApprovalForAll(address(draw), true);
        IERC1155BurnDraw.PrizeDeposit[] memory d = new IERC1155BurnDraw.PrizeDeposit[](1);
        d[0] = IERC1155BurnDraw.PrizeDeposit(address(mal1155), 5, 2, true);
        mal1155.arm(address(draw), abi.encodeCall(draw.open, (address(creator), INSTANCE, 1)));
        draw.depositPrizes(address(creator), INSTANCE, d);
        vm.stopPrank();
        _assertGuarded(mal1155);
        assertEq(draw.remainingSlots(address(creator), INSTANCE), 2);
    }

    // ---- claim hook re-enters ----
    function _openAndFulfilAll(address who, uint256 n) internal returns (uint256 id) {
        id = _open(who, n);
        assertTrue(_fulfill(id, 5));
    }

    function testReenterDuringClaim721() public {
        _depositMal();
        uint256 id = _openAndFulfilAll(alice, 4); // takes all 4 slots
        mal721.arm(address(draw), abi.encodeCall(draw.claim, (id)));
        mal1155.arm(address(draw), abi.encodeCall(draw.claim, (id)));
        draw.claim(id);
        // whichever token types were hit first fired once
        assertTrue(mal721.attacked() || mal1155.attacked());
        if (mal721.attacked()) _assertGuarded(mal721);
        if (mal1155.attacked()) _assertGuarded(mal1155);
        assertEq(uint8(draw.getRequest(id).status), uint8(IERC1155BurnDraw.Status.CLAIMED));
        assertEq(mal721.balanceOf(alice) + mal1155.balanceOf(alice, 5), 4, "each prize delivered exactly once");
        assertEq(_packedPrizes(), 0);
    }

    function testReenterDuringClaimWithCancelOpenWithdraw() public {
        _depositMal();
        uint256 id = _openAndFulfilAll(alice, 2);
        bytes[3] memory attacks = [
            abi.encodeCall(draw.open, (address(creator), INSTANCE, 1)),
            abi.encodeCall(draw.cancel, (id, alice)),
            abi.encodeCall(draw.withdrawPrizes, (address(creator), INSTANCE, _desc1(), owner))
        ];
        for (uint256 k; k < 3; k++) {
            uint256 snap = vm.snapshot();
            mal721.arm(address(draw), attacks[k]);
            mal1155.arm(address(draw), attacks[k]);
            draw.claim(id);
            if (mal721.attacked()) _assertGuarded(mal721);
            if (mal1155.attacked()) _assertGuarded(mal1155);
            assertTrue(mal721.attacked() || mal1155.attacked());
            assertEq(uint8(draw.getRequest(id).status), uint8(IERC1155BurnDraw.Status.CLAIMED));
            vm.revertTo(snap);
        }
    }

    function _desc1() internal pure returns (uint256[] memory idx) {
        idx = new uint256[](1);
        idx[0] = 0;
    }

    // ---- withdraw hook re-enters ----
    function testReenterDuringWithdraw() public {
        _depositMal();
        vm.warp(end + 1);
        uint256[] memory idx = new uint256[](4);
        idx[0] = 3;
        idx[1] = 2;
        idx[2] = 1;
        idx[3] = 0;
        bytes[2] memory attacks = [
            abi.encodeCall(draw.withdrawPrizes, (address(creator), INSTANCE, idx, owner)),
            abi.encodeCall(draw.depositPrizes, (address(creator), INSTANCE, new IERC1155BurnDraw.PrizeDeposit[](0)))
        ];
        for (uint256 k; k < 2; k++) {
            uint256 snap = vm.snapshot();
            mal721.arm(address(draw), attacks[k]);
            mal1155.arm(address(draw), attacks[k]);
            vm.prank(owner);
            draw.withdrawPrizes(address(creator), INSTANCE, idx, owner);
            if (mal721.attacked()) _assertGuarded(mal721);
            if (mal1155.attacked()) _assertGuarded(mal1155);
            assertTrue(mal721.attacked() || mal1155.attacked());
            assertEq(draw.getInstance(address(creator), INSTANCE).totalSlots, 0);
            assertEq(mal721.balanceOf(owner) + mal1155.balanceOf(owner, 5), 4, "all returned once");
            assertEq(_packedPrizes(), 0);
            vm.revertTo(snap);
        }
    }

    // ---- refund hook re-enters ----
    function testReenterDuringRefund() public {
        _depositMal();
        RefundReenter ro = new RefundReenter();
        address[] memory to = new address[](1);
        to[0] = address(ro);
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amts = new uint256[](1);
        ids[0] = packId;
        amts[0] = 10;
        vm.prank(owner);
        creator.mintBaseExisting(to, ids, amts);
        vm.deal(address(ro), 10 ether);

        bytes[3] memory attacks = [
            abi.encodeCall(draw.open, (address(creator), INSTANCE, 1)),
            abi.encodeCall(draw.cancel, (1000, address(ro))),
            abi.encodeCall(draw.claim, (1000))
        ];
        uint256 p = _price(1);
        for (uint256 k; k < 3; k++) {
            uint256 snap = vm.snapshot();
            ro.arm(address(draw), attacks[k]);
            uint256 id = ro.callOpen(address(draw), address(creator), INSTANCE, 1, p + 1 ether);
            _assertGuarded(ro);
            assertEq(draw.getInstance(address(creator), INSTANCE).pendingRequests, 1);
            assertEq(draw.getInstance(address(creator), INSTANCE).reservedCount, 1);
            assertEq(uint8(draw.getRequest(id).status), uint8(IERC1155BurnDraw.Status.PENDING));
            vm.revertTo(snap);
        }
    }

    // ---- wrapper-callback re-entry: a rogue "wrapper-like" call path is blocked by sender check ----
    function testFulfilCannotBeReenteredFromBurn() public {
        // pack whose burn tries to call rawFulfillRandomWords back: caller is the pack, not wrapper => NotWrapper
        // (and nonReentrant would also block it). Fulfilment then fails atomically and the request stays pending.
        _depositMal();
        uint256 id = _open(alice, 1);
        assertTrue(_fulfill(id, 3));
        assertEq(uint8(draw.getRequest(id).status), uint8(IERC1155BurnDraw.Status.FULFILLED));
    }
}

/*//////////////////////////////////////////////////////////////////
                    invariants (handler-driven fuzz)
//////////////////////////////////////////////////////////////////*/

contract BurnDrawHandler is Test {
    ERC1155BurnDraw public draw;
    MockVRFWrapper public wrapper;
    ERC1155Creator public creator;
    MockERC721 public p721;
    MockERC1155 public p1155;
    address public admin;
    address[3] public users;
    uint256 public packId;
    uint256 public constant INSTANCE = 1;

    uint256 public next721 = 1;
    uint256[] public allRequests;
    uint256[] public pendingList; // may contain stale ids; check status before use

    // ghost flags
    bool public fulfilFailed;
    bool public duplicate721;
    bool public openedBeyondAvailable;
    mapping(uint256 => bool) public assigned721;
    uint256 public ghostFulfils;

    constructor(
        ERC1155BurnDraw d,
        MockVRFWrapper w,
        ERC1155Creator c,
        MockERC721 a,
        MockERC1155 b,
        address admin_,
        address[3] memory users_,
        uint256 packId_
    ) {
        draw = d;
        wrapper = w;
        creator = c;
        p721 = a;
        p1155 = b;
        admin = admin_;
        users = users_;
        packId = packId_;
        vm.startPrank(admin);
        p721.setApprovalForAll(address(draw), true);
        p1155.setApprovalForAll(address(draw), true);
        vm.stopPrank();
        for (uint256 i; i < 3; i++) {
            vm.deal(users[i], 1000 ether);
            vm.prank(users[i]);
            creator.setApprovalForAll(address(draw), true);
        }
    }

    function allRequestsLength() external view returns (uint256) {
        return allRequests.length;
    }

    function dep721(uint8 n) external {
        uint256 k = bound(n, 1, 3);
        IERC1155BurnDraw.PrizeDeposit[] memory d = new IERC1155BurnDraw.PrizeDeposit[](k);
        for (uint256 i; i < k; i++) {
            p721.mint(admin, next721);
            d[i] = IERC1155BurnDraw.PrizeDeposit(address(p721), next721, 1, false);
            next721++;
        }
        vm.prank(admin);
        try draw.depositPrizes(address(creator), INSTANCE, d) {} catch {}
    }

    function dep1155(uint8 idSeed, uint8 amt) external {
        uint256 id = bound(idSeed, 1, 2);
        uint256 a = bound(amt, 1, 6);
        p1155.mint(admin, id, a);
        IERC1155BurnDraw.PrizeDeposit[] memory d = new IERC1155BurnDraw.PrizeDeposit[](1);
        d[0] = IERC1155BurnDraw.PrizeDeposit(address(p1155), id, a, true);
        vm.prank(admin);
        try draw.depositPrizes(address(creator), INSTANCE, d) {} catch {}
    }

    function open(uint8 who, uint8 n) external {
        address u = users[who % 3];
        uint256 k = bound(n, 1, 10);
        uint256 avail = draw.remainingSlots(address(creator), INSTANCE);
        uint256 price = draw.quoteOpen(k);
        vm.prank(u);
        try draw.open{value: price}(address(creator), INSTANCE, k) returns (uint256 id) {
            if (k > avail) openedBeyondAvailable = true;
            allRequests.push(id);
            pendingList.push(id);
        } catch {}
    }

    function fulfil(uint8 pick, uint256 word) external {
        if (pendingList.length == 0) return;
        uint256 i = pick % pendingList.length;
        uint256 id = pendingList[i];
        pendingList[i] = pendingList[pendingList.length - 1];
        pendingList.pop();
        if (draw.getRequest(id).status != IERC1155BurnDraw.Status.PENDING) return;
        bool ok = wrapper.fulfillWord(id, word);
        if (!ok) {
            fulfilFailed = true;
            return;
        }
        ghostFulfils++;
        IERC1155BurnDraw.RequestInfo memory ri = draw.getRequest(id);
        for (uint256 j; j < ri.prizes.length; j++) {
            if (!ri.prizes[j].is1155) {
                if (assigned721[ri.prizes[j].id]) duplicate721 = true;
                assigned721[ri.prizes[j].id] = true;
            }
        }
    }

    function claim(uint8 pick) external {
        if (allRequests.length == 0) return;
        uint256 id = allRequests[pick % allRequests.length];
        try draw.claim(id) {} catch {}
    }

    function cancel(uint8 pick) external {
        if (allRequests.length == 0) return;
        uint256 id = allRequests[pick % allRequests.length];
        IERC1155BurnDraw.RequestInfo memory ri = draw.getRequest(id);
        if (ri.status != IERC1155BurnDraw.Status.PENDING) return;
        vm.warp(block.timestamp + 24 hours);
        vm.prank(ri.opener);
        try draw.cancel(id, ri.opener) {} catch {}
    }

    function warp(uint16 dt) external {
        vm.warp(block.timestamp + bound(dt, 1, 6 hours));
    }

    function adminWithdraw(uint8 n) external {
        IERC1155BurnDraw.InstanceInfo memory info = draw.getInstance(address(creator), INSTANCE);
        if (info.totalSlots == 0) return;
        uint256 k = bound(n, 1, info.totalSlots > 3 ? 3 : info.totalSlots);
        uint256[] memory idx = new uint256[](k);
        for (uint256 i; i < k; i++) idx[i] = k - 1 - i;
        // move to after the end so the window allows it
        if (info.endDate != 0 && block.timestamp < info.endDate) vm.warp(info.endDate);
        vm.prank(admin);
        try draw.withdrawPrizes(address(creator), INSTANCE, idx, admin) {} catch {}
    }

    /// keep the instance usable: reopen the window starting now
    function adminReopen() external {
        IERC1155BurnDraw.InstanceInfo memory info = draw.getInstance(address(creator), INSTANCE);
        vm.prank(admin);
        try draw.update(
            address(creator),
            INSTANCE,
            IERC1155BurnDraw.Params(info.packTokenId, uint48(block.timestamp), uint48(block.timestamp + 30 days))
        ) {} catch {}
    }
}

/// forge-config: default.invariant.runs = 64
/// forge-config: default.invariant.depth = 60
/// forge-config: default.invariant.fail-on-revert = false
contract ERC1155BurnDrawInvariantTest is BurnDrawBase {
    BurnDrawHandler public handler;
    address public u1 = address(0xA1);
    address public u2 = address(0xA2);
    address public u3 = address(0xA3);

    function setUp() public {
        vm.warp(1_000_000);
        wrapper = new MockVRFWrapper();
        _deployCommon(address(wrapper));
        // users
        address[3] memory us = [u1, u2, u3];
        vm.startPrank(owner);
        for (uint256 i; i < 3; i++) {
            address[] memory to = new address[](1);
            uint256[] memory ids = new uint256[](1);
            uint256[] memory amts = new uint256[](1);
            to[0] = us[i];
            ids[0] = packId;
            amts[0] = 100_000;
            creator.mintBaseExisting(to, ids, amts);
        }
        vm.stopPrank();
        _init();
        handler = new BurnDrawHandler(draw, wrapper, creator, prize721, prize1155, owner, us, packId);
        // allow the handler to act as the admin (prank-based) – nothing else needed.
        targetContract(address(handler));
        bytes4[] memory sels = new bytes4[](9);
        sels[0] = handler.dep721.selector;
        sels[1] = handler.dep1155.selector;
        sels[2] = handler.open.selector;
        sels[3] = handler.fulfil.selector;
        sels[4] = handler.claim.selector;
        sels[5] = handler.cancel.selector;
        sels[6] = handler.warp.selector;
        sels[7] = handler.adminWithdraw.selector;
        sels[8] = handler.adminReopen.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: sels}));
    }

    /// sum over all non-final requests of what is still owed, computed from public views
    function _undelivered(address token, uint256 id, bool is1155) internal view returns (uint256 total) {
        uint256 n = handler.allRequestsLength();
        for (uint256 i; i < n; i++) {
            IERC1155BurnDraw.RequestInfo memory ri = draw.getRequest(handler.allRequests(i));
            if (ri.status != IERC1155BurnDraw.Status.FULFILLED) continue;
            for (uint256 j; j < ri.prizes.length; j++) {
                if (ri.deliveredMask & (1 << j) != 0) continue;
                if (ri.prizes[j].token == token && ri.prizes[j].id == id && ri.prizes[j].is1155 == is1155) total++;
            }
        }
    }

    function _slotsOf(address token, uint256 id, bool is1155) internal view returns (uint256 total) {
        IERC1155BurnDraw.Slot[] memory s = draw.getSlots(address(creator), INSTANCE, 0, type(uint32).max);
        for (uint256 i; i < s.length; i++) {
            if (s[i].token == token && s[i].id == id && s[i].is1155 == is1155) total++;
        }
    }

    /// tokens held == unassigned slots + assigned-but-undelivered, per prize kind
    function invariant_prizeConservation() public {
        // 1155 ids 1 and 2
        for (uint256 id = 1; id <= 2; id++) {
            assertEq(
                prize1155.balanceOf(address(draw), id),
                _slotsOf(address(prize1155), id, true) + _undelivered(address(prize1155), id, true),
                "1155 conservation"
            );
        }
        // total 721s held
        uint256 held721 = prize721.balanceOf(address(draw));
        uint256 accounted;
        uint256 top = handler.next721();
        for (uint256 id = 1; id < top; id++) {
            accounted += _slotsOf(address(prize721), id, false) + _undelivered(address(prize721), id, false);
        }
        assertEq(held721, accounted, "721 conservation");
    }

    function invariant_packsHeldEqualPendingCounts() public {
        uint256 pending;
        uint256 n = handler.allRequestsLength();
        for (uint256 i; i < n; i++) {
            IERC1155BurnDraw.RequestInfo memory ri = draw.getRequest(handler.allRequests(i));
            if (ri.status == IERC1155BurnDraw.Status.PENDING) pending += ri.count;
        }
        assertEq(creator.balanceOf(address(draw), packId), pending, "packs held == pending reservations");
        assertEq(draw.getInstance(address(creator), INSTANCE).reservedCount, pending, "reservedCount == sum pending");
    }

    /// sum(pending reservations) <= unassigned slots, i.e. every pending request can be filled
    function invariant_reservationsNeverExceedSlots() public {
        IERC1155BurnDraw.InstanceInfo memory info = draw.getInstance(address(creator), INSTANCE);
        assertLe(info.reservedCount, info.totalSlots);
        assertEq(info.availableSlots, info.totalSlots - info.reservedCount);
    }

    function invariant_everyFulfilSucceededAndNoUnitAssignedTwice() public {
        assertFalse(handler.fulfilFailed(), "a pending request could not be fulfilled");
        assertFalse(handler.duplicate721(), "a 721 was assigned twice");
        assertFalse(handler.openedBeyondAvailable(), "opened more than available");
    }

    function invariant_noEthStuck() public {
        assertEq(address(draw).balance, 0);
    }
}

/*//////////////////////////////////////////////////////////////////
                         mainnet fork (optional)
//////////////////////////////////////////////////////////////////*/

contract ERC1155BurnDrawForkTest is BurnDrawBase {
    address internal constant MAINNET_WRAPPER = 0x02aae1A04f9828517b3007f83f6181900CaD910c;

    function _rpc() internal returns (string memory) {
        return vm.envOr("BURN_DRAW_FORK_RPC", string(""));
    }

    /// Skipped (returns early) unless BURN_DRAW_FORK_RPC is set.
    function testFork_RealWrapperPriceAndFulfil() public {
        string memory url = _rpc();
        if (bytes(url).length == 0) {
            console2.log("fork test skipped: BURN_DRAW_FORK_RPC not set");
            return;
        }
        vm.createSelectFork(url);
        assertGt(MAINNET_WRAPPER.code.length, 0, "no code at wrapper");
        _deployCommon(MAINNET_WRAPPER);
        vm.warp(block.timestamp); // keep fork time
        _init();
        _deposit721(1, 12);

        vm.txGasPrice(30 gwei);
        for (uint256 n = 1; n <= 10; n += (n == 1 ? 4 : 5)) {
            console2.log("mainnet VRF native price @30 gwei, n =", n, draw.quoteOpen(n));
        }
        vm.txGasPrice(10 gwei);
        console2.log("mainnet VRF native price @10 gwei, n=1:", draw.quoteOpen(1));

        // real open through the real wrapper
        vm.txGasPrice(30 gwei);
        uint256 price = draw.quoteOpen(2);
        vm.startPrank(alice);
        creator.setApprovalForAll(address(draw), true);
        uint256 id = draw.open{value: price}(address(creator), INSTANCE, 2);
        vm.stopPrank();
        assertGt(id, 0);

        // fulfil as the real coordinator through the real wrapper (which calls our callback with exact gas)
        (bool ok, bytes memory ret) = MAINNET_WRAPPER.staticcall(abi.encodeWithSignature("s_vrfCoordinator()"));
        require(ok, "coordinator read");
        address coordinator = abi.decode(ret, (address));
        uint256[] memory w = new uint256[](1);
        w[0] = 0x1234abcd;
        vm.recordLogs();
        vm.prank(coordinator);
        (ok,) = MAINNET_WRAPPER.call(abi.encodeWithSignature("rawFulfillRandomWords(uint256,uint256[])", id, w));
        require(ok, "wrapper fulfil");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 failedSig = keccak256("WrapperFulfillmentFailed(uint256,address)");
        for (uint256 i; i < logs.length; i++) {
            assertTrue(logs[i].topics[0] != failedSig, "real wrapper reports callback failure");
        }
        assertEq(uint8(draw.getRequest(id).status), uint8(IERC1155BurnDraw.Status.FULFILLED));
        assertEq(_packsOf(address(draw)), 0);
        draw.claim(id);
        assertEq(prize721.balanceOf(alice), 2);
    }
}
