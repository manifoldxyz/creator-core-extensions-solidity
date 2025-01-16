// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../contracts/burnredeemUpdatableFee/ERC721BurnRedeemV2.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC721Creator.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC1155Creator.sol";

import "../mocks/Mock.sol";

contract ManifoldERC721BurnRedeemV2Test is Test {
    ERC721BurnRedeemV2 public burnRedeem;
    ERC721Creator public creator;
    MockManifoldMembership public manifoldMembership;
    ERC721Creator public burnable721;
    ERC721Creator public burnable721_2;
    ERC1155Creator public burnable1155;
    ERC1155Creator public burnable1155_2;
    MockERC721 public oz721;
    MockERC1155 public oz1155;
    MockERC721Burnable public oz721Burnable;
    MockERC1155Burnable public oz1155Burnable;
    MockERC1155Fallback public fallback1155;
    MockERC1155FallbackBurnable public fallback1155Burnable;

    uint256 public defaultBurnFee = 690000000000000;
    uint256 public defaultMultiBurnFee = 990000000000000;

    address public owner = 0x6140F00e4Ff3936702E68744f2b5978885464cbB;
    address public burnRedeemOwner = 0xc78Dc443c126af6E4f6Ed540c1e740C1b5be09cd;
    address public anyone1 = 0x80AAC46bbd3C2FcE33681541a52CacBEd14bF425;
    address public anyone2 = 0x5174cD462b60c536eb51D4ceC1D561D3Ea31004F;

    address public zeroAddress = address(0);
    address public deadAddress = 0x000000000000000000000000000000000000dEaD;

    function setUp() public {
        vm.startPrank(owner);
        creator = new ERC721Creator("Test", "TEST");
        burnRedeem = new ERC721BurnRedeemV2(burnRedeemOwner);
        manifoldMembership = new MockManifoldMembership();
        burnable721 = new ERC721Creator("Test", "TEST");
        burnable721_2 = new ERC721Creator("Test", "TEST");
        burnable1155 = new ERC1155Creator("Test", "TEST");
        burnable1155_2 = new ERC1155Creator("Test", "TEST");
        oz721 = new MockERC721("Test", "TEST");
        oz1155 = new MockERC1155("test.com");
        oz721Burnable = new MockERC721Burnable("Test", "TEST");
        oz1155Burnable = new MockERC1155Burnable("test.com");
        fallback1155 = new MockERC1155Fallback("test.com");
        fallback1155Burnable = new MockERC1155FallbackBurnable("test.com");
        creator.registerExtension(address(burnRedeem), "");
        vm.stopPrank();

        vm.startPrank(burnRedeemOwner);
        burnRedeem.setMembershipAddress(address(manifoldMembership));
        burnRedeem.setBurnFees(defaultBurnFee, defaultMultiBurnFee);
        vm.stopPrank();
        vm.warp(100000);
    }

    function testAccess() public {
        IBurnRedeemCoreV2.BurnGroup[] memory group = new IBurnRedeemCoreV2.BurnGroup[](0);
        IBurnRedeemCoreV2.BurnRedeemParameters memory params = IBurnRedeemCoreV2.BurnRedeemParameters({
            paymentReceiver: payable(owner),
            storageProtocol: IBurnRedeemCoreV2.StorageProtocol.NONE,
            redeemAmount: 1,
            totalSupply: 1,
            startDate: uint48(block.timestamp - 30),
            endDate: uint48(block.timestamp + 1000),
            cost: 0,
            location: "",
            burnSet: group
        });

        // Must be admin
        vm.prank(anyone1);
        vm.expectRevert(abi.encodePacked(IBurnRedeemCoreV2.NotAdmin.selector, uint256(uint160(address(creator)))));
        burnRedeem.initializeBurnRedeem(address(creator), 1, params, true);

        // Succeeds because admin
        vm.prank(owner);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params, true);

        // Fails because not admin
        vm.prank(anyone1);
        vm.expectRevert(abi.encodePacked(IBurnRedeemCoreV2.NotAdmin.selector, uint256(uint160(address(creator)))));
        burnRedeem.updateBurnRedeem(address(creator), 1, params, true);

        // Only admin can set membership address and update fees
        vm.startPrank(owner);
        vm.expectRevert();
        burnRedeem.setMembershipAddress(address(manifoldMembership));
        vm.expectRevert();
        burnRedeem.setBurnFees(defaultBurnFee, defaultMultiBurnFee);
        vm.stopPrank();
    }

    function testInitializeSanitation() public {
        IBurnRedeemCoreV2.BurnGroup[] memory group = new IBurnRedeemCoreV2.BurnGroup[](0);
        IBurnRedeemCoreV2.BurnRedeemParameters memory params = IBurnRedeemCoreV2.BurnRedeemParameters({
            paymentReceiver: payable(owner),
            storageProtocol: IBurnRedeemCoreV2.StorageProtocol.NONE,
            redeemAmount: 1,
            totalSupply: 10,
            startDate: uint48(block.timestamp - 30),
            endDate: uint48(block.timestamp + 1000),
            cost: 0,
            location: "",
            burnSet: group
        });

        vm.startPrank(owner);

        params.endDate = uint48(block.timestamp - 60);
        // Fails due to endDate <= startDate
        vm.expectRevert(BurnRedeemLibV2.InvalidDates.selector);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params, true);


        // Fails due to non-mod-0 redeemAmount
        params.endDate = uint48(block.timestamp + 1000);
        params.redeemAmount = 3;
        vm.expectRevert(IBurnRedeemCoreV2.InvalidRedeemAmount.selector);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params, true);

        // Cannot update non-existant burn redeem
        vm.expectRevert(abi.encodePacked(IBurnRedeemCoreV2.BurnRedeemDoesNotExist.selector, uint256(1)));
        burnRedeem.updateBurnRedeem(address(creator), 1, params, true);

        // Cannot have amount == 0 on ERC1155 burn item
        IBurnRedeemCoreV2.BurnItem[] memory items = new IBurnRedeemCoreV2.BurnItem[](1);
        items[0] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.CONTRACT,
            contractAddress: address(burnable1155),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC1155,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.MANIFOLD,
            amount: 0,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        params.redeemAmount = 1;
        group = new IBurnRedeemCoreV2.BurnGroup[](1);
        group[0] = IBurnRedeemCoreV2.BurnGroup({
            requiredCount: 1,
            items: items
        });
        params.burnSet = group;
        vm.expectRevert(IBurnRedeemCoreV2.InvalidInput.selector);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params, true);

        // Cannot have ValidationType == INVALID on burn item
        items[0].amount = 1;
        items[0].validationType = IBurnRedeemCoreV2.ValidationType.INVALID;
        vm.expectRevert(IBurnRedeemCoreV2.InvalidInput.selector);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params, true);

        // Cannot have TokenSpec == INVALID on burn item
        items[0].validationType = IBurnRedeemCoreV2.ValidationType.CONTRACT;
        items[0].tokenSpec = IBurnRedeemCoreV2.TokenSpec.INVALID;
        vm.expectRevert(IBurnRedeemCoreV2.InvalidInput.selector);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params, true);

        // Cannot have requiredCount == 0 on burn group
        items[0].tokenSpec = IBurnRedeemCoreV2.TokenSpec.ERC1155;
        group[0].requiredCount = 0;
        vm.expectRevert(IBurnRedeemCoreV2.InvalidInput.selector);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params, true);

        // Cannot have requiredCount > items.length on burn group
        group[0].requiredCount = 2;
        vm.expectRevert(IBurnRedeemCoreV2.InvalidInput.selector);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params, true);

        vm.stopPrank();
    }

    function testUpdateSanitation() public {
        IBurnRedeemCoreV2.BurnGroup[] memory group = new IBurnRedeemCoreV2.BurnGroup[](0);
        IBurnRedeemCoreV2.BurnRedeemParameters memory params = IBurnRedeemCoreV2.BurnRedeemParameters({
            paymentReceiver: payable(owner),
            storageProtocol: IBurnRedeemCoreV2.StorageProtocol.NONE,
            redeemAmount: 1,
            totalSupply: 10,
            startDate: uint48(block.timestamp - 30),
            endDate: uint48(block.timestamp + 1000),
            cost: 0,
            location: "",
            burnSet: group
        });

        vm.deal(owner, 1 ether);
        vm.startPrank(owner);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params, true);

        params.endDate = uint48(block.timestamp - 60);
        // Fails due to endDate <= startDate
        vm.expectRevert(BurnRedeemLibV2.InvalidDates.selector);
        burnRedeem.updateBurnRedeem(address(creator), 1, params, true);

        // Fails due to non-mod-0 redeemAmount
        params.endDate = uint48(block.timestamp + 1000);
        params.redeemAmount = 3;
        vm.expectRevert(IBurnRedeemCoreV2.InvalidRedeemAmount.selector);
        burnRedeem.updateBurnRedeem(address(creator), 1, params, true);

        IBurnRedeemCoreV2.BurnToken[] memory tokens = new IBurnRedeemCoreV2.BurnToken[](0);
        uint256 burnFee = burnRedeem.BURN_FEE();
        burnRedeem.burnRedeem{value: burnFee*2}(address(creator), 1, 2, tokens);

        // Fails due to non-mod-0 redeemAmount after redemptions
        params.redeemAmount = 3;
        params.totalSupply = 9;
        vm.expectRevert(IBurnRedeemCoreV2.InvalidRedeemAmount.selector);
        burnRedeem.updateBurnRedeem(address(creator), 1, params, true);

        // totalSupply = redeemedCount if updated below redeemedCount
        params.redeemAmount = 1;
        params.totalSupply = 1;
        burnRedeem.updateBurnRedeem(address(creator), 1, params, true);
        IBurnRedeemCoreV2.BurnRedeem memory burnInstance = burnRedeem.getBurnRedeem(address(creator), 1);
        assertEq(burnInstance.totalSupply, 2);

        // totalSupply = 0 if updated to 0 and redeemedCount > 0
        params.totalSupply = 0;
        burnRedeem.updateBurnRedeem(address(creator), 1, params, true);
        burnInstance = burnRedeem.getBurnRedeem(address(creator), 1);
        assertEq(burnInstance.totalSupply, 0);

        vm.stopPrank();
    }

    function testTokenURI() public {
        IBurnRedeemCoreV2.BurnItem[] memory items = new IBurnRedeemCoreV2.BurnItem[](1);
        items[0] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.CONTRACT,
            contractAddress: address(burnable721),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC721,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.MANIFOLD,
            amount: 0,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        IBurnRedeemCoreV2.BurnGroup[] memory group = new IBurnRedeemCoreV2.BurnGroup[](1);
        group[0] = IBurnRedeemCoreV2.BurnGroup({
            requiredCount: 1,
            items: items
        });
        IBurnRedeemCoreV2.BurnRedeemParameters memory params = IBurnRedeemCoreV2.BurnRedeemParameters({
            paymentReceiver: payable(owner),
            storageProtocol: IBurnRedeemCoreV2.StorageProtocol.NONE,
            redeemAmount: 1,
            totalSupply: 10,
            startDate: uint48(block.timestamp - 30),
            endDate: uint48(block.timestamp + 1000),
            cost: 0,
            location: "XXX",
            burnSet: group
        });
        vm.startPrank(owner);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params, true);
        burnable721.mintBase(anyone1);
        vm.stopPrank();
        vm.deal(anyone1, 1 ether);
        vm.startPrank(anyone1);
        burnable721.setApprovalForAll(address(burnRedeem), true);
        bytes32[] memory merkleProof;
        IBurnRedeemCoreV2.BurnToken[] memory tokens = new IBurnRedeemCoreV2.BurnToken[](1);
        tokens[0] = IBurnRedeemCoreV2.BurnToken({
            groupIndex: 0,
            itemIndex: 0,
            contractAddress: address(burnable721),
            id: 1,
            merkleProof: merkleProof
        });
        uint256 burnFee = burnRedeem.BURN_FEE();
        burnRedeem.burnRedeem{value: burnFee}(address(creator), 1, 1, tokens);

        string memory uri = creator.tokenURI(1);
        assertEq(uri, "XXX");

        vm.stopPrank();

        vm.prank(owner);
        burnRedeem.updateBurnRedeem(address(creator), 1, params, false);
        uri = creator.tokenURI(1);
        assertEq(uri, "XXX/1");
    }

    function testTokenURIWithMintInBetween() public {
        IBurnRedeemCoreV2.BurnItem[] memory items = new IBurnRedeemCoreV2.BurnItem[](1);
        items[0] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.CONTRACT,
            contractAddress: address(burnable721),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC721,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.MANIFOLD,
            amount: 0,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        IBurnRedeemCoreV2.BurnGroup[] memory group = new IBurnRedeemCoreV2.BurnGroup[](1);
        group[0] = IBurnRedeemCoreV2.BurnGroup({
            requiredCount: 1,
            items: items
        });
        IBurnRedeemCoreV2.BurnRedeemParameters memory params = IBurnRedeemCoreV2.BurnRedeemParameters({
            paymentReceiver: payable(owner),
            storageProtocol: IBurnRedeemCoreV2.StorageProtocol.NONE,
            redeemAmount: 1,
            totalSupply: 10,
            startDate: uint48(block.timestamp - 30),
            endDate: uint48(block.timestamp + 1000),
            cost: 0,
            location: "XXX",
            burnSet: group
        });
        vm.startPrank(owner);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params, false);
        burnable721.mintBase(anyone1);
        burnable721.mintBase(anyone1);
        vm.stopPrank();

        vm.deal(anyone1, 1 ether);

        vm.prank(anyone1);
        burnable721.setApprovalForAll(address(burnRedeem), true);

        bytes32[] memory merkleProof;
        IBurnRedeemCoreV2.BurnToken[] memory tokens = new IBurnRedeemCoreV2.BurnToken[](1);
        tokens[0] = IBurnRedeemCoreV2.BurnToken({
            groupIndex: 0,
            itemIndex: 0,
            contractAddress: address(burnable721),
            id: 1,
            merkleProof: merkleProof
        });
        uint256 burnFee = burnRedeem.BURN_FEE();

        // Redeem first token
        vm.prank(anyone1);
        burnRedeem.burnRedeem{value: burnFee}(address(creator), 1, 1, tokens);
        string memory uri = creator.tokenURI(1);
        assertEq(uri, "XXX/1");

        vm.prank(owner);
        creator.mintBase(anyone1);

        // Redeem another token
        tokens[0].id = 2;
        vm.prank(anyone1);
        burnRedeem.burnRedeem{value: burnFee}(address(creator), 1, 1, tokens);
        uri = creator.tokenURI(3);
        assertEq(uri, "XXX/2");
    }

    function testBurnAnything() public {
        IBurnRedeemCoreV2.BurnItem[] memory items = new IBurnRedeemCoreV2.BurnItem[](6);
        // tokenSpec: ERC-721, burnSpec: NONE
        items[0] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.ANY,
            contractAddress: address(0),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC721,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.NONE,
            amount: 0,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        // tokenSpec: ERC-721, burnSpec: MANIFOLD
        items[1] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.ANY,
            contractAddress: address(0),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC721,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.MANIFOLD,
            amount: 0,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        // tokenSpec: ERC-721, burnSpec: OPENZEPPELIN
        items[2] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.ANY,
            contractAddress: address(0),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC721,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.OPENZEPPELIN,
            amount: 0,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        // tokenSpec: ERC-1155, burnSpec: NONE
        items[3] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.ANY,
            contractAddress: address(0),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC1155,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.NONE,
            amount: 1,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        // tokenSpec: ERC-1155, burnSpec: MANIFOLD
        items[4] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.ANY,
            contractAddress: address(0),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC1155,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.MANIFOLD,
            amount: 1,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        // tokenSpec: ERC-1155, burnSpec: OPENZEPPELIN
        items[5] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.ANY,
            contractAddress: address(0),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC1155,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.OPENZEPPELIN,
            amount: 1,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        IBurnRedeemCoreV2.BurnGroup[] memory group = new IBurnRedeemCoreV2.BurnGroup[](1);
        group[0] = IBurnRedeemCoreV2.BurnGroup({
            requiredCount: 1,
            items: items
        });
        IBurnRedeemCoreV2.BurnRedeemParameters memory params = IBurnRedeemCoreV2.BurnRedeemParameters({
            paymentReceiver: payable(owner),
            storageProtocol: IBurnRedeemCoreV2.StorageProtocol.NONE,
            redeemAmount: 1,
            totalSupply: 10,
            startDate: uint48(block.timestamp - 30),
            endDate: uint48(block.timestamp + 1000),
            cost: 0,
            location: "XXX",
            burnSet: group
        });
        vm.startPrank(owner);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params, false);

        // Mint tokens to anyone1
        oz721.mint(anyone1, 1);
        burnable721.mintBase(anyone1);
        oz721Burnable.mint(anyone1, 1);
        oz1155.mint(anyone1, 1, 1);
        address[] memory recipients = new address[](1);
        recipients[0] = anyone1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1;
        string[] memory uris = new string[](1);
        uris[0] = "";
        burnable1155.mintBaseNew(recipients, amounts, uris);
        oz1155Burnable.mint(anyone1, 1, 1);

        vm.stopPrank();

        vm.deal(anyone1, 1 ether);
        bytes32[] memory merkleProof;
        IBurnRedeemCoreV2.BurnToken[] memory tokens = new IBurnRedeemCoreV2.BurnToken[](1);
        tokens[0] = IBurnRedeemCoreV2.BurnToken({
            groupIndex: 0,
            itemIndex: 0,
            contractAddress: address(0),
            id: 1,
            merkleProof: merkleProof
        });
        uint256 burnFee = burnRedeem.BURN_FEE();

        vm.startPrank(anyone1);
        oz721.setApprovalForAll(address(burnRedeem), true);
        tokens[0].contractAddress = address(oz721);
        tokens[0].itemIndex = 0;
        burnRedeem.burnRedeem{value: burnFee}(address(creator), 1, 1, tokens);
        assertEq(0, oz721.balanceOf(anyone1));
        assertEq(1, oz721.balanceOf(address(0x000000000000000000000000000000000000dEaD)));

        burnable721.setApprovalForAll(address(burnRedeem), true);
        tokens[0].contractAddress = address(burnable721);
        tokens[0].itemIndex = 1;
        burnRedeem.burnRedeem{value: burnFee}(address(creator), 1, 1, tokens);
        vm.expectRevert("ERC721: invalid token ID");
        burnable721.ownerOf(1);

        oz721Burnable.setApprovalForAll(address(burnRedeem), true);
        tokens[0].contractAddress = address(oz721Burnable);
        tokens[0].itemIndex = 2;
        burnRedeem.burnRedeem{value: burnFee}(address(creator), 1, 1, tokens);
        vm.expectRevert("ERC721: invalid token ID");
        oz721Burnable.ownerOf(1);

        oz1155.setApprovalForAll(address(burnRedeem), true);
        tokens[0].contractAddress = address(oz1155);
        tokens[0].itemIndex = 3;
        burnRedeem.burnRedeem{value: burnFee}(address(creator), 1, 1, tokens);
        assertEq(0, oz1155.balanceOf(anyone1, 1));
        assertEq(1, oz1155.balanceOf(address(0x000000000000000000000000000000000000dEaD), 1));

        burnable1155.setApprovalForAll(address(burnRedeem), true);
        tokens[0].contractAddress = address(burnable1155);
        tokens[0].itemIndex = 4;
        burnRedeem.burnRedeem{value: burnFee}(address(creator), 1, 1, tokens);
        assertEq(0, burnable1155.balanceOf(anyone1, 1));
        assertEq(0, burnable1155.totalSupply(1));

        oz1155Burnable.setApprovalForAll(address(burnRedeem), true);
        tokens[0].contractAddress = address(oz1155Burnable);
        tokens[0].itemIndex = 5;
        burnRedeem.burnRedeem{value: burnFee}(address(creator), 1, 1, tokens);
        assertEq(0, oz1155Burnable.balanceOf(anyone1, 1));
        assertEq(0, oz1155Burnable.balanceOf(address(0x000000000000000000000000000000000000dEaD), 1));

        vm.stopPrank();
    }

    function testRedeemWithCustomDataEmitted() public {
        IBurnRedeemCoreV2.BurnItem[] memory items = new IBurnRedeemCoreV2.BurnItem[](1);
        items[0] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.CONTRACT,
            contractAddress: address(oz721),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC721,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.NONE,
            amount: 0,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        IBurnRedeemCoreV2.BurnGroup[] memory group = new IBurnRedeemCoreV2.BurnGroup[](1);
        group[0] = IBurnRedeemCoreV2.BurnGroup({
            requiredCount: 1,
            items: items
        });
        IBurnRedeemCoreV2.BurnRedeemParameters memory params = IBurnRedeemCoreV2.BurnRedeemParameters({
            paymentReceiver: payable(owner),
            storageProtocol: IBurnRedeemCoreV2.StorageProtocol.NONE,
            redeemAmount: 1,
            totalSupply: 10,
            startDate: uint48(block.timestamp - 30),
            endDate: uint48(block.timestamp + 1000),
            cost: 0,
            location: "XXX",
            burnSet: group
        });
        vm.startPrank(owner);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params, false);
        oz721.mint(anyone1, 1);
        oz721.mint(anyone1, 2);
        oz721.mint(anyone1, 3);
        vm.stopPrank();

        vm.deal(anyone1, 1 ether);

        vm.prank(anyone1);
        oz721.setApprovalForAll(address(burnRedeem), true);

        bytes memory message = bytes("test");
        bytes32[] memory merkleProof;
        IBurnRedeemCoreV2.BurnToken[] memory tokens = new IBurnRedeemCoreV2.BurnToken[](1);
        tokens[0] = IBurnRedeemCoreV2.BurnToken({
            groupIndex: 0,
            itemIndex: 0,
            contractAddress: address(oz721),
            id: 1,
            merkleProof: merkleProof
        });
        uint256 burnFee = burnRedeem.BURN_FEE();

        // Redeem first token
        vm.prank(anyone1);
        vm.expectEmit();
        emit BurnRedeemLibV2.BurnRedeemMint(address(creator), 1, 1, 1, message);
        burnRedeem.burnRedeemWithData{value: burnFee}(address(creator), 1, 1, tokens, message);
        assertEq(2, oz721.balanceOf(anyone1));
        assertEq(1, creator.balanceOf(anyone1));
    }

    function testContractsWithFallbackCannotBypass() public {
        IBurnRedeemCoreV2.BurnItem[] memory items = new IBurnRedeemCoreV2.BurnItem[](1);
        items[0] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.CONTRACT,
            contractAddress: address(fallback1155),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC1155,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.NONE,
            amount: 1,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        IBurnRedeemCoreV2.BurnGroup[] memory group = new IBurnRedeemCoreV2.BurnGroup[](1);
        group[0] = IBurnRedeemCoreV2.BurnGroup({
            requiredCount: 1,
            items: items
        });
        IBurnRedeemCoreV2.BurnRedeemParameters memory params = IBurnRedeemCoreV2.BurnRedeemParameters({
            paymentReceiver: payable(owner),
            storageProtocol: IBurnRedeemCoreV2.StorageProtocol.NONE,
            redeemAmount: 1,
            totalSupply: 10,
            startDate: uint48(block.timestamp - 30),
            endDate: uint48(block.timestamp + 1000),
            cost: 0,
            location: "XXX",
            burnSet: group
        });
        vm.startPrank(owner);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params, false);
        fallback1155.mint(anyone1, 1, 1);
        vm.stopPrank();

        vm.deal(anyone1, 1 ether);

        vm.prank(anyone1);
        fallback1155.setApprovalForAll(address(burnRedeem), true);
        bytes32[] memory merkleProof;
        IBurnRedeemCoreV2.BurnToken[] memory tokens = new IBurnRedeemCoreV2.BurnToken[](1);
        tokens[0] = IBurnRedeemCoreV2.BurnToken({
            groupIndex: 0,
            itemIndex: 0,
            contractAddress: address(fallback1155),
            id: 1,
            merkleProof: merkleProof
        });
        uint256 burnFee = burnRedeem.BURN_FEE();

        vm.prank(anyone1);
        burnRedeem.burnRedeem{value: burnFee}(address(creator), 1, 1, tokens);
        assertEq(1, fallback1155.balanceOf(address(0x000000000000000000000000000000000000dEaD), 1));
    }

    function testBurn721() public {
        /**
         *   const merkleElements = [];
         *   merkleElements.push(ethers.utils.solidityPack(["uint256"], [3]));
         *   merkleElements.push(ethers.utils.solidityPack(["uint256"], [10]));
         *   merkleElements.push(ethers.utils.solidityPack(["uint256"], [15]));
         *   merkleElements.push(ethers.utils.solidityPack(["uint256"], [20]));
         *   merkleTreeWithValues = new MerkleTree(merkleElements, keccak256, { hashLeaves: true, sortPairs: true });
         *   merkleRoot = merkleTreeWithValues.getHexRoot()
         */
        IBurnRedeemCoreV2.BurnItem[] memory items1 = new IBurnRedeemCoreV2.BurnItem[](1);
        items1[0] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.CONTRACT,
            contractAddress: address(burnable721),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC721,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.MANIFOLD,
            amount: 0,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        IBurnRedeemCoreV2.BurnItem[] memory items2 = new IBurnRedeemCoreV2.BurnItem[](2);
        items2[0] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.RANGE,
            contractAddress: address(burnable721_2),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC721,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.MANIFOLD,
            amount: 0,
            minTokenId: 1,
            maxTokenId: 2,
            merkleRoot: bytes32(0)
        });
        items2[1] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.MERKLE_TREE,
            contractAddress: address(burnable721_2),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC721,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.MANIFOLD,
            amount: 0,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0x9c1cfb2dc26ce204a49fc7b1a9b4e3a57e9344e39ee46ac2d6208d1c058e4bf0)
        });
        IBurnRedeemCoreV2.BurnGroup[] memory group = new IBurnRedeemCoreV2.BurnGroup[](2);
        group[0] = IBurnRedeemCoreV2.BurnGroup({
            requiredCount: 1,
            items: items1
        });
        group[1] = IBurnRedeemCoreV2.BurnGroup({
            requiredCount: 1,
            items: items2
        });
        IBurnRedeemCoreV2.BurnRedeemParameters memory params = IBurnRedeemCoreV2.BurnRedeemParameters({
            paymentReceiver: payable(owner),
            storageProtocol: IBurnRedeemCoreV2.StorageProtocol.NONE,
            redeemAmount: 1,
            totalSupply: 10,
            startDate: uint48(block.timestamp - 30),
            endDate: uint48(block.timestamp + 1000),
            cost: 0,
            location: "XXX",
            burnSet: group
        });
        vm.startPrank(owner);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params, false);
        for (uint256 i = 0; i < 4; i++) {
            burnable721.mintBase(anyone1);
            burnable721_2.mintBase(anyone1);
        }
        vm.stopPrank();

        vm.deal(anyone1, 1 ether);

        vm.startPrank(anyone1);
        burnable721.setApprovalForAll(address(burnRedeem), true);
        burnable721_2.setApprovalForAll(address(burnRedeem), true);

        bytes32[] memory merkleProof;
        bytes32[] memory merkleProofToken3 = new bytes32[](2);
        merkleProofToken3[0] = bytes32(0xc65a7bb8d6351c1cf70c95a316cc6a92839c986682d98bc35f958f4883f9d2a8);
        merkleProofToken3[1] = bytes32(0xe465c7176713655952e4cd0925e3c01b046d9399e14c8fcbea1a9839720e1928);

        IBurnRedeemCoreV2.BurnToken[] memory tokens = new IBurnRedeemCoreV2.BurnToken[](1);
        tokens[0] = IBurnRedeemCoreV2.BurnToken({
            groupIndex: 0,
            itemIndex: 0,
            contractAddress: address(burnable721),
            id: 1,
            merkleProof: merkleProof
        });
        uint256 burnFee = burnRedeem.MULTI_BURN_FEE();

        // Reverts due to unmet requirements
        vm.expectRevert(IBurnRedeemCoreV2.InvalidBurnAmount.selector);
        burnRedeem.burnRedeem{value: burnFee}(address(creator), 1, 1, tokens);

        // Reverts due to too many tokens
        tokens = new IBurnRedeemCoreV2.BurnToken[](3);
        tokens[0] = IBurnRedeemCoreV2.BurnToken({
            groupIndex: 0,
            itemIndex: 0,
            contractAddress: address(burnable721),
            id: 1,
            merkleProof: merkleProof
        });
        tokens[1] = IBurnRedeemCoreV2.BurnToken({
            groupIndex: 1,
            itemIndex: 0,
            contractAddress: address(burnable721_2),
            id: 1,
            merkleProof: merkleProof
        });
        tokens[2] = IBurnRedeemCoreV2.BurnToken({
            groupIndex: 1,
            itemIndex: 1,
            contractAddress: address(burnable721_2),
            id: 3,
            merkleProof: merkleProofToken3
        });
        vm.expectRevert(IBurnRedeemCoreV2.InvalidBurnAmount.selector);
        burnRedeem.burnRedeem{value: burnFee}(address(creator), 1, 1, tokens);

        // Reverts when token ID out of range
        tokens = new IBurnRedeemCoreV2.BurnToken[](2);
        tokens[0] = IBurnRedeemCoreV2.BurnToken({
            groupIndex: 0,
            itemIndex: 0,
            contractAddress: address(burnable721),
            id: 1,
            merkleProof: merkleProof
        });
        tokens[1] = IBurnRedeemCoreV2.BurnToken({
            groupIndex: 1,
            itemIndex: 0,
            contractAddress: address(burnable721_2),
            id: 3,
            merkleProof: merkleProof
        });
        vm.expectRevert(abi.encodePacked(IBurnRedeemCoreV2.InvalidToken.selector, uint256(3)));
        burnRedeem.burnRedeem{value: burnFee}(address(creator), 1, 1, tokens);

        // Reverts with invalid merkle proof
        tokens = new IBurnRedeemCoreV2.BurnToken[](2);
        tokens[0] = IBurnRedeemCoreV2.BurnToken({
            groupIndex: 0,
            itemIndex: 0,
            contractAddress: address(burnable721),
            id: 1,
            merkleProof: merkleProof
        });
        tokens[1] = IBurnRedeemCoreV2.BurnToken({
            groupIndex: 1,
            itemIndex: 1,
            contractAddress: address(burnable721_2),
            id: 2,
            merkleProof: merkleProof
        });
        vm.expectRevert(BurnRedeemLibV2.InvalidMerkleProof.selector);
        burnRedeem.burnRedeem{value: burnFee}(address(creator), 1, 1, tokens);

        // Reverts due to no fee
        tokens = new IBurnRedeemCoreV2.BurnToken[](2);
        tokens[0] = IBurnRedeemCoreV2.BurnToken({
            groupIndex: 0,
            itemIndex: 0,
            contractAddress: address(burnable721),
            id: 1,
            merkleProof: merkleProof
        });
        tokens[1] = IBurnRedeemCoreV2.BurnToken({
            groupIndex: 1,
            itemIndex: 0,
            contractAddress: address(burnable721_2),
            id: 1,
            merkleProof: merkleProof
        });
        vm.expectRevert(IBurnRedeemCoreV2.InvalidPaymentAmount.selector);
        burnRedeem.burnRedeem(address(creator), 1, 1, tokens);

        // Reverts when msg.sender is not token owner, but tokens are approved
        vm.stopPrank();
        vm.deal(anyone2, 1 ether);
        vm.prank(anyone2);
        vm.expectRevert(IBurnRedeemCoreV2.TransferFailure.selector);
        burnRedeem.burnRedeem{value: burnFee}(address(creator), 1, 1, tokens);

        // Reverts with burnCount > 1
        vm.startPrank(anyone1);
        vm.expectRevert(IBurnRedeemCoreV2.InvalidBurnAmount.selector);
        burnRedeem.burnRedeem{value: burnFee*2}(address(creator), 1, 2, tokens);

        // Passes with met requirements - range
        burnRedeem.burnRedeem{value: burnFee}(address(creator), 1, 1, tokens);

        (uint256 burnInstanceId, IBurnRedeemCoreV2.BurnRedeem memory burnInstance) = burnRedeem.getBurnRedeemForToken(address(creator), 1);
        assertEq(burnInstanceId, 1);
        assertEq(burnInstance.contractVersion, 3);

        // Passes with met requirements - merkle tree
        tokens[0].id = 2;
        tokens[1].itemIndex = 1;
        tokens[1].id = 3;
        tokens[1].merkleProof = merkleProofToken3;
        burnRedeem.burnRedeem{value: burnFee}(address(creator), 1, 1, tokens);

        // Ensure tokens are burned/minted
        assertEq(2, burnable721.balanceOf(anyone1));
        assertEq(2, burnable721_2.balanceOf(anyone1));
        assertEq(2, creator.balanceOf(anyone1));
        vm.stopPrank();
    }

    function testBurn721BurnSpecNone() public {
        IBurnRedeemCoreV2.BurnItem[] memory items = new IBurnRedeemCoreV2.BurnItem[](1);
        items[0] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.CONTRACT,
            contractAddress: address(oz721),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC721,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.NONE,
            amount: 0,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        IBurnRedeemCoreV2.BurnGroup[] memory group = new IBurnRedeemCoreV2.BurnGroup[](1);
        group[0] = IBurnRedeemCoreV2.BurnGroup({
            requiredCount: 1,
            items: items
        });
        IBurnRedeemCoreV2.BurnRedeemParameters memory params = IBurnRedeemCoreV2.BurnRedeemParameters({
            paymentReceiver: payable(owner),
            storageProtocol: IBurnRedeemCoreV2.StorageProtocol.NONE,
            redeemAmount: 1,
            totalSupply: 10,
            startDate: uint48(block.timestamp - 30),
            endDate: uint48(block.timestamp + 1000),
            cost: 0,
            location: "XXX",
            burnSet: group
        });
        vm.startPrank(owner);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params, false);
        for (uint256 i = 0; i < 4; i++) {
            oz721.mint(anyone1, i);
        }
        vm.stopPrank();

        vm.deal(anyone1, 1 ether);

        vm.startPrank(anyone1);
        oz721.setApprovalForAll(address(burnRedeem), true);

        // Reverts due to unmet requirements
        bytes32[] memory merkleProof;

        IBurnRedeemCoreV2.BurnToken[] memory tokens = new IBurnRedeemCoreV2.BurnToken[](1);
        tokens[0] = IBurnRedeemCoreV2.BurnToken({
            groupIndex: 0,
            itemIndex: 0,
            contractAddress: address(oz721),
            id: 1,
            merkleProof: merkleProof
        });
        uint256 burnFee = burnRedeem.BURN_FEE();

        // Passes with met requirements - range
        burnRedeem.burnRedeem{value: burnFee}(address(creator), 1, 1, tokens);
        // Ensure tokens are burned/minted
        assertEq(3, oz721.balanceOf(anyone1));
        assertEq(1, oz721.balanceOf(address(0xdead)));
        assertEq(1, creator.balanceOf(anyone1));
        vm.stopPrank();
    }

    function testBurn721BurnSpecOpenzeppelin() public {
        IBurnRedeemCoreV2.BurnItem[] memory items = new IBurnRedeemCoreV2.BurnItem[](1);
        items[0] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.CONTRACT,
            contractAddress: address(oz721Burnable),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC721,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.OPENZEPPELIN,
            amount: 0,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        IBurnRedeemCoreV2.BurnGroup[] memory group = new IBurnRedeemCoreV2.BurnGroup[](1);
        group[0] = IBurnRedeemCoreV2.BurnGroup({
            requiredCount: 1,
            items: items
        });
        IBurnRedeemCoreV2.BurnRedeemParameters memory params = IBurnRedeemCoreV2.BurnRedeemParameters({
            paymentReceiver: payable(owner),
            storageProtocol: IBurnRedeemCoreV2.StorageProtocol.NONE,
            redeemAmount: 1,
            totalSupply: 10,
            startDate: uint48(block.timestamp - 30),
            endDate: uint48(block.timestamp + 1000),
            cost: 0,
            location: "XXX",
            burnSet: group
        });
        vm.startPrank(owner);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params, false);
        for (uint256 i = 0; i < 4; i++) {
            oz721Burnable.mint(anyone1, i);
        }
        vm.stopPrank();

        vm.deal(anyone1, 1 ether);

        vm.startPrank(anyone1);
        oz721Burnable.setApprovalForAll(address(burnRedeem), true);

        // Reverts due to unmet requirements
        bytes32[] memory merkleProof;

        IBurnRedeemCoreV2.BurnToken[] memory tokens = new IBurnRedeemCoreV2.BurnToken[](1);
        tokens[0] = IBurnRedeemCoreV2.BurnToken({
            groupIndex: 0,
            itemIndex: 0,
            contractAddress: address(oz721Burnable),
            id: 1,
            merkleProof: merkleProof
        });
        uint256 burnFee = burnRedeem.BURN_FEE();

        // Passes with met requirement
        burnRedeem.burnRedeem{value: burnFee}(address(creator), 1, 1, tokens);
        // Ensure tokens are burned/minted
        assertEq(3, oz721Burnable.balanceOf(anyone1));
        assertEq(0, oz721Burnable.balanceOf(address(0xdead)));
        assertEq(1, creator.balanceOf(anyone1));
        vm.stopPrank();
    }

    function testBurn1155() public {
        /**
         *   const merkleElements = [];
         *   merkleElements.push(ethers.utils.solidityPack(["uint256"], [2]));
         *   merkleElements.push(ethers.utils.solidityPack(["uint256"], [10]));
         *   merkleElements.push(ethers.utils.solidityPack(["uint256"], [15]));
         *   merkleElements.push(ethers.utils.solidityPack(["uint256"], [20]));
         *   merkleTreeWithValues = new MerkleTree(merkleElements, keccak256, { hashLeaves: true, sortPairs: true });
         *   merkleRoot = merkleTreeWithValues.getHexRoot()
         */

        IBurnRedeemCoreV2.BurnItem[] memory items1 = new IBurnRedeemCoreV2.BurnItem[](1);
        items1[0] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.CONTRACT,
            contractAddress: address(burnable1155_2),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC1155,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.MANIFOLD,
            amount: 2,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        IBurnRedeemCoreV2.BurnItem[] memory items2 = new IBurnRedeemCoreV2.BurnItem[](1);
        items2[0] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.RANGE,
            contractAddress: address(burnable1155),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC1155,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.MANIFOLD,
            amount: 1,
            minTokenId: 1,
            maxTokenId: 2,
            merkleRoot: bytes32(0)
        });
        IBurnRedeemCoreV2.BurnItem[] memory items3 = new IBurnRedeemCoreV2.BurnItem[](2);
        items3[0] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.MERKLE_TREE,
            contractAddress: address(burnable1155),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC1155,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.MANIFOLD,
            amount: 1,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0xa0e5e9d42a6adc6538b879161a5503e44aacae809116f3c8f0507a06728a04fc)
        });
        items3[1] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.CONTRACT,
            contractAddress: address(burnable721),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC721,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.MANIFOLD,
            amount: 0,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        IBurnRedeemCoreV2.BurnGroup[] memory group = new IBurnRedeemCoreV2.BurnGroup[](3);
        group[0] = IBurnRedeemCoreV2.BurnGroup({
            requiredCount: 1,
            items: items1
        });
        group[1] = IBurnRedeemCoreV2.BurnGroup({
            requiredCount: 1,
            items: items2
        });
        group[2] = IBurnRedeemCoreV2.BurnGroup({
            requiredCount: 1,
            items: items3
        });
        IBurnRedeemCoreV2.BurnRedeemParameters memory params = IBurnRedeemCoreV2.BurnRedeemParameters({
            paymentReceiver: payable(owner),
            storageProtocol: IBurnRedeemCoreV2.StorageProtocol.NONE,
            redeemAmount: 1,
            totalSupply: 10,
            startDate: uint48(block.timestamp - 30),
            endDate: uint48(block.timestamp + 1000),
            cost: 0,
            location: "XXX",
            burnSet: group
        });
        vm.startPrank(owner);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params, false);
        address[] memory recipients = new address[](1);
        recipients[0] = anyone1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10;
        string[] memory uris = new string[](1);
        uris[0] = "";
        burnable1155.mintBaseNew(recipients, amounts, uris);
        burnable1155.mintBaseNew(recipients, amounts, uris);
        burnable1155_2.mintBaseNew(recipients, amounts, uris);
        burnable721.mintBase(anyone1);
        vm.stopPrank();

        vm.deal(anyone1, 1 ether);

        vm.startPrank(anyone1);
        burnable1155.setApprovalForAll(address(burnRedeem), true);
        burnable1155_2.setApprovalForAll(address(burnRedeem), true);
        burnable721.setApprovalForAll(address(burnRedeem), true);

        // Reverts due to unmet requirements
        bytes32[] memory merkleProof;
        bytes32[] memory merkleProofToken2 = new bytes32[](2);
        merkleProofToken2[0] = bytes32(0xc65a7bb8d6351c1cf70c95a316cc6a92839c986682d98bc35f958f4883f9d2a8);
        merkleProofToken2[1] = bytes32(0xe465c7176713655952e4cd0925e3c01b046d9399e14c8fcbea1a9839720e1928);

        IBurnRedeemCoreV2.BurnToken[] memory tokens = new IBurnRedeemCoreV2.BurnToken[](3);
        tokens[0] = IBurnRedeemCoreV2.BurnToken({
            groupIndex: 0,
            itemIndex: 0,
            contractAddress: address(burnable1155_2),
            id: 1,
            merkleProof: merkleProof
        });
        tokens[1] = IBurnRedeemCoreV2.BurnToken({
            groupIndex: 1,
            itemIndex: 0,
            contractAddress: address(burnable1155),
            id: 1,
            merkleProof: merkleProof
        });
        tokens[2] = IBurnRedeemCoreV2.BurnToken({
            groupIndex: 2,
            itemIndex: 1,
            contractAddress: address(burnable721),
            id: 1,
            merkleProof: merkleProof
        });
        uint256 burnFee = burnRedeem.MULTI_BURN_FEE();

        // Reverts with burnCount > 1 if 721 is in burnTokens
        vm.expectRevert(IBurnRedeemCoreV2.InvalidBurnAmount.selector);
        burnRedeem.burnRedeem{value: burnFee*2}(address(creator), 1, 2, tokens);

        // Passes with burnCount > 1
        tokens[2].itemIndex = 0;
        tokens[2].contractAddress = address(burnable1155);
        tokens[2].id = 2;
        tokens[2].merkleProof = merkleProofToken2;
        burnRedeem.burnRedeem{value: burnFee*3}(address(creator), 1, 3, tokens);

        
        // Ensure tokens are burned/minted
        assertEq(7, burnable1155.balanceOf(anyone1, 1));
        assertEq(7, burnable1155.balanceOf(anyone1, 2));
        assertEq(4, burnable1155_2.balanceOf(anyone1, 1));
        assertEq(3, creator.balanceOf(anyone1));

        vm.stopPrank();
    }

    function testBurn1155BurnSpecNone() public {
        IBurnRedeemCoreV2.BurnItem[] memory items = new IBurnRedeemCoreV2.BurnItem[](1);
        items[0] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.CONTRACT,
            contractAddress: address(oz1155),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC1155,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.NONE,
            amount: 1,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        IBurnRedeemCoreV2.BurnGroup[] memory group = new IBurnRedeemCoreV2.BurnGroup[](1);
        group[0] = IBurnRedeemCoreV2.BurnGroup({
            requiredCount: 1,
            items: items
        });
        IBurnRedeemCoreV2.BurnRedeemParameters memory params = IBurnRedeemCoreV2.BurnRedeemParameters({
            paymentReceiver: payable(owner),
            storageProtocol: IBurnRedeemCoreV2.StorageProtocol.NONE,
            redeemAmount: 1,
            totalSupply: 10,
            startDate: uint48(block.timestamp - 30),
            endDate: uint48(block.timestamp + 1000),
            cost: 0,
            location: "XXX",
            burnSet: group
        });
        vm.startPrank(owner);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params, false);
        oz1155.mint(anyone1, 1, 3);
        vm.stopPrank();

        vm.deal(anyone1, 1 ether);

        vm.startPrank(anyone1);
        oz1155.setApprovalForAll(address(burnRedeem), true);

        bytes32[] memory merkleProof;
        IBurnRedeemCoreV2.BurnToken[] memory tokens = new IBurnRedeemCoreV2.BurnToken[](1);
        tokens[0] = IBurnRedeemCoreV2.BurnToken({
            groupIndex: 0,
            itemIndex: 0,
            contractAddress: address(oz1155),
            id: 1,
            merkleProof: merkleProof
        });
        uint256 burnFee = burnRedeem.BURN_FEE();

        // Passes with met requirements
        burnRedeem.burnRedeem{value: burnFee}(address(creator), 1, 1, tokens);
        // Ensure tokens are burned/minted
        assertEq(2, oz1155.balanceOf(anyone1, 1));
        assertEq(1, oz1155.balanceOf(address(0xdead), 1));
        assertEq(1, creator.balanceOf(anyone1));
        vm.stopPrank();
    }

    function testBurn1155BurnSpecOpenzeppelin() public {
        IBurnRedeemCoreV2.BurnItem[] memory items = new IBurnRedeemCoreV2.BurnItem[](1);
        items[0] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.CONTRACT,
            contractAddress: address(oz1155Burnable),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC1155,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.OPENZEPPELIN,
            amount: 1,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        IBurnRedeemCoreV2.BurnGroup[] memory group = new IBurnRedeemCoreV2.BurnGroup[](1);
        group[0] = IBurnRedeemCoreV2.BurnGroup({
            requiredCount: 1,
            items: items
        });
        IBurnRedeemCoreV2.BurnRedeemParameters memory params = IBurnRedeemCoreV2.BurnRedeemParameters({
            paymentReceiver: payable(owner),
            storageProtocol: IBurnRedeemCoreV2.StorageProtocol.NONE,
            redeemAmount: 1,
            totalSupply: 10,
            startDate: uint48(block.timestamp - 30),
            endDate: uint48(block.timestamp + 1000),
            cost: 0,
            location: "XXX",
            burnSet: group
        });
        vm.startPrank(owner);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params, false);
        oz1155Burnable.mint(anyone1, 1, 3);
        vm.stopPrank();

        vm.deal(anyone1, 1 ether);

        vm.startPrank(anyone1);
        oz1155Burnable.setApprovalForAll(address(burnRedeem), true);

        bytes32[] memory merkleProof;
        IBurnRedeemCoreV2.BurnToken[] memory tokens = new IBurnRedeemCoreV2.BurnToken[](1);
        tokens[0] = IBurnRedeemCoreV2.BurnToken({
            groupIndex: 0,
            itemIndex: 0,
            contractAddress: address(oz1155Burnable),
            id: 1,
            merkleProof: merkleProof
        });
        uint256 burnFee = burnRedeem.BURN_FEE();

        // Passes with met requirements
        burnRedeem.burnRedeem{value: burnFee}(address(creator), 1, 1, tokens);
        // Ensure tokens are burned/minted
        assertEq(2, oz1155Burnable.balanceOf(anyone1, 1));
        assertEq(0, oz1155Burnable.balanceOf(address(0xdead), 1));
        assertEq(1, creator.balanceOf(anyone1));
        vm.stopPrank();
    }

    function testRedeemAmountMoreThanOne() public {
        IBurnRedeemCoreV2.BurnItem[] memory items = new IBurnRedeemCoreV2.BurnItem[](1);
        items[0] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.CONTRACT,
            contractAddress: address(burnable721),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC721,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.NONE,
            amount: 0,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        IBurnRedeemCoreV2.BurnGroup[] memory group = new IBurnRedeemCoreV2.BurnGroup[](1);
        group[0] = IBurnRedeemCoreV2.BurnGroup({
            requiredCount: 1,
            items: items
        });
        IBurnRedeemCoreV2.BurnRedeemParameters memory params = IBurnRedeemCoreV2.BurnRedeemParameters({
            paymentReceiver: payable(owner),
            storageProtocol: IBurnRedeemCoreV2.StorageProtocol.NONE,
            redeemAmount: 2,
            totalSupply: 10,
            startDate: uint48(block.timestamp - 30),
            endDate: uint48(block.timestamp + 1000),
            cost: 0,
            location: "XXX",
            burnSet: group
        });
        vm.startPrank(owner);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params, false);
        burnable721.mintBase(anyone1);
        vm.stopPrank();

        vm.deal(anyone1, 1 ether);

        vm.startPrank(anyone1);
        burnable721.setApprovalForAll(address(burnRedeem), true);

        bytes32[] memory merkleProof;
        IBurnRedeemCoreV2.BurnToken[] memory tokens = new IBurnRedeemCoreV2.BurnToken[](1);
        tokens[0] = IBurnRedeemCoreV2.BurnToken({
            groupIndex: 0,
            itemIndex: 0,
            contractAddress: address(burnable721),
            id: 1,
            merkleProof: merkleProof
        });
        uint256 burnFee = burnRedeem.BURN_FEE();

        // Passes with met requirements
        burnRedeem.burnRedeem{value: burnFee}(address(creator), 1, 1, tokens);
        // Ensure tokens are burned/minted
        assertEq(0, burnable721.balanceOf(anyone1));
        assertEq(2, creator.balanceOf(anyone1));
        vm.stopPrank();
    }

    function testMaliciousSenderReverts() public {
        IBurnRedeemCoreV2.BurnItem[] memory items = new IBurnRedeemCoreV2.BurnItem[](1);
        items[0] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.CONTRACT,
            contractAddress: address(burnable721),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC721,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.NONE,
            amount: 0,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        IBurnRedeemCoreV2.BurnGroup[] memory group = new IBurnRedeemCoreV2.BurnGroup[](1);
        group[0] = IBurnRedeemCoreV2.BurnGroup({
            requiredCount: 1,
            items: items
        });
        IBurnRedeemCoreV2.BurnRedeemParameters memory params = IBurnRedeemCoreV2.BurnRedeemParameters({
            paymentReceiver: payable(owner),
            storageProtocol: IBurnRedeemCoreV2.StorageProtocol.NONE,
            redeemAmount: 1,
            totalSupply: 10,
            startDate: uint48(block.timestamp - 30),
            endDate: uint48(block.timestamp + 1000),
            cost: 0,
            location: "XXX",
            burnSet: group
        });
        vm.startPrank(owner);
        // Burn #1
        burnRedeem.initializeBurnRedeem(address(creator), 1, params, false);
        // Burn #2
        items[0].contractAddress = address(burnable1155);
        items[0].tokenSpec = IBurnRedeemCoreV2.TokenSpec.ERC1155;
        items[0].amount = 1;
        burnRedeem.initializeBurnRedeem(address(creator), 2, params, false);
        // Burn #3
        items[0].burnSpec = IBurnRedeemCoreV2.BurnSpec.MANIFOLD;
        burnRedeem.initializeBurnRedeem(address(creator), 3, params, false);

        burnable721.mintBase(anyone1);
        address[] memory recipients = new address[](1);
        recipients[0] = anyone1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 2;
        string[] memory uris = new string[](1);
        uris[0] = "";
        burnable1155.mintBaseNew(recipients, amounts, uris);
        vm.stopPrank();

        vm.deal(anyone1, 1 ether);
        vm.deal(anyone2, 1 ether);

        vm.startPrank(anyone1);
        burnable721.setApprovalForAll(address(burnRedeem), true);
        burnable1155.setApprovalForAll(address(burnRedeem), true);
        vm.stopPrank();

        bytes32[] memory merkleProof;
        IBurnRedeemCoreV2.BurnToken[] memory tokens = new IBurnRedeemCoreV2.BurnToken[](1);
        tokens[0] = IBurnRedeemCoreV2.BurnToken({
            groupIndex: 0,
            itemIndex: 0,
            contractAddress: address(burnable721),
            id: 1,
            merkleProof: merkleProof
        });
        uint256 burnFee = burnRedeem.BURN_FEE();

        // Reverts when msg.sender is not token owner, but tokens are approved
        // 721 with no burn
        vm.prank(anyone2);
        vm.expectRevert("ERC721: transfer from incorrect owner");
        burnRedeem.burnRedeem{value: burnFee}(address(creator), 1, 1, tokens);
        // 1155 with no burn
        tokens[0].contractAddress = address(burnable1155);
        vm.expectRevert("ERC1155: caller is not token owner or approved");
        burnRedeem.burnRedeem{value: burnFee}(address(creator), 2, 1, tokens);
        // 1155 with burn
        vm.expectRevert("Caller is not owner or approved");
        burnRedeem.burnRedeem{value: burnFee}(address(creator), 3, 1, tokens);
    }

    function testBurnRedeemWithCost() public {
        IBurnRedeemCoreV2.BurnItem[] memory items = new IBurnRedeemCoreV2.BurnItem[](2);
        uint160 cost = 1000000000000000000;
        items[0] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.CONTRACT,
            contractAddress: address(burnable721),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC721,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.MANIFOLD,
            amount: 0,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        items[1] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.CONTRACT,
            contractAddress: address(burnable1155),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC1155,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.MANIFOLD,
            amount: 1,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        IBurnRedeemCoreV2.BurnGroup[] memory group = new IBurnRedeemCoreV2.BurnGroup[](1);
        group[0] = IBurnRedeemCoreV2.BurnGroup({
            requiredCount: 1,
            items: items
        });
        IBurnRedeemCoreV2.BurnRedeemParameters memory params = IBurnRedeemCoreV2.BurnRedeemParameters({
            paymentReceiver: payable(owner),
            storageProtocol: IBurnRedeemCoreV2.StorageProtocol.NONE,
            redeemAmount: 1,
            totalSupply: 10,
            startDate: uint48(block.timestamp - 30),
            endDate: uint48(block.timestamp + 1000),
            cost: cost,
            location: "XXX",
            burnSet: group
        });
        vm.startPrank(owner);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params, false);

        burnable721.mintBase(anyone1);
        address[] memory recipients = new address[](1);
        recipients[0] = anyone1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10;
        string[] memory uris = new string[](1);
        uris[0] = "";
        burnable1155.mintBaseNew(recipients, amounts, uris);
        vm.stopPrank();

        vm.deal(anyone1, 10 ether);

        vm.startPrank(anyone1);
        burnable721.setApprovalForAll(address(burnRedeem), true);
        burnable1155.setApprovalForAll(address(burnRedeem), true);

        bytes32[] memory merkleProof;
        IBurnRedeemCoreV2.BurnToken[] memory tokens = new IBurnRedeemCoreV2.BurnToken[](1);
        tokens[0] = IBurnRedeemCoreV2.BurnToken({
            groupIndex: 0,
            itemIndex: 0,
            contractAddress: address(burnable721),
            id: 1,
            merkleProof: merkleProof
        });
        uint256 burnFee = burnRedeem.BURN_FEE();

        // Reverts due to invalid value
        vm.expectRevert(IBurnRedeemCoreV2.InvalidPaymentAmount.selector);
        burnRedeem.burnRedeem{value: burnFee}(address(creator), 1, 1, tokens);

        // Passes with proper value
        burnRedeem.burnRedeem{value: burnFee+cost}(address(creator), 1, 1, tokens);

        // Passes with burnCount > 1
        tokens[0].itemIndex = 1;
        tokens[0].contractAddress = address(burnable1155);
        burnRedeem.burnRedeem{value: (burnFee+cost)*5}(address(creator), 1, 5, tokens);
        vm.stopPrank();

        // Check that cost was sent to creator
        assertEq(cost*6, owner.balance);
    }

    function testRedeemWithMembership() public {
        IBurnRedeemCoreV2.BurnItem[] memory items = new IBurnRedeemCoreV2.BurnItem[](1);
        items[0] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.CONTRACT,
            contractAddress: address(burnable721),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC721,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.NONE,
            amount: 0,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        IBurnRedeemCoreV2.BurnGroup[] memory group = new IBurnRedeemCoreV2.BurnGroup[](1);
        group[0] = IBurnRedeemCoreV2.BurnGroup({
            requiredCount: 1,
            items: items
        });
        IBurnRedeemCoreV2.BurnRedeemParameters memory params = IBurnRedeemCoreV2.BurnRedeemParameters({
            paymentReceiver: payable(owner),
            storageProtocol: IBurnRedeemCoreV2.StorageProtocol.NONE,
            redeemAmount: 1,
            totalSupply: 10,
            startDate: uint48(block.timestamp - 30),
            endDate: uint48(block.timestamp + 1000),
            cost: 0,
            location: "XXX",
            burnSet: group
        });
        vm.startPrank(owner);
        manifoldMembership.setMember(anyone1, true);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params, false);
        burnable721.mintBase(anyone1);
        vm.stopPrank();

        vm.startPrank(anyone1);
        burnable721.setApprovalForAll(address(burnRedeem), true);

        bytes32[] memory merkleProof;
        IBurnRedeemCoreV2.BurnToken[] memory tokens = new IBurnRedeemCoreV2.BurnToken[](1);
        tokens[0] = IBurnRedeemCoreV2.BurnToken({
            groupIndex: 0,
            itemIndex: 0,
            contractAddress: address(burnable721),
            id: 1,
            merkleProof: merkleProof
        });

        // Passes without burn fee
        burnRedeem.burnRedeem(address(creator), 1, 1, tokens);
        // Ensure tokens are burned/minted
        assertEq(0, burnable721.balanceOf(anyone1));
        assertEq(1, creator.balanceOf(anyone1));
        vm.stopPrank();
    }

    function testMultipleRedemptions() public {
        IBurnRedeemCoreV2.BurnItem[] memory items = new IBurnRedeemCoreV2.BurnItem[](1);
        items[0] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.CONTRACT,
            contractAddress: address(burnable721),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC721,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.MANIFOLD,
            amount: 0,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        IBurnRedeemCoreV2.BurnGroup[] memory group = new IBurnRedeemCoreV2.BurnGroup[](1);
        group[0] = IBurnRedeemCoreV2.BurnGroup({
            requiredCount: 1,
            items: items
        });
        IBurnRedeemCoreV2.BurnRedeemParameters memory params = IBurnRedeemCoreV2.BurnRedeemParameters({
            paymentReceiver: payable(owner),
            storageProtocol: IBurnRedeemCoreV2.StorageProtocol.NONE,
            redeemAmount: 1,
            totalSupply: 2,
            startDate: uint48(block.timestamp - 30),
            endDate: uint48(block.timestamp + 1000),
            cost: 0,
            location: "XXX",
            burnSet: group
        });
        vm.startPrank(owner);
        // Burn #1
        burnRedeem.initializeBurnRedeem(address(creator), 1, params, false);
        // Burn #2
        items[0].contractAddress = address(burnable1155);
        items[0].tokenSpec = IBurnRedeemCoreV2.TokenSpec.ERC1155;
        items[0].amount = 1;
        burnRedeem.initializeBurnRedeem(address(creator), 2, params, false);

        burnable721.mintBase(anyone1);
        address[] memory recipients = new address[](1);
        recipients[0] = anyone1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 3;
        string[] memory uris = new string[](1);
        uris[0] = "";
        burnable1155.mintBaseNew(recipients, amounts, uris);
        vm.stopPrank();

        vm.deal(anyone1, 1 ether);
        vm.startPrank(anyone1);
        burnable721.setApprovalForAll(address(burnRedeem), true);
        burnable1155.setApprovalForAll(address(burnRedeem), true);

        address[] memory addresses = new address[](2);
        addresses[0] = address(creator);
        addresses[1] = address(creator);

        uint256[] memory indexes = new uint256[](2);
        indexes[0] = 1;
        indexes[1] = 2;

        uint32[] memory burnCounts = new uint32[](2);
        burnCounts[0] = 1;
        burnCounts[1] = 3;

        bytes32[] memory merkleProof;
        IBurnRedeemCoreV2.BurnToken[][] memory allTokens = new IBurnRedeemCoreV2.BurnToken[][](2);
        IBurnRedeemCoreV2.BurnToken[] memory tokens1 = new IBurnRedeemCoreV2.BurnToken[](1);
        IBurnRedeemCoreV2.BurnToken[] memory tokens2 = new IBurnRedeemCoreV2.BurnToken[](1);

        tokens1[0] = IBurnRedeemCoreV2.BurnToken({
            groupIndex: 0,
            itemIndex: 0,
            contractAddress: address(burnable721),
            id: 1,
            merkleProof: merkleProof
        });
        tokens2[0] = IBurnRedeemCoreV2.BurnToken({
            groupIndex: 0,
            itemIndex: 0,
            contractAddress: address(burnable1155),
            id: 1,
            merkleProof: merkleProof
        });
        allTokens[0] = tokens1;
        allTokens[1] = tokens2;
        uint256 burnFee = burnRedeem.BURN_FEE();

        vm.expectRevert(IBurnRedeemCoreV2.InvalidPaymentAmount.selector);
        burnRedeem.burnRedeem{value: burnFee}(addresses, indexes, burnCounts, allTokens);

        // Reverts with mismatching lengths
        address[] memory singleAddresses = new address[](1);
        addresses[0] = address(creator);
        vm.expectRevert(IBurnRedeemCoreV2.InvalidInput.selector);
        burnRedeem.burnRedeem{value: burnFee*2}(singleAddresses, indexes, burnCounts, allTokens);

        uint256[] memory singleIndexes = new uint256[](1);
        indexes[0] = 1;
        vm.expectRevert(IBurnRedeemCoreV2.InvalidInput.selector);
        burnRedeem.burnRedeem{value: burnFee*2}(addresses, singleIndexes, burnCounts, allTokens);

        uint32[] memory singleBurnCounts = new uint32[](1);
        burnCounts[0] = 1;
        vm.expectRevert(IBurnRedeemCoreV2.InvalidInput.selector);
        burnRedeem.burnRedeem{value: burnFee*2}(addresses, indexes, singleBurnCounts, allTokens);

        IBurnRedeemCoreV2.BurnToken[][] memory singleTokens = new IBurnRedeemCoreV2.BurnToken[][](1);
        singleTokens[0] = tokens1;
        vm.expectRevert(IBurnRedeemCoreV2.InvalidInput.selector);
        burnRedeem.burnRedeem{value: burnFee*2}(addresses, indexes, burnCounts, singleTokens);

        // Reverts with burnCount > 1 for 721
        burnCounts[0] = 2;
        vm.expectRevert(IBurnRedeemCoreV2.InvalidBurnAmount.selector);
        burnRedeem.burnRedeem{value: burnFee*2}(addresses, indexes, burnCounts, allTokens);

        // Passes with multiple redemptions, burnCount > 1 for 1155
        burnCounts[0] = 1;
        burnRedeem.burnRedeem{value: burnFee*4}(addresses, indexes, burnCounts, allTokens);

        // However, only 2 redeemed for 1155 because total supply is 2
        // Excess fee refunded
        assertEq(1 ether - burnFee*3, anyone1.balance);

        // Check balances
        assertEq(0, burnable721.balanceOf(anyone1));
        assertEq(1, burnable1155.balanceOf(anyone1, 1));
        assertEq(3, creator.balanceOf(anyone1));
    }

    function testOnERC721Received() public {
        IBurnRedeemCoreV2.BurnItem[] memory items = new IBurnRedeemCoreV2.BurnItem[](1);
        items[0] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.CONTRACT,
            contractAddress: address(burnable721),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC721,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.MANIFOLD,
            amount: 0,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        IBurnRedeemCoreV2.BurnGroup[] memory group = new IBurnRedeemCoreV2.BurnGroup[](1);
        group[0] = IBurnRedeemCoreV2.BurnGroup({
            requiredCount: 1,
            items: items
        });
        IBurnRedeemCoreV2.BurnRedeemParameters memory params = IBurnRedeemCoreV2.BurnRedeemParameters({
            paymentReceiver: payable(owner),
            storageProtocol: IBurnRedeemCoreV2.StorageProtocol.NONE,
            redeemAmount: 1,
            totalSupply: 2,
            startDate: uint48(block.timestamp - 30),
            endDate: uint48(block.timestamp + 1000),
            cost: 0,
            location: "XXX",
            burnSet: group
        });
        vm.startPrank(owner);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params, false);

        burnable721.mintBase(anyone1);
        burnable721_2.mintBase(anyone1);
        vm.stopPrank();

        // Reverts without membership
        bytes32[] memory merkleProof;
        bytes memory data = abi.encode(address(creator), uint256(1), uint256(0), merkleProof);
        vm.prank(anyone1);
        vm.expectRevert(IBurnRedeemCoreV2.InvalidInput.selector);
        burnable721.safeTransferFrom(anyone1, address(burnRedeem), 1, data);

        vm.prank(owner);
        manifoldMembership.setMember(anyone1, true);

        // Reverts due to the wrong contract
        vm.prank(anyone1);
        vm.expectRevert(BurnRedeemLibV2.InvalidBurnToken.selector);
        burnable721_2.safeTransferFrom(anyone1, address(burnRedeem), 1, data);

        // Passes with right token id
        vm.prank(anyone1);
        burnable721.safeTransferFrom(anyone1, address(burnRedeem), 1, data);

        // Ensure tokens are burned/minted
        assertEq(0, burnable721.balanceOf(anyone1));
        assertEq(1, creator.balanceOf(anyone1));
        vm.stopPrank();
    }

    function testOnERC1155Received() public {
        IBurnRedeemCoreV2.BurnItem[] memory items = new IBurnRedeemCoreV2.BurnItem[](1);
        items[0] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.CONTRACT,
            contractAddress: address(burnable1155),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC1155,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.MANIFOLD,
            amount: 2,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        IBurnRedeemCoreV2.BurnGroup[] memory group = new IBurnRedeemCoreV2.BurnGroup[](1);
        group[0] = IBurnRedeemCoreV2.BurnGroup({
            requiredCount: 1,
            items: items
        });
        IBurnRedeemCoreV2.BurnRedeemParameters memory params = IBurnRedeemCoreV2.BurnRedeemParameters({
            paymentReceiver: payable(owner),
            storageProtocol: IBurnRedeemCoreV2.StorageProtocol.NONE,
            redeemAmount: 1,
            totalSupply: 10,
            startDate: uint48(block.timestamp - 30),
            endDate: uint48(block.timestamp + 1000),
            cost: 0,
            location: "XXX",
            burnSet: group
        });
        vm.startPrank(owner);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params, false);
        address[] memory recipients = new address[](1);
        recipients[0] = anyone1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 3;
        string[] memory uris = new string[](1);
        uris[0] = "";
        burnable1155.mintBaseNew(recipients, amounts, uris);
        burnable1155_2.mintBaseNew(recipients, amounts, uris);
        vm.stopPrank();

        // Reverts without membership
        bytes32[] memory merkleProof;
        bytes memory data = abi.encode(address(creator), uint256(1), uint32(1), uint256(0), merkleProof);
        vm.prank(anyone1);
        vm.expectRevert("ERC1155: transfer to non-ERC1155Receiver implementer");
        burnable1155.safeTransferFrom(anyone1, address(burnRedeem), 1, 2, data);

        vm.prank(owner);
        manifoldMembership.setMember(anyone1, true);

        // Reverts due to the wrong contract
        vm.prank(anyone1);
        vm.expectRevert("ERC1155: transfer to non-ERC1155Receiver implementer");
        burnable1155_2.safeTransferFrom(anyone1, address(burnRedeem), 1, 2, data);

        // Reverts with invalid amount
        vm.prank(anyone1);
        vm.expectRevert("ERC1155: transfer to non-ERC1155Receiver implementer");
        burnable1155.safeTransferFrom(anyone1, address(burnRedeem), 1, 3, data);

        // Passes with right token id
        vm.prank(anyone1);
        burnable1155.safeTransferFrom(anyone1, address(burnRedeem), 1, 2, data);

        // Ensure tokens are burned/minted
        assertEq(1, burnable1155.balanceOf(anyone1, 1));
        assertEq(1, creator.balanceOf(anyone1));
        vm.stopPrank();
    }

    function testOnERC1155ReceivedMultiple() public {
        IBurnRedeemCoreV2.BurnItem[] memory items = new IBurnRedeemCoreV2.BurnItem[](1);
        items[0] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.CONTRACT,
            contractAddress: address(burnable1155),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC1155,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.MANIFOLD,
            amount: 2,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        IBurnRedeemCoreV2.BurnGroup[] memory group = new IBurnRedeemCoreV2.BurnGroup[](1);
        group[0] = IBurnRedeemCoreV2.BurnGroup({
            requiredCount: 1,
            items: items
        });
        IBurnRedeemCoreV2.BurnRedeemParameters memory params = IBurnRedeemCoreV2.BurnRedeemParameters({
            paymentReceiver: payable(owner),
            storageProtocol: IBurnRedeemCoreV2.StorageProtocol.NONE,
            redeemAmount: 1,
            totalSupply: 3,
            startDate: uint48(block.timestamp - 30),
            endDate: uint48(block.timestamp + 1000),
            cost: 0,
            location: "XXX",
            burnSet: group
        });
        vm.startPrank(owner);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params, false);
        address[] memory recipients = new address[](1);
        recipients[0] = anyone1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10;
        string[] memory uris = new string[](1);
        uris[0] = "";
        burnable1155.mintBaseNew(recipients, amounts, uris);
        burnable1155_2.mintBaseNew(recipients, amounts, uris);
        vm.stopPrank();

        vm.prank(owner);
        manifoldMembership.setMember(anyone1, true);

        bytes32[] memory merkleProof;
        bytes memory data = abi.encode(address(creator), uint256(1), uint32(2), uint256(0), merkleProof);
        vm.prank(anyone1);
        burnable1155.safeTransferFrom(anyone1, address(burnRedeem), 1, 4, data);

        // Ensure tokens are burned/minted
        assertEq(6, burnable1155.balanceOf(anyone1, 1));
        assertEq(2  , creator.balanceOf(anyone1));
        vm.stopPrank();
    }

    function testOnERC1155BatchReceived() public {
        IBurnRedeemCoreV2.BurnItem[] memory items = new IBurnRedeemCoreV2.BurnItem[](2);
        items[0] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.RANGE,
            contractAddress: address(burnable1155),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC1155,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.MANIFOLD,
            amount: 2,
            minTokenId: 1,
            maxTokenId: 1,
            merkleRoot: bytes32(0)
        });
        items[1] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.RANGE,
            contractAddress: address(burnable1155),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC1155,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.MANIFOLD,
            amount: 2,
            minTokenId: 2,
            maxTokenId: 2,
            merkleRoot: bytes32(0)
        });
        IBurnRedeemCoreV2.BurnGroup[] memory group = new IBurnRedeemCoreV2.BurnGroup[](1);
        group[0] = IBurnRedeemCoreV2.BurnGroup({
            requiredCount: 2,
            items: items
        });
        IBurnRedeemCoreV2.BurnRedeemParameters memory params = IBurnRedeemCoreV2.BurnRedeemParameters({
            paymentReceiver: payable(owner),
            storageProtocol: IBurnRedeemCoreV2.StorageProtocol.NONE,
            redeemAmount: 1,
            totalSupply: 10,
            startDate: uint48(block.timestamp - 30),
            endDate: uint48(block.timestamp + 1000),
            cost: 0,
            location: "XXX",
            burnSet: group
        });
        vm.startPrank(owner);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params, false);
        address[] memory recipients = new address[](1);
        recipients[0] = anyone1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10;
        string[] memory uris = new string[](1);
        uris[0] = "";
        burnable1155.mintBaseNew(recipients, amounts, uris);
        burnable1155.mintBaseNew(recipients, amounts, uris);
        burnable1155.mintBaseNew(recipients, amounts, uris);
        burnable1155_2.mintBaseNew(recipients, amounts, uris);
        burnable1155_2.mintBaseNew(recipients, amounts, uris);
        burnable1155_2.mintBaseNew(recipients, amounts, uris);
        vm.stopPrank();

        bytes32[] memory merkleProof;
        IBurnRedeemCoreV2.BurnToken[] memory tokens = new IBurnRedeemCoreV2.BurnToken[](2);
        tokens[0] = IBurnRedeemCoreV2.BurnToken({
            groupIndex: 0,
            itemIndex: 0,
            contractAddress: address(burnable1155),
            id: 1,
            merkleProof: merkleProof
        });
        tokens[1] = IBurnRedeemCoreV2.BurnToken({
            groupIndex: 0,
            itemIndex: 1,
            contractAddress: address(burnable1155),
            id: 2,
            merkleProof: merkleProof
        });
        bytes memory data = abi.encode(address(creator), uint256(1), uint32(1), tokens);
        // Reverts without membership
        vm.prank(anyone1);
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        uint256[] memory values = new uint256[](2);
        values[0] = 2;
        values[1] = 2;
        vm.expectRevert("ERC1155: transfer to non-ERC1155Receiver implementer");
        burnable1155.safeBatchTransferFrom(anyone1, address(burnRedeem), tokenIds, values, data);

        vm.prank(owner);
        manifoldMembership.setMember(anyone1, true);

        // Reverts due to the wrong contract
        vm.prank(anyone1);
        vm.expectRevert(abi.encodePacked("ERC1155: transfer to non-ERC1155Receiver implementer"));
        burnable1155_2.safeBatchTransferFrom(anyone1, address(burnRedeem), tokenIds, values, data);

        // Reverts with mismatching token ids amount
        vm.prank(anyone1);
        tokenIds[1] = 3;
        vm.expectRevert("ERC1155: transfer to non-ERC1155Receiver implementer");
        burnable1155.safeBatchTransferFrom(anyone1, address(burnRedeem), tokenIds, values, data);

        // Reverts with mismatching values amount
        vm.prank(anyone1);
        tokenIds[1] = 2;
        values[0] = 1;
        values[1] = 1;
        vm.expectRevert("ERC1155: transfer to non-ERC1155Receiver implementer");
        burnable1155.safeBatchTransferFrom(anyone1, address(burnRedeem), tokenIds, values, data);

        // Reverts with extra tokens
        vm.prank(anyone1);
        uint256[] memory extraTokenIds = new uint256[](3);
        extraTokenIds[0] = 1;
        extraTokenIds[1] = 2;
        extraTokenIds[2] = 3;
        uint256[] memory extraValues = new uint256[](3);
        values[0] = 2;
        values[1] = 2;
        vm.expectRevert("ERC1155: transfer to non-ERC1155Receiver implementer");
        burnable1155.safeBatchTransferFrom(anyone1, address(burnRedeem), extraTokenIds, extraValues, data);

        // Passes with right token id
        values[0] = 2;
        values[1] = 2;
        vm.prank(anyone1);
        burnable1155.safeBatchTransferFrom(anyone1, address(burnRedeem), tokenIds, values, data);

        // burnCount > 1
        vm.prank(anyone1);
        data = abi.encode(address(creator), uint256(1), uint32(4), tokens);
        // Reverts with insufficient values
        vm.expectRevert("ERC1155: transfer to non-ERC1155Receiver implementer");
        burnable1155.safeBatchTransferFrom(anyone1, address(burnRedeem), tokenIds, values, data);

        // Passes with right values
        vm.prank(anyone1);
        values[0] = 8;
        values[1] = 8;
        burnable1155.safeBatchTransferFrom(anyone1, address(burnRedeem), tokenIds, values, data);

        // Ensure tokens are burned/minted
        assertEq(0, burnable1155.balanceOf(anyone1, 1));
        assertEq(0, burnable1155.balanceOf(anyone1, 2));
        assertEq(5, creator.balanceOf(anyone1));
        vm.stopPrank();
    }


    function testOnERC1155BatchReceivedDirectCall() public {
        IBurnRedeemCoreV2.BurnItem[] memory items = new IBurnRedeemCoreV2.BurnItem[](1);
        items[0] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.RANGE,
            contractAddress: address(burnable721),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC721,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.MANIFOLD,
            amount: 0,
            minTokenId: 1,
            maxTokenId: 1,
            merkleRoot: bytes32(0)
        });
        IBurnRedeemCoreV2.BurnGroup[] memory group = new IBurnRedeemCoreV2.BurnGroup[](1);
        group[0] = IBurnRedeemCoreV2.BurnGroup({
            requiredCount: 1,
            items: items
        });
        IBurnRedeemCoreV2.BurnRedeemParameters memory params = IBurnRedeemCoreV2.BurnRedeemParameters({
            paymentReceiver: payable(owner),
            storageProtocol: IBurnRedeemCoreV2.StorageProtocol.NONE,
            redeemAmount: 1,
            totalSupply: 10,
            startDate: uint48(block.timestamp - 30),
            endDate: uint48(block.timestamp + 1000),
            cost: 0,
            location: "XXX",
            burnSet: group
        });
        vm.startPrank(owner);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params, false);
        burnable721.mintBase(anyone1);
        vm.stopPrank();

        bytes32[] memory merkleProof;
        IBurnRedeemCoreV2.BurnToken[] memory tokens = new IBurnRedeemCoreV2.BurnToken[](1);
        tokens[0] = IBurnRedeemCoreV2.BurnToken({
            groupIndex: 0,
            itemIndex: 0,
            contractAddress: address(burnable721),
            id: 1,
            merkleProof: merkleProof
        });
        bytes memory data = abi.encode(address(creator), uint256(1), uint32(1), tokens);

        vm.prank(anyone1);
        burnable721.setApprovalForAll(address(burnRedeem), true);

        vm.prank(owner);
        manifoldMembership.setMember(anyone1, true);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        vm.prank(anyone2);
        vm.expectRevert(abi.encodePacked(IBurnRedeemCoreV2.InvalidToken.selector, uint256(1)));
        burnRedeem.onERC1155BatchReceived(anyone2, anyone1, tokenIds, values, data);
    }

    function testReceiverInvalidInput() public {
        uint160 cost = 1000000000000000000;
        IBurnRedeemCoreV2.BurnItem[] memory items = new IBurnRedeemCoreV2.BurnItem[](1);
        items[0] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.CONTRACT,
            contractAddress: address(burnable721),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC721,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.MANIFOLD,
            amount: 0,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        IBurnRedeemCoreV2.BurnGroup[] memory group = new IBurnRedeemCoreV2.BurnGroup[](1);
        group[0] = IBurnRedeemCoreV2.BurnGroup({
            requiredCount: 1,
            items: items
        });
        IBurnRedeemCoreV2.BurnRedeemParameters memory params = IBurnRedeemCoreV2.BurnRedeemParameters({
            paymentReceiver: payable(owner),
            storageProtocol: IBurnRedeemCoreV2.StorageProtocol.NONE,
            redeemAmount: 1,
            totalSupply: 2,
            startDate: uint48(block.timestamp - 30),
            endDate: uint48(block.timestamp + 1000),
            cost: cost,
            location: "XXX",
            burnSet: group
        });
        vm.startPrank(owner);
        // Burn #1 - burn with cost
        burnRedeem.initializeBurnRedeem(address(creator), 1, params, false);
        // Burn #2 - zero cost multi set requirement
        group = new IBurnRedeemCoreV2.BurnGroup[](2);
        group[0] = IBurnRedeemCoreV2.BurnGroup({
            requiredCount: 1,
            items: items
        });
        group[1] = IBurnRedeemCoreV2.BurnGroup({
            requiredCount: 1,
            items: items
        });
        params.cost = 0;
        params.burnSet = group;
        burnRedeem.initializeBurnRedeem(address(creator), 2, params, false);
        // Burn #3 - zero cost multi item set
        items = new IBurnRedeemCoreV2.BurnItem[](2);
        items[0] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.RANGE,
            contractAddress: address(burnable1155),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC1155,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.MANIFOLD,
            amount: 1,
            minTokenId: 1,
            maxTokenId: 1,
            merkleRoot: bytes32(0)
        });
        items[1] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.RANGE,
            contractAddress: address(burnable1155),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC1155,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.MANIFOLD,
            amount: 1,
            minTokenId: 2,
            maxTokenId: 2,
            merkleRoot: bytes32(0)
        });
        group = new IBurnRedeemCoreV2.BurnGroup[](1);
        group[0].items = items;
        group[0].requiredCount = 2;
        params.cost = 0;
        params.burnSet = group;
        burnRedeem.initializeBurnRedeem(address(creator), 3, params, false);


        burnable721.mintBase(anyone1);
        address[] memory recipients = new address[](1);
        recipients[0] = anyone1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1;
        string[] memory uris = new string[](1);
        uris[0] = "";
        burnable1155.mintBaseNew(recipients, amounts, uris);
        burnable1155.mintBaseNew(recipients, amounts, uris);
        manifoldMembership.setMember(anyone1, true);
        vm.stopPrank();

        vm.deal(anyone1, 1 ether);
        vm.startPrank(anyone1);

        // Receivers revert on burns with cost
        // onERC721Received
        bytes32[] memory merkleProof;
        bytes memory data = abi.encode(address(creator), uint256(1), uint256(0), merkleProof);
        vm.expectRevert(IBurnRedeemCoreV2.InvalidInput.selector);
        burnable721.safeTransferFrom(anyone1, address(burnRedeem), 1, data);

        // onERC1155Received
        data = abi.encode(address(creator), uint256(1), uint32(1), uint256(0), merkleProof);
        vm.expectRevert("ERC1155: transfer to non-ERC1155Receiver implementer");
        burnable1155.safeTransferFrom(anyone1, address(burnRedeem), 1, 1, data);

        // onERC1155BatchReceived
        IBurnRedeemCoreV2.BurnToken[] memory tokens = new IBurnRedeemCoreV2.BurnToken[](1);
        tokens[0] = IBurnRedeemCoreV2.BurnToken({
            groupIndex: 0,
            itemIndex: 0,
            contractAddress: address(burnable1155),
            id: 1,
            merkleProof: merkleProof
        });
        data = abi.encode(address(creator), uint256(1), uint32(1), tokens);
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        uint256[] memory values = new uint256[](1);
        values[0] = 1;
        vm.expectRevert("ERC1155: transfer to non-ERC1155Receiver implementer");
        burnable1155.safeBatchTransferFrom(anyone1, address(burnRedeem), tokenIds, values, data);

        // Single receivers revert when burnSets.length > 1 (burn #2)
        data = abi.encode(address(creator), uint256(2), uint256(0), merkleProof);
        vm.expectRevert(IBurnRedeemCoreV2.InvalidInput.selector);
        burnable721.safeTransferFrom(anyone1, address(burnRedeem), 1, data);
        data = abi.encode(address(creator), uint256(2), uint32(1), uint256(0), merkleProof);
        vm.expectRevert("ERC1155: transfer to non-ERC1155Receiver implementer");
        burnable1155.safeTransferFrom(anyone1, address(burnRedeem), 1, 1, data);

        // Single receivers revert when requiredCount > 1 (burn #3)
        data = abi.encode(address(creator), uint256(3), uint256(0), merkleProof);
        vm.expectRevert(IBurnRedeemCoreV2.InvalidInput.selector);
        burnable721.safeTransferFrom(anyone1, address(burnRedeem), 1, data);
        data = abi.encode(address(creator), uint256(3), uint32(1), uint256(0), merkleProof);
        vm.expectRevert("ERC1155: transfer to non-ERC1155Receiver implementer");
        burnable1155.safeTransferFrom(anyone1, address(burnRedeem), 1, 1, data);
    }

    function testMisconfigurationOnERC721Received() public {
        IBurnRedeemCoreV2.BurnItem[] memory items = new IBurnRedeemCoreV2.BurnItem[](1);
        items[0] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.CONTRACT,
            contractAddress: address(burnable721),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC1155,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.MANIFOLD,
            amount: 1,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        IBurnRedeemCoreV2.BurnGroup[] memory group = new IBurnRedeemCoreV2.BurnGroup[](1);
        group[0] = IBurnRedeemCoreV2.BurnGroup({
            requiredCount: 1,
            items: items
        });
        IBurnRedeemCoreV2.BurnRedeemParameters memory params = IBurnRedeemCoreV2.BurnRedeemParameters({
            paymentReceiver: payable(owner),
            storageProtocol: IBurnRedeemCoreV2.StorageProtocol.NONE,
            redeemAmount: 1,
            totalSupply: 10,
            startDate: uint48(block.timestamp - 30),
            endDate: uint48(block.timestamp + 1000),
            cost: 0,
            location: "XXX",
            burnSet: group
        });
        vm.startPrank(owner);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params, false);
        manifoldMembership.setMember(anyone1, true);
        burnable721.mintBase(anyone1);
        vm.stopPrank();
        bytes32[] memory merkleProof;
        bytes memory data = abi.encode(address(creator), uint256(1), uint256(0), merkleProof);

        vm.prank(anyone1);
        vm.expectRevert(IBurnRedeemCoreV2.InvalidInput.selector);
        burnable721.safeTransferFrom(anyone1, address(burnRedeem), 1, data);
    }

    function testMisconfigurationOnERC1155Received() public {
        IBurnRedeemCoreV2.BurnItem[] memory items = new IBurnRedeemCoreV2.BurnItem[](1);
        items[0] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.CONTRACT,
            contractAddress: address(burnable1155),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC721,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.MANIFOLD,
            amount: 0,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        IBurnRedeemCoreV2.BurnGroup[] memory group = new IBurnRedeemCoreV2.BurnGroup[](1);
        group[0] = IBurnRedeemCoreV2.BurnGroup({
            requiredCount: 1,
            items: items
        });
        IBurnRedeemCoreV2.BurnRedeemParameters memory params = IBurnRedeemCoreV2.BurnRedeemParameters({
            paymentReceiver: payable(owner),
            storageProtocol: IBurnRedeemCoreV2.StorageProtocol.NONE,
            redeemAmount: 1,
            totalSupply: 10,
            startDate: uint48(block.timestamp - 30),
            endDate: uint48(block.timestamp + 1000),
            cost: 0,
            location: "XXX",
            burnSet: group
        });
        vm.startPrank(owner);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params, false);
        manifoldMembership.setMember(anyone1, true);
        address[] memory recipients = new address[](1);
        recipients[0] = anyone1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1;
        string[] memory uris = new string[](1);
        uris[0] = "";
        burnable1155.mintBaseNew(recipients, amounts, uris);
        vm.stopPrank();
        bytes32[] memory merkleProof;
        bytes memory data = abi.encode(address(creator), uint256(1), uint256(0), merkleProof);

        vm.prank(anyone1);
        data = abi.encode(address(creator), uint256(1), uint32(1), uint256(0), merkleProof);
        vm.expectRevert("ERC1155: transfer to non-ERC1155Receiver implementer");
        burnable1155.safeTransferFrom(anyone1, address(burnRedeem), 1, 1, data);
    }

    function testWithdraw() public {
        IBurnRedeemCoreV2.BurnItem[] memory items = new IBurnRedeemCoreV2.BurnItem[](1);
        items[0] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.CONTRACT,
            contractAddress: address(burnable721),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC721,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.MANIFOLD,
            amount: 0,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        IBurnRedeemCoreV2.BurnGroup[] memory group = new IBurnRedeemCoreV2.BurnGroup[](1);
        group[0] = IBurnRedeemCoreV2.BurnGroup({
            requiredCount: 1,
            items: items
        });
        IBurnRedeemCoreV2.BurnRedeemParameters memory params = IBurnRedeemCoreV2.BurnRedeemParameters({
            paymentReceiver: payable(owner),
            storageProtocol: IBurnRedeemCoreV2.StorageProtocol.NONE,
            redeemAmount: 1,
            totalSupply: 10,
            startDate: uint48(block.timestamp - 30),
            endDate: uint48(block.timestamp + 1000),
            cost: 0,
            location: "XXX",
            burnSet: group
        });
        vm.startPrank(owner);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params, false);
        for (uint256 i = 0; i < 10; i++) {
            burnable721.mintBase(anyone1);
        }
        vm.stopPrank();

        vm.deal(anyone1, 1 ether);
        vm.startPrank(anyone1);
        burnable721.setApprovalForAll(address(burnRedeem), true);
        address[] memory addresses = new address[](10);
        uint256[] memory indexes = new uint256[](10);
        uint32[] memory burnCounts = new uint32[](10);
        bytes32[] memory merkleProof;
        IBurnRedeemCoreV2.BurnToken[][] memory allTokens = new IBurnRedeemCoreV2.BurnToken[][](10);
        for (uint256 i = 0; i < 10; i++) {
            addresses[i] = address(creator);
            indexes[i] = 1;
            burnCounts[i] = 1;
            IBurnRedeemCoreV2.BurnToken[] memory tokens = new IBurnRedeemCoreV2.BurnToken[](1);
            IBurnRedeemCoreV2.BurnToken memory token = IBurnRedeemCoreV2.BurnToken({
                groupIndex: 0,
                itemIndex: 0,
                contractAddress: address(burnable721),
                id: i+1,
                merkleProof: merkleProof
            });
            tokens[0] = token;
            allTokens[i] = tokens;
        }
        uint256 burnFee = burnRedeem.BURN_FEE();
        burnRedeem.burnRedeem{value: burnFee*10}(addresses, indexes, burnCounts, allTokens);
        vm.stopPrank();

        vm.prank(anyone2);
        vm.expectRevert("AdminControl: Must be owner or admin");
        burnRedeem.withdraw(payable(anyone2), burnFee*10);

        vm.prank(burnRedeemOwner);
        vm.expectRevert();
        burnRedeem.withdraw(payable(owner), burnFee*11);

        vm.prank(burnRedeemOwner);
        burnRedeem.withdraw(payable(owner), burnFee*10);
        assertEq(burnFee*10, owner.balance);
    }

    function testAirdrop() public {
        IBurnRedeemCoreV2.BurnItem[] memory items = new IBurnRedeemCoreV2.BurnItem[](1);
        items[0] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.CONTRACT,
            contractAddress: address(burnable721),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC721,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.MANIFOLD,
            amount: 0,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        IBurnRedeemCoreV2.BurnGroup[] memory group = new IBurnRedeemCoreV2.BurnGroup[](1);
        group[0] = IBurnRedeemCoreV2.BurnGroup({
            requiredCount: 1,
            items: items
        });
        IBurnRedeemCoreV2.BurnRedeemParameters memory params = IBurnRedeemCoreV2.BurnRedeemParameters({
            paymentReceiver: payable(owner),
            storageProtocol: IBurnRedeemCoreV2.StorageProtocol.NONE,
            redeemAmount: 2,
            totalSupply: 10,
            startDate: uint48(block.timestamp - 30),
            endDate: uint48(block.timestamp + 1000),
            cost: 0,
            location: "XXX",
            burnSet: group
        });
        vm.startPrank(owner);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params, false);
        vm.stopPrank();

        address[] memory recipients = new address[](2);
        recipients[0] = anyone1;
        recipients[1] = anyone2;
        uint32[] memory amounts = new uint32[](2);
        amounts[0] = 1;
        amounts[1] = 1;

        vm.prank(anyone1);
        vm.expectRevert(abi.encodePacked(IBurnRedeemCoreV2.NotAdmin.selector, uint256(uint160(address(creator)))));
        burnRedeem.airdrop(address(creator), 1, recipients, amounts);

        vm.prank(owner);
        burnRedeem.airdrop(address(creator), 1, recipients, amounts);

        // Check the token uri
        assertEq(creator.tokenURI(1), "XXX/1");
        assertEq(creator.tokenURI(2), "XXX/2");

        // Check balances
        assertEq(2, creator.balanceOf(anyone1));
        assertEq(2, creator.balanceOf(anyone2));

        // redeemedCount updated
        IBurnRedeemCoreV2.BurnRedeem memory burnInstance = burnRedeem.getBurnRedeem(address(creator), 1);
        assertEq(burnInstance.redeemedCount, 4);
        assertEq(burnInstance.totalSupply, 10);

        // Second airdrop
        amounts[0] = 9;
        amounts[1] = 9;
        vm.prank(owner);
        burnRedeem.airdrop(address(creator), 1, recipients, amounts);

        // check amounts
        burnInstance = burnRedeem.getBurnRedeem(address(creator), 1);
        assertEq(burnInstance.redeemedCount, 40);
        assertEq(burnInstance.totalSupply, 40);

        // Check balances
        assertEq(20, creator.balanceOf(anyone1));
        assertEq(20, creator.balanceOf(anyone2));

        // Reverts when redeemedCount would exceed max uint32
        recipients = new address[](1);
        recipients[0] = anyone1;
        amounts = new uint32[](1);
        amounts[0] = 2147483647;
        vm.prank(owner);
        vm.expectRevert(IBurnRedeemCoreV2.InvalidRedeemAmount.selector);
        burnRedeem.airdrop(address(creator), 1, recipients, amounts);
    }


    function testSetBurnFees() public {
        uint256 newBurnFee = defaultBurnFee + 1000000;
        uint256 newMultiBurnFee = defaultMultiBurnFee + 1000000;

         // Owner can set fees
        vm.prank(burnRedeemOwner);
        burnRedeem.setBurnFees(newBurnFee, newMultiBurnFee);

        // Verify fees were set correctly
        assertEq(burnRedeem.BURN_FEE(), newBurnFee);
        assertEq(burnRedeem.MULTI_BURN_FEE(), newMultiBurnFee);

        // test burns with new fees
        IBurnRedeemCoreV2.BurnItem[] memory items = new IBurnRedeemCoreV2.BurnItem[](6);
         // tokenSpec: ERC-721, burnSpec: NONE
        items[0] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.ANY,
            contractAddress: address(0),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC721,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.NONE,
            amount: 0,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        // tokenSpec: ERC-721, burnSpec: MANIFOLD
        items[1] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.ANY,
            contractAddress: address(0),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC721,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.MANIFOLD,
            amount: 0,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        // tokenSpec: ERC-721, burnSpec: OPENZEPPELIN
        items[2] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.ANY,
            contractAddress: address(0),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC721,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.OPENZEPPELIN,
            amount: 0,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        // tokenSpec: ERC-1155, burnSpec: NONE
        items[3] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.ANY,
            contractAddress: address(0),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC1155,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.NONE,
            amount: 1,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        // tokenSpec: ERC-1155, burnSpec: MANIFOLD
        items[4] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.ANY,
            contractAddress: address(0),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC1155,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.MANIFOLD,
            amount: 1,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        // tokenSpec: ERC-1155, burnSpec: OPENZEPPELIN
        items[5] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.ANY,
            contractAddress: address(0),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC1155,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.OPENZEPPELIN,
            amount: 1,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        IBurnRedeemCoreV2.BurnGroup[] memory group = new IBurnRedeemCoreV2.BurnGroup[](1);
        group[0] = IBurnRedeemCoreV2.BurnGroup({
            requiredCount: 1,
            items: items
        });
        IBurnRedeemCoreV2.BurnRedeemParameters memory params = IBurnRedeemCoreV2.BurnRedeemParameters({
            paymentReceiver: payable(owner),
            storageProtocol: IBurnRedeemCoreV2.StorageProtocol.NONE,
            redeemAmount: 1,
            totalSupply: 10,
            startDate: uint48(block.timestamp - 30),
            endDate: uint48(block.timestamp + 1000),
            cost: 0,
            location: "XXX",
            burnSet: group
        });
        vm.startPrank(owner);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params, true);

        // Mint tokens to anyone1
        oz721.mint(anyone1, 1);
        burnable721.mintBase(anyone1);
        oz721Burnable.mint(anyone1, 1);
        oz1155.mint(anyone1, 1, 1);
        address[] memory recipients = new address[](1);
        recipients[0] = anyone1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1;
        string[] memory uris = new string[](1);
        uris[0] = "";
        burnable1155.mintBaseNew(recipients, amounts, uris);
        oz1155Burnable.mint(anyone1, 1, 1);

        vm.stopPrank();

        vm.deal(anyone1, 1 ether);
        bytes32[] memory merkleProof;
        IBurnRedeemCoreV2.BurnToken[] memory tokens = new IBurnRedeemCoreV2.BurnToken[](1);
        tokens[0] = IBurnRedeemCoreV2.BurnToken({
            groupIndex: 0,
            itemIndex: 0,
            contractAddress: address(0),
            id: 1,
            merkleProof: merkleProof
        });
        uint256 burnFee = newBurnFee;

        vm.startPrank(anyone1);
        oz721.setApprovalForAll(address(burnRedeem), true);
        tokens[0].contractAddress = address(oz721);
        tokens[0].itemIndex = 0;
        vm.expectRevert();
        burnRedeem.burnRedeem{value: defaultBurnFee}(address(creator), 1, 1, tokens);
        burnRedeem.burnRedeem{value: burnFee}(address(creator), 1, 1, tokens);
        assertEq(0, oz721.balanceOf(anyone1));
        assertEq(1, oz721.balanceOf(address(0x000000000000000000000000000000000000dEaD)));

        burnable721.setApprovalForAll(address(burnRedeem), true);
        tokens[0].contractAddress = address(burnable721);
        tokens[0].itemIndex = 1;
        burnRedeem.burnRedeem{value: burnFee}(address(creator), 1, 1, tokens);
        vm.expectRevert("ERC721: invalid token ID");
        burnable721.ownerOf(1);

        oz721Burnable.setApprovalForAll(address(burnRedeem), true);
        tokens[0].contractAddress = address(oz721Burnable);
        tokens[0].itemIndex = 2;
        burnRedeem.burnRedeem{value: burnFee}(address(creator), 1, 1, tokens);
        vm.expectRevert("ERC721: invalid token ID");
        oz721Burnable.ownerOf(1);

        oz1155.setApprovalForAll(address(burnRedeem), true);
        tokens[0].contractAddress = address(oz1155);
        tokens[0].itemIndex = 3;
        burnRedeem.burnRedeem{value: burnFee}(address(creator), 1, 1, tokens);
        assertEq(0, oz1155.balanceOf(anyone1, 1));
        assertEq(1, oz1155.balanceOf(address(0x000000000000000000000000000000000000dEaD), 1));

        burnable1155.setApprovalForAll(address(burnRedeem), true);
        tokens[0].contractAddress = address(burnable1155);
        tokens[0].itemIndex = 4;
        burnRedeem.burnRedeem{value: burnFee}(address(creator), 1, 1, tokens);
        assertEq(0, burnable1155.balanceOf(anyone1, 1));
        assertEq(0, burnable1155.totalSupply(1));

        oz1155Burnable.setApprovalForAll(address(burnRedeem), true);
        tokens[0].contractAddress = address(oz1155Burnable);
        tokens[0].itemIndex = 5;
        burnRedeem.burnRedeem{value: burnFee}(address(creator), 1, 1, tokens);
        assertEq(0, oz1155Burnable.balanceOf(anyone1, 1));
        assertEq(0, oz1155Burnable.balanceOf(address(0x000000000000000000000000000000000000dEaD), 1));

        vm.stopPrank();
    }

    function testSetActive() public {
       // stop new burns from being initialized
        vm.startPrank(burnRedeemOwner);
        burnRedeem.setActive(false);
        vm.stopPrank();

        vm.startPrank(owner);
        IBurnRedeemCoreV2.BurnItem[] memory items = new IBurnRedeemCoreV2.BurnItem[](1);
        items[0] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.CONTRACT,
            contractAddress: address(burnable1155),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC1155,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.MANIFOLD,
            amount: 1,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        IBurnRedeemCoreV2.BurnGroup[] memory group = new IBurnRedeemCoreV2.BurnGroup[](1);
        group[0] = IBurnRedeemCoreV2.BurnGroup({
            requiredCount: 1,
            items: items
        });
        IBurnRedeemCoreV2.BurnRedeemParameters memory params = IBurnRedeemCoreV2.BurnRedeemParameters({
            paymentReceiver: payable(owner),
            storageProtocol: IBurnRedeemCoreV2.StorageProtocol.NONE,
            redeemAmount: 2,
            totalSupply: 10,
            startDate: uint48(block.timestamp - 30),
            endDate: uint48(block.timestamp + 1000),
            cost: 0,
            location: "XXX",
            burnSet: group
        });
        vm.expectRevert(IBurnRedeemCoreV2.Inactive.selector);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params, true);
        vm.stopPrank();

        // resume new burns
        vm.startPrank(burnRedeemOwner);
        burnRedeem.setActive(true);
        vm.stopPrank();

        vm.startPrank(owner);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params, true);
        vm.stopPrank();

        // can still burn even if claim creations are paused
        vm.startPrank(burnRedeemOwner);
        burnRedeem.setActive(false);
        vm.stopPrank();

        vm.startPrank(owner);
        address[] memory recipients = new address[](1);
        recipients[0] = anyone1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 3;
        string[] memory uris = new string[](1);
        uris[0] = "";

        uint256[] memory tokenIds = burnable1155.mintBaseNew(recipients, amounts, uris);

        // check they own 3x 1155 tokens
        assertEq(burnable1155.balanceOf(anyone1, tokenIds[0]), 3);

        vm.stopPrank();
        
        vm.startPrank(anyone1);

        vm.deal(anyone1, 1 ether);
        IBurnRedeemCoreV2.BurnToken[] memory tokens = new IBurnRedeemCoreV2.BurnToken[](1);
        tokens[0] = IBurnRedeemCoreV2.BurnToken({
            groupIndex: 0,
            itemIndex: 0,
            contractAddress: address(burnable1155),
            id: tokenIds[0],
            merkleProof: new bytes32[](0)
        });
        burnable1155.setApprovalForAll(address(burnRedeem), true);
        burnRedeem.burnRedeem{value: defaultBurnFee}(address(creator), 1, 1, tokens);
        vm.stopPrank();

    }

}
