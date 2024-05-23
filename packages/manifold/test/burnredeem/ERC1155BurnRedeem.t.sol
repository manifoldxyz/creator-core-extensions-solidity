// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../contracts/burnredeem/ERC1155BurnRedeem.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC721Creator.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC1155Creator.sol";

import "../mocks/Mock.sol";

contract ManifoldERC1155BurnRedeemTest is Test {
    ERC1155BurnRedeem public burnRedeem;
    ERC1155Creator public creator;
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

    address public owner = 0x6140F00e4Ff3936702E68744f2b5978885464cbB;
    address public burnRedeemOwner = 0xc78Dc443c126af6E4f6Ed540c1e740C1b5be09cd;
    address public anyone1 = 0x80AAC46bbd3C2FcE33681541a52CacBEd14bF425;
    address public anyone2 = 0x5174cD462b60c536eb51D4ceC1D561D3Ea31004F;

    address public zeroAddress = address(0);
    address public deadAddress = 0x000000000000000000000000000000000000dEaD;

    function setUp() public {
        vm.startPrank(owner);
        creator = new ERC1155Creator("Test", "TEST");
        burnRedeem = new ERC1155BurnRedeem(burnRedeemOwner);
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

        vm.prank(burnRedeemOwner);
        burnRedeem.setMembershipAddress(address(manifoldMembership));
        vm.warp(100000);
    }

    function testAccess() public {
        IBurnRedeemCore.BurnGroup[] memory group = new IBurnRedeemCore.BurnGroup[](0);
        IBurnRedeemCore.BurnRedeemParameters memory params = IBurnRedeemCore.BurnRedeemParameters({
            paymentReceiver: payable(owner),
            storageProtocol: IBurnRedeemCore.StorageProtocol.NONE,
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
        vm.expectRevert(abi.encodePacked(IBurnRedeemCore.NotAdmin.selector, uint256(uint160(address(creator)))));
        burnRedeem.initializeBurnRedeem(address(creator), 1, params);

        // Succeeds because admin
        vm.prank(owner);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params);

        // Fails because not admin
        vm.prank(anyone1);
        vm.expectRevert(abi.encodePacked(IBurnRedeemCore.NotAdmin.selector, uint256(uint160(address(creator)))));
        burnRedeem.updateBurnRedeem(address(creator), 1, params);
    }

    function testInitializeSanitation() public {
        IBurnRedeemCore.BurnGroup[] memory group = new IBurnRedeemCore.BurnGroup[](0);
        IBurnRedeemCore.BurnRedeemParameters memory params = IBurnRedeemCore.BurnRedeemParameters({
            paymentReceiver: payable(owner),
            storageProtocol: IBurnRedeemCore.StorageProtocol.NONE,
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
        vm.expectRevert(BurnRedeemLib.InvalidDates.selector);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params);


        // Fails due to non-mod-0 redeemAmount
        params.endDate = uint48(block.timestamp + 1000);
        params.redeemAmount = 3;
        vm.expectRevert(IBurnRedeemCore.InvalidRedeemAmount.selector);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params);

        // Cannot update non-existant burn redeem
        vm.expectRevert(abi.encodePacked(IBurnRedeemCore.BurnRedeemDoesNotExist.selector, uint256(1)));
        burnRedeem.updateBurnRedeem(address(creator), 1, params);

        // Cannot have amount == 0 on ERC1155 burn item
        IBurnRedeemCore.BurnItem[] memory items = new IBurnRedeemCore.BurnItem[](1);
        items[0] = IBurnRedeemCore.BurnItem({
            validationType: IBurnRedeemCore.ValidationType.CONTRACT,
            contractAddress: address(burnable1155),
            tokenSpec: IBurnRedeemCore.TokenSpec.ERC1155,
            burnSpec: IBurnRedeemCore.BurnSpec.MANIFOLD,
            amount: 0,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        params.redeemAmount = 1;
        group = new IBurnRedeemCore.BurnGroup[](1);
        group[0] = IBurnRedeemCore.BurnGroup({
            requiredCount: 1,
            items: items
        });
        params.burnSet = group;
        vm.expectRevert(IBurnRedeemCore.InvalidInput.selector);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params);

        // Cannot have ValidationType == INVALID on burn item
        items[0].amount = 1;
        items[0].validationType = IBurnRedeemCore.ValidationType.INVALID;
        vm.expectRevert(IBurnRedeemCore.InvalidInput.selector);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params);

        // Cannot have TokenSpec == INVALID on burn item
        items[0].validationType = IBurnRedeemCore.ValidationType.CONTRACT;
        items[0].tokenSpec = IBurnRedeemCore.TokenSpec.INVALID;
        vm.expectRevert(IBurnRedeemCore.InvalidInput.selector);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params);

        // Cannot have requiredCount == 0 on burn group
        items[0].tokenSpec = IBurnRedeemCore.TokenSpec.ERC1155;
        group[0].requiredCount = 0;
        vm.expectRevert(IBurnRedeemCore.InvalidInput.selector);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params);

        // Cannot have requiredCount > items.length on burn group
        group[0].requiredCount = 2;
        vm.expectRevert(IBurnRedeemCore.InvalidInput.selector);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params);

        vm.stopPrank();
    }

    function testUpdateSanitation() public {
        IBurnRedeemCore.BurnGroup[] memory group = new IBurnRedeemCore.BurnGroup[](0);
        IBurnRedeemCore.BurnRedeemParameters memory params = IBurnRedeemCore.BurnRedeemParameters({
            paymentReceiver: payable(owner),
            storageProtocol: IBurnRedeemCore.StorageProtocol.NONE,
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
        burnRedeem.initializeBurnRedeem(address(creator), 1, params);

        params.endDate = uint48(block.timestamp - 60);
        // Fails due to endDate <= startDate
        vm.expectRevert(BurnRedeemLib.InvalidDates.selector);
        burnRedeem.updateBurnRedeem(address(creator), 1, params);

        // Fails due to non-mod-0 redeemAmount
        params.endDate = uint48(block.timestamp + 1000);
        params.redeemAmount = 3;
        vm.expectRevert(IBurnRedeemCore.InvalidRedeemAmount.selector);
        burnRedeem.updateBurnRedeem(address(creator), 1, params);

        IBurnRedeemCore.BurnToken[] memory tokens = new IBurnRedeemCore.BurnToken[](0);
        uint256 burnFee = burnRedeem.BURN_FEE();
        burnRedeem.burnRedeem{value: burnFee*2}(address(creator), 1, 2, tokens);

        // Fails due to non-mod-0 redeemAmount after redemptions
        params.redeemAmount = 3;
        params.totalSupply = 9;
        vm.expectRevert(IBurnRedeemCore.InvalidRedeemAmount.selector);
        burnRedeem.updateBurnRedeem(address(creator), 1, params);

        // totalSupply = redeemedCount if updated below redeemedCount
        params.redeemAmount = 1;
        params.totalSupply = 1;
        burnRedeem.updateBurnRedeem(address(creator), 1, params);
        IBurnRedeemCore.BurnRedeem memory burnInstance = burnRedeem.getBurnRedeem(address(creator), 1);
        assertEq(burnInstance.totalSupply, 2);

        // totalSupply = 0 if updated to 0 and redeemedCount > 0
        params.totalSupply = 0;
        burnRedeem.updateBurnRedeem(address(creator), 1, params);
        burnInstance = burnRedeem.getBurnRedeem(address(creator), 1);
        assertEq(burnInstance.totalSupply, 0);

        vm.stopPrank();
    }

    function testTokenURI() public {
        IBurnRedeemCore.BurnItem[] memory items = new IBurnRedeemCore.BurnItem[](1);
        items[0] = IBurnRedeemCore.BurnItem({
            validationType: IBurnRedeemCore.ValidationType.CONTRACT,
            contractAddress: address(burnable721),
            tokenSpec: IBurnRedeemCore.TokenSpec.ERC721,
            burnSpec: IBurnRedeemCore.BurnSpec.MANIFOLD,
            amount: 0,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        IBurnRedeemCore.BurnGroup[] memory group = new IBurnRedeemCore.BurnGroup[](1);
        group[0] = IBurnRedeemCore.BurnGroup({
            requiredCount: 1,
            items: items
        });
        IBurnRedeemCore.BurnRedeemParameters memory params = IBurnRedeemCore.BurnRedeemParameters({
            paymentReceiver: payable(owner),
            storageProtocol: IBurnRedeemCore.StorageProtocol.NONE,
            redeemAmount: 1,
            totalSupply: 10,
            startDate: uint48(block.timestamp - 30),
            endDate: uint48(block.timestamp + 1000),
            cost: 0,
            location: "XXX",
            burnSet: group
        });
        vm.startPrank(owner);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params);
        burnable721.mintBase(anyone1);
        vm.stopPrank();
        vm.deal(anyone1, 1 ether);
        vm.startPrank(anyone1);
        burnable721.setApprovalForAll(address(burnRedeem), true);
        bytes32[] memory merkleProof;
        IBurnRedeemCore.BurnToken[] memory tokens = new IBurnRedeemCore.BurnToken[](1);
        tokens[0] = IBurnRedeemCore.BurnToken({
            groupIndex: 0,
            itemIndex: 0,
            contractAddress: address(burnable721),
            id: 1,
            merkleProof: merkleProof
        });
        uint256 burnFee = burnRedeem.BURN_FEE();
        burnRedeem.burnRedeem{value: burnFee}(address(creator), 1, 1, tokens);

        string memory uri = creator.uri(1);
        assertEq(uri, "XXX");

        vm.stopPrank();
    }

    function testBurnAnything() public {
        IBurnRedeemCore.BurnItem[] memory items = new IBurnRedeemCore.BurnItem[](6);
        // tokenSpec: ERC-721, burnSpec: NONE
        items[0] = IBurnRedeemCore.BurnItem({
            validationType: IBurnRedeemCore.ValidationType.ANY,
            contractAddress: address(0),
            tokenSpec: IBurnRedeemCore.TokenSpec.ERC721,
            burnSpec: IBurnRedeemCore.BurnSpec.NONE,
            amount: 0,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        // tokenSpec: ERC-721, burnSpec: MANIFOLD
        items[1] = IBurnRedeemCore.BurnItem({
            validationType: IBurnRedeemCore.ValidationType.ANY,
            contractAddress: address(0),
            tokenSpec: IBurnRedeemCore.TokenSpec.ERC721,
            burnSpec: IBurnRedeemCore.BurnSpec.MANIFOLD,
            amount: 0,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        // tokenSpec: ERC-721, burnSpec: OPENZEPPELIN
        items[2] = IBurnRedeemCore.BurnItem({
            validationType: IBurnRedeemCore.ValidationType.ANY,
            contractAddress: address(0),
            tokenSpec: IBurnRedeemCore.TokenSpec.ERC721,
            burnSpec: IBurnRedeemCore.BurnSpec.OPENZEPPELIN,
            amount: 0,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        // tokenSpec: ERC-1155, burnSpec: NONE
        items[3] = IBurnRedeemCore.BurnItem({
            validationType: IBurnRedeemCore.ValidationType.ANY,
            contractAddress: address(0),
            tokenSpec: IBurnRedeemCore.TokenSpec.ERC1155,
            burnSpec: IBurnRedeemCore.BurnSpec.NONE,
            amount: 1,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        // tokenSpec: ERC-1155, burnSpec: MANIFOLD
        items[4] = IBurnRedeemCore.BurnItem({
            validationType: IBurnRedeemCore.ValidationType.ANY,
            contractAddress: address(0),
            tokenSpec: IBurnRedeemCore.TokenSpec.ERC1155,
            burnSpec: IBurnRedeemCore.BurnSpec.MANIFOLD,
            amount: 1,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        // tokenSpec: ERC-1155, burnSpec: OPENZEPPELIN
        items[5] = IBurnRedeemCore.BurnItem({
            validationType: IBurnRedeemCore.ValidationType.ANY,
            contractAddress: address(0),
            tokenSpec: IBurnRedeemCore.TokenSpec.ERC1155,
            burnSpec: IBurnRedeemCore.BurnSpec.OPENZEPPELIN,
            amount: 1,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        IBurnRedeemCore.BurnGroup[] memory group = new IBurnRedeemCore.BurnGroup[](1);
        group[0] = IBurnRedeemCore.BurnGroup({
            requiredCount: 1,
            items: items
        });
        IBurnRedeemCore.BurnRedeemParameters memory params = IBurnRedeemCore.BurnRedeemParameters({
            paymentReceiver: payable(owner),
            storageProtocol: IBurnRedeemCore.StorageProtocol.NONE,
            redeemAmount: 1,
            totalSupply: 10,
            startDate: uint48(block.timestamp - 30),
            endDate: uint48(block.timestamp + 1000),
            cost: 0,
            location: "XXX",
            burnSet: group
        });
        vm.startPrank(owner);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params);

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
        IBurnRedeemCore.BurnToken[] memory tokens = new IBurnRedeemCore.BurnToken[](1);
        tokens[0] = IBurnRedeemCore.BurnToken({
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

    function testOnERC1155ReceivedMultiple() public {
        IBurnRedeemCore.BurnItem[] memory items = new IBurnRedeemCore.BurnItem[](1);
        items[0] = IBurnRedeemCore.BurnItem({
            validationType: IBurnRedeemCore.ValidationType.CONTRACT,
            contractAddress: address(burnable1155),
            tokenSpec: IBurnRedeemCore.TokenSpec.ERC1155,
            burnSpec: IBurnRedeemCore.BurnSpec.MANIFOLD,
            amount: 2,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        IBurnRedeemCore.BurnGroup[] memory group = new IBurnRedeemCore.BurnGroup[](1);
        group[0] = IBurnRedeemCore.BurnGroup({
            requiredCount: 1,
            items: items
        });
        IBurnRedeemCore.BurnRedeemParameters memory params = IBurnRedeemCore.BurnRedeemParameters({
            paymentReceiver: payable(owner),
            storageProtocol: IBurnRedeemCore.StorageProtocol.NONE,
            redeemAmount: 1,
            totalSupply: 3,
            startDate: uint48(block.timestamp - 30),
            endDate: uint48(block.timestamp + 1000),
            cost: 0,
            location: "XXX",
            burnSet: group
        });
        vm.startPrank(owner);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params);
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
        assertEq(2  , creator.balanceOf(anyone1, 1));
        vm.stopPrank();
    }

    function testWithdraw() public {
        IBurnRedeemCore.BurnItem[] memory items = new IBurnRedeemCore.BurnItem[](1);
        items[0] = IBurnRedeemCore.BurnItem({
            validationType: IBurnRedeemCore.ValidationType.CONTRACT,
            contractAddress: address(burnable721),
            tokenSpec: IBurnRedeemCore.TokenSpec.ERC721,
            burnSpec: IBurnRedeemCore.BurnSpec.MANIFOLD,
            amount: 0,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        IBurnRedeemCore.BurnGroup[] memory group = new IBurnRedeemCore.BurnGroup[](1);
        group[0] = IBurnRedeemCore.BurnGroup({
            requiredCount: 1,
            items: items
        });
        IBurnRedeemCore.BurnRedeemParameters memory params = IBurnRedeemCore.BurnRedeemParameters({
            paymentReceiver: payable(owner),
            storageProtocol: IBurnRedeemCore.StorageProtocol.NONE,
            redeemAmount: 1,
            totalSupply: 10,
            startDate: uint48(block.timestamp - 30),
            endDate: uint48(block.timestamp + 1000),
            cost: 0,
            location: "XXX",
            burnSet: group
        });
        vm.startPrank(owner);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params);
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
        IBurnRedeemCore.BurnToken[][] memory allTokens = new IBurnRedeemCore.BurnToken[][](10);
        for (uint256 i = 0; i < 10; i++) {
            addresses[i] = address(creator);
            indexes[i] = 1;
            burnCounts[i] = 1;
            IBurnRedeemCore.BurnToken[] memory tokens = new IBurnRedeemCore.BurnToken[](1);
            IBurnRedeemCore.BurnToken memory token = IBurnRedeemCore.BurnToken({
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
        IBurnRedeemCore.BurnItem[] memory items = new IBurnRedeemCore.BurnItem[](1);
        items[0] = IBurnRedeemCore.BurnItem({
            validationType: IBurnRedeemCore.ValidationType.CONTRACT,
            contractAddress: address(burnable721),
            tokenSpec: IBurnRedeemCore.TokenSpec.ERC721,
            burnSpec: IBurnRedeemCore.BurnSpec.MANIFOLD,
            amount: 0,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        IBurnRedeemCore.BurnGroup[] memory group = new IBurnRedeemCore.BurnGroup[](1);
        group[0] = IBurnRedeemCore.BurnGroup({
            requiredCount: 1,
            items: items
        });
        IBurnRedeemCore.BurnRedeemParameters memory params = IBurnRedeemCore.BurnRedeemParameters({
            paymentReceiver: payable(owner),
            storageProtocol: IBurnRedeemCore.StorageProtocol.NONE,
            redeemAmount: 2,
            totalSupply: 10,
            startDate: uint48(block.timestamp - 30),
            endDate: uint48(block.timestamp + 1000),
            cost: 0,
            location: "XXX",
            burnSet: group
        });
        vm.startPrank(owner);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params);
        vm.stopPrank();

        address[] memory recipients = new address[](2);
        recipients[0] = anyone1;
        recipients[1] = anyone2;
        uint32[] memory amounts = new uint32[](2);
        amounts[0] = 1;
        amounts[1] = 1;

        vm.prank(anyone1);
        vm.expectRevert(abi.encodePacked(IBurnRedeemCore.NotAdmin.selector, uint256(uint160(address(creator)))));
        burnRedeem.airdrop(address(creator), 1, recipients, amounts);

        vm.prank(owner);
        burnRedeem.airdrop(address(creator), 1, recipients, amounts);

        // Check balances
        assertEq(2, creator.balanceOf(anyone1, 1));
        assertEq(2, creator.balanceOf(anyone2, 1));

        // redeemedCount updated
        IBurnRedeemCore.BurnRedeem memory burnInstance = burnRedeem.getBurnRedeem(address(creator), 1);
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
        assertEq(20, creator.balanceOf(anyone1, 1));
        assertEq(20, creator.balanceOf(anyone2, 1));

        // Reverts when redeemedCount would exceed max uint32
        recipients = new address[](1);
        recipients[0] = anyone1;
        amounts = new uint32[](1);
        amounts[0] = 2147483647;
        vm.prank(owner);
        vm.expectRevert(IBurnRedeemCore.InvalidRedeemAmount.selector);
        burnRedeem.airdrop(address(creator), 1, recipients, amounts);
    }

}
