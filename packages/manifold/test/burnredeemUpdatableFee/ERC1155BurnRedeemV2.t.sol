// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../contracts/burnredeemUpdatableFee/ERC1155BurnRedeemV2.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC721Creator.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC1155Creator.sol";

import "../mocks/Mock.sol";

contract ManifoldERC1155BurnRedeemV2Test is Test {
    ERC1155BurnRedeemV2 public burnRedeem;
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
        creator = new ERC1155Creator("Test", "TEST");
        burnRedeem = new ERC1155BurnRedeemV2(burnRedeemOwner);
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
        burnRedeem.initializeBurnRedeem(address(creator), 1, params);

        // Succeeds because admin
        vm.prank(owner);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params);

        // Fails because not admin
        vm.prank(anyone1);
        vm.expectRevert(abi.encodePacked(IBurnRedeemCoreV2.NotAdmin.selector, uint256(uint160(address(creator)))));
        burnRedeem.updateBurnRedeem(address(creator), 1, params);

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
        burnRedeem.initializeBurnRedeem(address(creator), 1, params);


        // Fails due to non-mod-0 redeemAmount
        params.endDate = uint48(block.timestamp + 1000);
        params.redeemAmount = 3;
        vm.expectRevert(IBurnRedeemCoreV2.InvalidRedeemAmount.selector);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params);

        // Cannot update non-existant burn redeem
        vm.expectRevert(abi.encodePacked(IBurnRedeemCoreV2.BurnRedeemDoesNotExist.selector, uint256(1)));
        burnRedeem.updateBurnRedeem(address(creator), 1, params);

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
        burnRedeem.initializeBurnRedeem(address(creator), 1, params);

        // Cannot have ValidationType == INVALID on burn item
        items[0].amount = 1;
        items[0].validationType = IBurnRedeemCoreV2.ValidationType.INVALID;
        vm.expectRevert(IBurnRedeemCoreV2.InvalidInput.selector);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params);

        // Cannot have TokenSpec == INVALID on burn item
        items[0].validationType = IBurnRedeemCoreV2.ValidationType.CONTRACT;
        items[0].tokenSpec = IBurnRedeemCoreV2.TokenSpec.INVALID;
        vm.expectRevert(IBurnRedeemCoreV2.InvalidInput.selector);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params);

        // Cannot have requiredCount == 0 on burn group
        items[0].tokenSpec = IBurnRedeemCoreV2.TokenSpec.ERC1155;
        group[0].requiredCount = 0;
        vm.expectRevert(IBurnRedeemCoreV2.InvalidInput.selector);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params);

        // Cannot have requiredCount > items.length on burn group
        group[0].requiredCount = 2;
        vm.expectRevert(IBurnRedeemCoreV2.InvalidInput.selector);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params);

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
        burnRedeem.initializeBurnRedeem(address(creator), 1, params);

        params.endDate = uint48(block.timestamp - 60);
        // Fails due to endDate <= startDate
        vm.expectRevert(BurnRedeemLibV2.InvalidDates.selector);
        burnRedeem.updateBurnRedeem(address(creator), 1, params);

        // Fails due to non-mod-0 redeemAmount
        params.endDate = uint48(block.timestamp + 1000);
        params.redeemAmount = 3;
        vm.expectRevert(IBurnRedeemCoreV2.InvalidRedeemAmount.selector);
        burnRedeem.updateBurnRedeem(address(creator), 1, params);

        IBurnRedeemCoreV2.BurnToken[] memory tokens = new IBurnRedeemCoreV2.BurnToken[](0);
        uint256 burnFee = burnRedeem.BURN_FEE();
        burnRedeem.burnRedeem{value: burnFee*2}(address(creator), 1, 2, tokens);

        // Fails due to non-mod-0 redeemAmount after redemptions
        params.redeemAmount = 3;
        params.totalSupply = 9;
        vm.expectRevert(IBurnRedeemCoreV2.InvalidRedeemAmount.selector);
        burnRedeem.updateBurnRedeem(address(creator), 1, params);

        // totalSupply = redeemedCount if updated below redeemedCount
        params.redeemAmount = 1;
        params.totalSupply = 1;
        burnRedeem.updateBurnRedeem(address(creator), 1, params);
        IBurnRedeemCoreV2.BurnRedeem memory burnInstance = burnRedeem.getBurnRedeem(address(creator), 1);
        assertEq(burnInstance.totalSupply, 2);

        // totalSupply = 0 if updated to 0 and redeemedCount > 0
        params.totalSupply = 0;
        burnRedeem.updateBurnRedeem(address(creator), 1, params);
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
        burnRedeem.initializeBurnRedeem(address(creator), 1, params);
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

        string memory uri = creator.uri(1);
        assertEq(uri, "XXX");

        vm.stopPrank();
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
        burnRedeem.initializeBurnRedeem(address(creator), 1, params);
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

        // Check balances
        assertEq(2, creator.balanceOf(anyone1, 1));
        assertEq(2, creator.balanceOf(anyone2, 1));

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
        assertEq(20, creator.balanceOf(anyone1, 1));
        assertEq(20, creator.balanceOf(anyone2, 1));

        // Reverts when redeemedCount would exceed max uint32
        recipients = new address[](1);
        recipients[0] = anyone1;
        amounts = new uint32[](1);
        amounts[0] = 2147483647;
        vm.prank(owner);
        vm.expectRevert(IBurnRedeemCoreV2.InvalidRedeemAmount.selector);
        burnRedeem.airdrop(address(creator), 1, recipients, amounts);
    }

    function testBurnRedeemWithMixedItems() public {
        // Set up the burn items
        IBurnRedeemCoreV2.BurnItem[] memory items = new IBurnRedeemCoreV2.BurnItem[](2);
        items[0] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.CONTRACT,
            contractAddress: address(burnable1155),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC1155,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.MANIFOLD,
            amount: 3,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });
        items[1] = IBurnRedeemCoreV2.BurnItem({
            validationType: IBurnRedeemCoreV2.ValidationType.CONTRACT,
            contractAddress: address(burnable721),
            tokenSpec: IBurnRedeemCoreV2.TokenSpec.ERC721,
            burnSpec: IBurnRedeemCoreV2.BurnSpec.NONE,
            amount: 0,
            minTokenId: 0,
            maxTokenId: 0,
            merkleRoot: bytes32(0)
        });

        // Set up the burn group
        IBurnRedeemCoreV2.BurnGroup[] memory group = new IBurnRedeemCoreV2.BurnGroup[](1);
        group[0] = IBurnRedeemCoreV2.BurnGroup({
            requiredCount: 1,
            items: items
        });

        // Set up the burn redeem parameters
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

        // Initialize the burn redeem
        vm.startPrank(owner);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params);
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


        // Approve the burn redeem contract to burn the tokens
        vm.startPrank(anyone1);
        burnable1155.setApprovalForAll(address(burnRedeem), true);

        vm.deal(anyone1, 1 ether);

        // Perform the burn redeem
        // @note: we only use one group here because the item it maps to has the 3x multiplier
        IBurnRedeemCoreV2.BurnToken[] memory tokens = new IBurnRedeemCoreV2.BurnToken[](1);
        tokens[0] = IBurnRedeemCoreV2.BurnToken({
            groupIndex: 0,
            itemIndex: 0,
            contractAddress: address(burnable1155),
            id: tokenIds[0],
            merkleProof: new bytes32[](0)
        });

        uint256 burnFee = burnRedeem.MULTI_BURN_FEE();
        burnRedeem.burnRedeem{value: burnFee}(address(creator), 1, 1, tokens);

        // Verify the burns
        assertEq(burnable1155.balanceOf(anyone1, tokenIds[0]), 0);
        vm.stopPrank();
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
        burnRedeem.initializeBurnRedeem(address(creator), 1, params);
        vm.stopPrank();

        // resume new burns
        vm.startPrank(burnRedeemOwner);
        burnRedeem.setActive(true);
        vm.stopPrank();

        vm.startPrank(owner);
        burnRedeem.initializeBurnRedeem(address(creator), 1, params);
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
