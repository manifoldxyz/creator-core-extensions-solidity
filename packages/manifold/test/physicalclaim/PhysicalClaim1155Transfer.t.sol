// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./PhysicalClaimBase.t.sol";
import "../../contracts/physicalclaim/PhysicalClaim.sol";
import "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC721Creator.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC1155Creator.sol";
import "../mocks/Mock.sol";

contract PhysicalClaim1155TransferTest is PhysicalClaimBase {
    PhysicalClaim public example;
    ERC721Creator public creatorCore721;
    ERC1155Creator public creatorCore1155;
    MockERC20 public mockERC20;
    MockManifoldMembership public manifoldMembership;

    address public owner = 0x6140F00e4Ff3936702E68744f2b5978885464cbB;
    address public other1 = 0xc78Dc443c126af6E4f6Ed540c1e740C1b5be09cd;
    address public other2 = 0x80AAC46bbd3C2FcE33681541a52CacBEd14bF425;
    address public seller = 0x5174cD462b60c536eb51D4ceC1D561D3Ea31004F;

    address public zeroSigner = address(0);

    address public zeroAddress = address(0);

    address public signingAddress;

    function setUp() public {
        vm.startPrank(owner);
        creatorCore721 = new ERC721Creator("Token721", "NFT721");
        creatorCore1155 = new ERC1155Creator("Token1155", "NFT1155");
        mockERC20 = new MockERC20("Token20", "ERC20");
        manifoldMembership = new MockManifoldMembership();

        signingAddress = vm.addr(privateKey);
        example = new PhysicalClaim(owner, signingAddress);

        vm.deal(owner, 10 ether);
        vm.deal(other1, 10 ether);
        vm.deal(other2, 10 ether);
        vm.stopPrank();
    }

    function testInvalidData() public {
        vm.startPrank(owner);
        address[] memory recipients = new address[](1);
        recipients[0] = other1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10;
        string[] memory uris = new string[](1);
        creatorCore1155.mintBaseNew(recipients, amounts, uris);
        vm.stopPrank();

        vm.startPrank(other1);
        vm.expectRevert("ERC1155: transfer to non-ERC1155Receiver implementer");
        creatorCore1155.safeTransferFrom(other1, address(example), 1, 1, "");
        vm.stopPrank();
    }

    function testInvalidBurnTokenLength() public {
        vm.startPrank(owner);
        example.setMembershipAddress(address(manifoldMembership));
        manifoldMembership.setMember(other1, true);
        address[] memory recipients = new address[](1);
        recipients[0] = other1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10;
        string[] memory uris = new string[](1);
        creatorCore1155.mintBaseNew(recipients, amounts, uris);
        vm.stopPrank();

        IPhysicalClaim.BurnToken[] memory burnTokens = new IPhysicalClaim.BurnToken[](0);

        uint256 instanceId = 100;
        uint8 variation = 2;
        uint64 variationLimit = 0;
        uint64 totalLimit = 0;
        address erc20 = address(0);
        uint256 price = 0;
        address payable fundsRecipient = payable(address(0));
        uint160 expiration = uint160(block.timestamp + 1000);
        bytes32 nonce = bytes32(bytes4(0xdeadbeef));

        IPhysicalClaim.BurnSubmission memory submission = constructSubmission(instanceId, burnTokens, variation, variationLimit, totalLimit, erc20, price, fundsRecipient, expiration, nonce);

        vm.startPrank(other1);
        // Note: Current ERC1155 implementation does not pass through revert messages
        vm.expectRevert("ERC1155: transfer to non-ERC1155Receiver implementer");
        //vm.expectRevert(IPhysicalClaim.InvalidInput.selector);
        creatorCore1155.safeTransferFrom(other1, address(example), 1, 1, abi.encode(submission));
        vm.stopPrank();
    }

    function testCannotReceive1() public {
        vm.startPrank(owner);
        address[] memory recipients = new address[](1);
        recipients[0] = other1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10;
        string[] memory uris = new string[](1);
        creatorCore1155.mintBaseNew(recipients, amounts, uris);
        vm.stopPrank();

        IPhysicalClaim.BurnToken[] memory burnTokens = new IPhysicalClaim.BurnToken[](1);
        burnTokens[0] = IPhysicalClaim.BurnToken({
            contractAddress: address(creatorCore1155),
            tokenId: 1,
            tokenSpec: IPhysicalClaim.TokenSpec.ERC1155,
            burnSpec: IPhysicalClaim.BurnSpec.MANIFOLD,
            amount: 1
        });

        uint256 instanceId = 100;
        uint8 variation = 2;
        uint64 variationLimit = 0;
        uint64 totalLimit = 0;
        address erc20 = address(0);
        uint256 price = 0;
        address payable fundsRecipient = payable(address(0));
        uint160 expiration = uint160(block.timestamp + 1000);
        bytes32 nonce = bytes32(bytes4(0xdeadbeef));

        IPhysicalClaim.BurnSubmission memory submission = constructSubmission(instanceId, burnTokens, variation, variationLimit, totalLimit, erc20, price, fundsRecipient, expiration, nonce);

        vm.startPrank(other1);
        // Note: Current ERC1155 implementation does not pass through revert messages
        vm.expectRevert("ERC1155: transfer to non-ERC1155Receiver implementer");
        //vm.expectRevert(IPhysicalClaim.InvalidInput.selector);
        creatorCore1155.safeTransferFrom(other1, address(example), 1, 1, abi.encode(submission));
        vm.stopPrank();
    }

    function testCannotReceive2() public {
        vm.startPrank(owner);
        example.setMembershipAddress(address(manifoldMembership));
        manifoldMembership.setMember(other1, true);
        address[] memory recipients = new address[](1);
        recipients[0] = other1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10;
        string[] memory uris = new string[](1);
        creatorCore1155.mintBaseNew(recipients, amounts, uris);
        vm.stopPrank();

        IPhysicalClaim.BurnToken[] memory burnTokens = new IPhysicalClaim.BurnToken[](1);
        burnTokens[0] = IPhysicalClaim.BurnToken({
            contractAddress: address(creatorCore1155),
            tokenId: 1,
            tokenSpec: IPhysicalClaim.TokenSpec.ERC1155,
            burnSpec: IPhysicalClaim.BurnSpec.MANIFOLD,
            amount: 1
        });

        uint256 instanceId = 100;
        uint8 variation = 2;
        uint64 variationLimit = 0;
        uint64 totalLimit = 0;
        address erc20 = address(0);
        uint256 price = 1;
        address payable fundsRecipient = payable(address(0));
        uint160 expiration = uint160(block.timestamp + 1000);
        bytes32 nonce = bytes32(bytes4(0xdeadbeef));

        IPhysicalClaim.BurnSubmission memory submission = constructSubmission(instanceId, burnTokens, variation, variationLimit, totalLimit, erc20, price, fundsRecipient, expiration, nonce);

        vm.startPrank(other1);
        // Note: Current ERC1155 implementation does not pass through revert messages
        vm.expectRevert("ERC1155: transfer to non-ERC1155Receiver implementer");
        //vm.expectRevert(IPhysicalClaim.InvalidInput.selector);
        creatorCore1155.safeTransferFrom(other1, address(example), 1, 1, abi.encode(submission));
        vm.stopPrank();
    }
    
    function testInvalidBurnToken1() public {
        vm.startPrank(owner);
        example.setMembershipAddress(address(manifoldMembership));
        manifoldMembership.setMember(other1, true);
        address[] memory recipients = new address[](1);
        recipients[0] = other1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10;
        string[] memory uris = new string[](1);
        creatorCore1155.mintBaseNew(recipients, amounts, uris);
        vm.stopPrank();

        IPhysicalClaim.BurnToken[] memory burnTokens = new IPhysicalClaim.BurnToken[](1);
        burnTokens[0] = IPhysicalClaim.BurnToken({
            contractAddress: address(creatorCore1155),
            tokenId: 1,
            tokenSpec: IPhysicalClaim.TokenSpec.ERC721,
            burnSpec: IPhysicalClaim.BurnSpec.MANIFOLD,
            amount: 1
        });

        uint256 instanceId = 100;
        uint8 variation = 2;
        uint64 variationLimit = 0;
        uint64 totalLimit = 0;
        address erc20 = address(0);
        uint256 price = 0;
        address payable fundsRecipient = payable(address(0));
        uint160 expiration = uint160(block.timestamp + 1000);
        bytes32 nonce = bytes32(bytes4(0xdeadbeef));

        IPhysicalClaim.BurnSubmission memory submission = constructSubmission(instanceId, burnTokens, variation, variationLimit, totalLimit, erc20, price, fundsRecipient, expiration, nonce);

        vm.startPrank(other1);
        // Note: Current ERC1155 implementation does not pass through revert messages
        vm.expectRevert("ERC1155: transfer to non-ERC1155Receiver implementer");
        //vm.expectRevert(IPhysicalClaim.InvalidInput.selector);
        creatorCore1155.safeTransferFrom(other1, address(example), 1, 1, abi.encode(submission));
        vm.stopPrank();
    }

    function testInvalidBurnToken2() public {
        vm.startPrank(owner);
        example.setMembershipAddress(address(manifoldMembership));
        manifoldMembership.setMember(other1, true);
        address[] memory recipients = new address[](1);
        recipients[0] = other1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10;
        string[] memory uris = new string[](1);
        creatorCore1155.mintBaseNew(recipients, amounts, uris);
        vm.stopPrank();

        IPhysicalClaim.BurnToken[] memory burnTokens = new IPhysicalClaim.BurnToken[](1);
        burnTokens[0] = IPhysicalClaim.BurnToken({
            contractAddress: address(creatorCore1155),
            tokenId: 2,
            tokenSpec: IPhysicalClaim.TokenSpec.ERC1155,
            burnSpec: IPhysicalClaim.BurnSpec.MANIFOLD,
            amount: 1
        });

        uint256 instanceId = 100;
        uint8 variation = 2;
        uint64 variationLimit = 0;
        uint64 totalLimit = 0;
        address erc20 = address(0);
        uint256 price = 0;
        address payable fundsRecipient = payable(address(0));
        uint160 expiration = uint160(block.timestamp + 1000);
        bytes32 nonce = bytes32(bytes4(0xdeadbeef));

        IPhysicalClaim.BurnSubmission memory submission = constructSubmission(instanceId, burnTokens, variation, variationLimit, totalLimit, erc20, price, fundsRecipient, expiration, nonce);

        vm.startPrank(other1);
        // Note: Current ERC1155 implementation does not pass through revert messages
        vm.expectRevert("ERC1155: transfer to non-ERC1155Receiver implementer");
        //vm.expectRevert(abi.encodeWithSelector(IPhysicalClaim.InvalidToken.selector, address(creatorCore1155), 2));
        creatorCore1155.safeTransferFrom(other1, address(example), 1, 1, abi.encode(submission));
        vm.stopPrank();
    }

    function testInvalidBurnToken3() public {
        vm.startPrank(owner);
        example.setMembershipAddress(address(manifoldMembership));
        manifoldMembership.setMember(other1, true);
        address[] memory recipients = new address[](1);
        recipients[0] = other1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10;
        string[] memory uris = new string[](1);
        creatorCore1155.mintBaseNew(recipients, amounts, uris);
        vm.stopPrank();

        IPhysicalClaim.BurnToken[] memory burnTokens = new IPhysicalClaim.BurnToken[](1);
        burnTokens[0] = IPhysicalClaim.BurnToken({
            contractAddress: address(creatorCore721),
            tokenId: 1,
            tokenSpec: IPhysicalClaim.TokenSpec.ERC1155,
            burnSpec: IPhysicalClaim.BurnSpec.MANIFOLD,
            amount: 1
        });

        uint256 instanceId = 100;
        uint8 variation = 2;
        uint64 variationLimit = 0;
        uint64 totalLimit = 0;
        address erc20 = address(0);
        uint256 price = 0;
        address payable fundsRecipient = payable(address(0));
        uint160 expiration = uint160(block.timestamp + 1000);
        bytes32 nonce = bytes32(bytes4(0xdeadbeef));

        IPhysicalClaim.BurnSubmission memory submission = constructSubmission(instanceId, burnTokens, variation, variationLimit, totalLimit, erc20, price, fundsRecipient, expiration, nonce);

        vm.startPrank(other1);
        // Note: Current ERC1155 implementation does not pass through revert messages
        vm.expectRevert("ERC1155: transfer to non-ERC1155Receiver implementer");
        //vm.expectRevert(abi.encodeWithSelector(IPhysicalClaim.InvalidToken.selector, address(creatorCore721), 1));
        creatorCore1155.safeTransferFrom(other1, address(example), 1, 1, abi.encode(submission));
        vm.stopPrank();
    }

    function testInvalidSignature() public {
        vm.startPrank(owner);
        example.setMembershipAddress(address(manifoldMembership));
        manifoldMembership.setMember(other1, true);
        address[] memory recipients = new address[](1);
        recipients[0] = other1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10;
        string[] memory uris = new string[](1);
        creatorCore1155.mintBaseNew(recipients, amounts, uris);
        vm.stopPrank();

        IPhysicalClaim.BurnToken[] memory burnTokens = new IPhysicalClaim.BurnToken[](1);
        burnTokens[0] = IPhysicalClaim.BurnToken({
            contractAddress: address(creatorCore1155),
            tokenId: 1,
            tokenSpec: IPhysicalClaim.TokenSpec.ERC1155,
            burnSpec: IPhysicalClaim.BurnSpec.MANIFOLD,
            amount: 1
        });

        uint256 instanceId = 100;
        uint8 variation = 2;
        uint64 variationLimit = 0;
        uint64 totalLimit = 0;
        address erc20 = address(0);
        uint256 price = 0;
        address payable fundsRecipient = payable(address(0));
        uint160 expiration = uint160(block.timestamp + 1000);
        bytes32 nonce = bytes32(bytes4(0xdeadbeef));

        IPhysicalClaim.BurnSubmission memory submission = constructSubmission(instanceId, burnTokens, variation, variationLimit, totalLimit, erc20, price, fundsRecipient, expiration, nonce);

        // Test redeem because we have an invalid signature
        // Change configured signer
        vm.startPrank(owner);
        example.updateSigner(other2);
        vm.stopPrank();
        vm.startPrank(other1);
        // Note: Current ERC1155 implementation does not pass through revert messages
        vm.expectRevert("ERC1155: transfer to non-ERC1155Receiver implementer");
        //vm.expectRevert(IPhysicalClaim.InvalidSignature.selector);
        creatorCore1155.safeTransferFrom(other1, address(example), 1, 1, abi.encode(submission));
        vm.stopPrank();
    }

    function testInvalidMessage() public {
        vm.startPrank(owner);
        example.setMembershipAddress(address(manifoldMembership));
        manifoldMembership.setMember(other1, true);
        address[] memory recipients = new address[](1);
        recipients[0] = other1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10;
        string[] memory uris = new string[](1);
        creatorCore1155.mintBaseNew(recipients, amounts, uris);
        vm.stopPrank();

        IPhysicalClaim.BurnToken[] memory burnTokens = new IPhysicalClaim.BurnToken[](1);
        burnTokens[0] = IPhysicalClaim.BurnToken({
            contractAddress: address(creatorCore1155),
            tokenId: 1,
            tokenSpec: IPhysicalClaim.TokenSpec.ERC1155,
            burnSpec: IPhysicalClaim.BurnSpec.MANIFOLD,
            amount: 1
        });

        uint256 instanceId = 100;
        uint8 variation = 2;
        uint64 variationLimit = 0;
        uint64 totalLimit = 0;
        address erc20 = address(0);
        uint256 price = 0;
        address payable fundsRecipient = payable(address(0));
        uint160 expiration = uint160(block.timestamp + 1000);
        bytes32 nonce = bytes32(bytes4(0xdeadbeef));

        IPhysicalClaim.BurnSubmission memory submission = constructSubmission(instanceId, burnTokens, variation, variationLimit, totalLimit, erc20, price, fundsRecipient, expiration, nonce);

        // Test redeem because we change the data
        submission.message = bytes32(0);
        vm.startPrank(other1);
        // Note: Current ERC1155 implementation does not pass through revert messages
        vm.expectRevert("ERC1155: transfer to non-ERC1155Receiver implementer");
        //vm.expectRevert(IPhysicalClaim.InvalidSignature.selector);
        creatorCore1155.safeTransferFrom(other1, address(example), 1, 1, abi.encode(submission));
        vm.stopPrank();
    }

    function testInvalidDueToDataChange() public {
        vm.startPrank(owner);
        example.setMembershipAddress(address(manifoldMembership));
        manifoldMembership.setMember(other1, true);
        address[] memory recipients = new address[](1);
        recipients[0] = other1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10;
        string[] memory uris = new string[](1);
        creatorCore1155.mintBaseNew(recipients, amounts, uris);
        vm.stopPrank();

        IPhysicalClaim.BurnToken[] memory burnTokens = new IPhysicalClaim.BurnToken[](1);
        burnTokens[0] = IPhysicalClaim.BurnToken({
            contractAddress: address(creatorCore1155),
            tokenId: 1,
            tokenSpec: IPhysicalClaim.TokenSpec.ERC1155,
            burnSpec: IPhysicalClaim.BurnSpec.MANIFOLD,
            amount: 1
        });

        uint256 instanceId = 100;
        uint8 variation = 2;
        uint64 variationLimit = 0;
        uint64 totalLimit = 0;
        address erc20 = address(0);
        uint256 price = 0;
        address payable fundsRecipient = payable(address(0));
        uint160 expiration = uint160(block.timestamp + 1000);
        bytes32 nonce = bytes32(bytes4(0xdeadbeef));

        IPhysicalClaim.BurnSubmission memory submission = constructSubmission(instanceId, burnTokens, variation, variationLimit, totalLimit, erc20, price, fundsRecipient, expiration, nonce);

        // Test redeem because we change the data
        submission.variationLimit = 10;
        vm.startPrank(other1);
        // Note: Current ERC1155 implementation does not pass through revert messages
        vm.expectRevert("ERC1155: transfer to non-ERC1155Receiver implementer");
        //vm.expectRevert(IPhysicalClaim.InvalidSignature.selector);
        creatorCore1155.safeTransferFrom(other1, address(example), 1, 1, abi.encode(submission));
        vm.stopPrank();
    }

    function testInvalidDueToExpired() public {
        vm.startPrank(owner);
        example.setMembershipAddress(address(manifoldMembership));
        manifoldMembership.setMember(other1, true);
        address[] memory recipients = new address[](1);
        recipients[0] = other1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10;
        string[] memory uris = new string[](1);
        creatorCore1155.mintBaseNew(recipients, amounts, uris);
        vm.stopPrank();

        IPhysicalClaim.BurnToken[] memory burnTokens = new IPhysicalClaim.BurnToken[](1);
        burnTokens[0] = IPhysicalClaim.BurnToken({
            contractAddress: address(creatorCore1155),
            tokenId: 1,
            tokenSpec: IPhysicalClaim.TokenSpec.ERC1155,
            burnSpec: IPhysicalClaim.BurnSpec.MANIFOLD,
            amount: 1
        });

        uint256 instanceId = 100;
        uint8 variation = 2;
        uint64 variationLimit = 0;
        uint64 totalLimit = 0;
        address erc20 = address(0);
        uint256 price = 0;
        address payable fundsRecipient = payable(address(0));
        uint160 expiration = uint160(block.timestamp - 1);
        bytes32 nonce = bytes32(bytes4(0xdeadbeef));

        IPhysicalClaim.BurnSubmission memory submission = constructSubmission(instanceId, burnTokens, variation, variationLimit, totalLimit, erc20, price, fundsRecipient, expiration, nonce);

        // Test redeem because it is expired
        vm.startPrank(other1);
        // Note: Current ERC1155 implementation does not pass through revert messages
        vm.expectRevert("ERC1155: transfer to non-ERC1155Receiver implementer");
        //vm.expectRevert(IPhysicalClaim.ExpiredSignature.selector);
        creatorCore1155.safeTransferFrom(other1, address(example), 1, 1, abi.encode(submission));
        vm.stopPrank();
    }

    function testNotEnoughTokens() public {
        vm.startPrank(owner);
        example.setMembershipAddress(address(manifoldMembership));
        manifoldMembership.setMember(other1, true);
        address[] memory recipients = new address[](1);
        recipients[0] = other1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10;
        string[] memory uris = new string[](1);
        creatorCore1155.mintBaseNew(recipients, amounts, uris);
        vm.stopPrank();

        IPhysicalClaim.BurnToken[] memory burnTokens = new IPhysicalClaim.BurnToken[](1);
        burnTokens[0] = IPhysicalClaim.BurnToken({
            contractAddress: address(creatorCore1155),
            tokenId: 1,
            tokenSpec: IPhysicalClaim.TokenSpec.ERC1155,
            burnSpec: IPhysicalClaim.BurnSpec.MANIFOLD,
            amount: 2
        });

        uint256 instanceId = 100;
        uint8 variation = 2;
        uint64 variationLimit = 0;
        uint64 totalLimit = 0;
        address erc20 = address(0);
        uint256 price = 0;
        address payable fundsRecipient = payable(address(0));
        uint160 expiration = uint160(block.timestamp + 100);
        bytes32 nonce = bytes32(bytes4(0xdeadbeef));

        IPhysicalClaim.BurnSubmission memory submission = constructSubmission(instanceId, burnTokens, variation, variationLimit, totalLimit, erc20, price, fundsRecipient, expiration, nonce);

        // Test redeem
        vm.startPrank(other1);
        // Note: Current ERC1155 implementation does not pass through revert messages
        vm.expectRevert("ERC1155: transfer to non-ERC1155Receiver implementer");
        //vm.expectRevert(IPhysicalClaim.InvalidBurnAmount.selector);
        creatorCore1155.safeTransferFrom(other1, address(example), 1, 1, abi.encode(submission));
        vm.stopPrank();
    }

    function testPhyiscalClaim() public {
        vm.startPrank(owner);
        example.setMembershipAddress(address(manifoldMembership));
        manifoldMembership.setMember(other1, true);
        address[] memory recipients = new address[](1);
        recipients[0] = other1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10;
        string[] memory uris = new string[](1);
        creatorCore1155.mintBaseNew(recipients, amounts, uris);
        vm.stopPrank();

        IPhysicalClaim.BurnToken[] memory burnTokens = new IPhysicalClaim.BurnToken[](1);
        burnTokens[0] = IPhysicalClaim.BurnToken({
            contractAddress: address(creatorCore1155),
            tokenId: 1,
            tokenSpec: IPhysicalClaim.TokenSpec.ERC1155,
            burnSpec: IPhysicalClaim.BurnSpec.MANIFOLD,
            amount: 2
        });

        uint256 instanceId = 100;
        uint8 variation = 2;
        uint64 variationLimit = 0;
        uint64 totalLimit = 0;
        address erc20 = address(0);
        uint256 price = 0;
        address payable fundsRecipient = payable(address(0));
        uint160 expiration = uint160(block.timestamp + 100);
        bytes32 nonce = bytes32(bytes4(0xdeadbeef));

        IPhysicalClaim.BurnSubmission memory submission = constructSubmission(instanceId, burnTokens, variation, variationLimit, totalLimit, erc20, price, fundsRecipient, expiration, nonce);

        // Test redeem
        vm.startPrank(other1);
        creatorCore1155.safeTransferFrom(other1, address(example), 1, 2, abi.encode(submission));
        vm.stopPrank();

        // Check token burned
        assertEq(creatorCore1155.balanceOf(other1, 1), 8);
    }

    function testPhyiscalClaimSoldOut() public {
        vm.startPrank(owner);
        example.setMembershipAddress(address(manifoldMembership));
        manifoldMembership.setMember(other1, true);
        address[] memory recipients = new address[](1);
        recipients[0] = other1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10;
        string[] memory uris = new string[](1);
        creatorCore1155.mintBaseNew(recipients, amounts, uris);
        vm.stopPrank();

        IPhysicalClaim.BurnToken[] memory burnTokens = new IPhysicalClaim.BurnToken[](1);
        burnTokens[0] = IPhysicalClaim.BurnToken({
            contractAddress: address(creatorCore1155),
            tokenId: 1,
            tokenSpec: IPhysicalClaim.TokenSpec.ERC1155,
            burnSpec: IPhysicalClaim.BurnSpec.MANIFOLD,
            amount: 2
        });

        uint256 instanceId = 100;
        uint8 variation = 2;
        uint64 variationLimit = 0;
        uint64 totalLimit = 1;
        address erc20 = address(0);
        uint256 price = 0;
        address payable fundsRecipient = payable(address(0));
        uint160 expiration = uint160(block.timestamp + 100);
        bytes32 nonce = bytes32(bytes4(0xdeadbeef));

        IPhysicalClaim.BurnSubmission memory submission = constructSubmission(instanceId, burnTokens, variation, variationLimit, totalLimit, erc20, price, fundsRecipient, expiration, nonce);

        // Test redeem
        vm.startPrank(other1);
        creatorCore1155.safeTransferFrom(other1, address(example), 1, 2, abi.encode(submission));
        vm.stopPrank();

        // Check correct amount of tokens burned
        assertEq(creatorCore1155.balanceOf(other1, 1), 8);

        // Test redeem again (should fail)
        nonce = bytes32(bytes4(0xdeafbeef));
        submission = constructSubmission(instanceId, burnTokens, variation, variationLimit, totalLimit, erc20, price, fundsRecipient, expiration, nonce);
        vm.startPrank(other1);
        // Note: Current ERC1155 implementation does not pass through revert messages
        vm.expectRevert("ERC1155: transfer to non-ERC1155Receiver implementer");
        //vm.expectRevert(IPhysicalClaim.SoldOut.selector);
        creatorCore1155.safeTransferFrom(other1, address(example), 1, 2, abi.encode(submission));
        vm.stopPrank();

        // Check correct amount of tokens burned
        assertEq(creatorCore1155.balanceOf(other1, 1), 8);
    }

    function testPhyiscalClaimWithERC20() public {
        vm.startPrank(owner);
        example.setMembershipAddress(address(manifoldMembership));
        manifoldMembership.setMember(other1, true);
        address[] memory recipients = new address[](1);
        recipients[0] = other1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10;
        string[] memory uris = new string[](1);
        creatorCore1155.mintBaseNew(recipients, amounts, uris);
        mockERC20.fakeMint(other2, 200);
        vm.stopPrank();

        IPhysicalClaim.BurnToken[] memory burnTokens = new IPhysicalClaim.BurnToken[](1);
        burnTokens[0] = IPhysicalClaim.BurnToken({
            contractAddress: address(creatorCore1155),
            tokenId: 1,
            tokenSpec: IPhysicalClaim.TokenSpec.ERC1155,
            burnSpec: IPhysicalClaim.BurnSpec.MANIFOLD,
            amount: 2
        });

        uint256 instanceId = 100;
        uint8 variation = 2;
        uint64 variationLimit = 0;
        uint64 totalLimit = 0;
        address erc20 = address(mockERC20);
        uint256 price = 15;
        address payable fundsRecipient = payable(seller);
        uint160 expiration = uint160(block.timestamp + 100);
        bytes32 nonce = bytes32(bytes4(0xdeadbeef));

        IPhysicalClaim.BurnSubmission memory submission = constructSubmission(instanceId, burnTokens, variation, variationLimit, totalLimit, erc20, price, fundsRecipient, expiration, nonce);

        // Approve spend from other2
        vm.startPrank(other2);
        mockERC20.approve(address(example), 15);
        vm.stopPrank();

        // Test redeem (should fail, cannot steal someone else's balance)
        vm.startPrank(other1);
        vm.expectRevert("ERC20: insufficient allowance");
        creatorCore1155.safeTransferFrom(other1, address(example), 1, 2, abi.encode(submission));
        mockERC20.approve(address(example), 15);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        creatorCore1155.safeTransferFrom(other1, address(example), 1, 2, abi.encode(submission));
        vm.stopPrank();

        // Mint to other1
        vm.startPrank(owner);
        mockERC20.fakeMint(other1, 200);
        vm.stopPrank();
    
        // Approve spend from other1
        vm.startPrank(other1);
        creatorCore1155.safeTransferFrom(other1, address(example), 1, 2, abi.encode(submission));
        vm.stopPrank();

        // Check token burned
        vm.expectRevert("ERC721: invalid token ID");
        creatorCore721.ownerOf(1);

        // Check seller got price
        assertEq(mockERC20.balanceOf(address(seller)), 15);
        assertEq(mockERC20.balanceOf(address(other1)), 185);
    }

  }
