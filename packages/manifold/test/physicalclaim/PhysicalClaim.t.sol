// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../contracts/physicalclaim/PhysicalClaim.sol";
import "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC721Creator.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC1155Creator.sol";
import "../mocks/Mock.sol";

contract PhysicalClaimTest is Test {
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
    uint256 privateKey = 0x1010101010101010101010101010101010101010101010101010101010101010;

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

    function testAccess() public {
        vm.startPrank(other1);
        vm.expectRevert("AdminControl: Must be owner or admin");
        example.recover(address(creatorCore721), 1, other1);
        vm.expectRevert("AdminControl: Must be owner or admin");
        example.withdraw(payable(other1), 1 ether);
        vm.expectRevert("AdminControl: Must be owner or admin");
        example.setMembershipAddress(other1);
        vm.expectRevert("AdminControl: Must be owner or admin");
        example.updateSigner(address(0));
        vm.stopPrank();

        // Accidentally send token to contract
        vm.startPrank(owner);
        creatorCore721.mintBase(owner, "");
        creatorCore721.transferFrom(owner, address(example), 1);
        example.recover(address(creatorCore721), 1, owner);
        vm.stopPrank();

        // Test withdraw
        vm.deal(address(example), 10 ether);
        vm.startPrank(owner);
        example.withdraw(payable(other1), 1 ether);
        assertEq(address(example).balance, 9 ether);
        assertEq(other1.balance, 11 ether);
        vm.stopPrank();

        // Test setMembershipAddress
        vm.startPrank(owner);
        example.setMembershipAddress(other2);
        assertEq(example.manifoldMembershipContract(), other2);
        vm.stopPrank();

        // Test updateSigner
        vm.startPrank(owner);
        example.updateSigner(seller);
        vm.stopPrank();

    }

    function testSupportsInterface() public {
        vm.startPrank(owner);

        bytes4 interfaceId = type(IPhysicalClaim).interfaceId;
        assertEq(example.supportsInterface(interfaceId), true);
        assertEq(example.supportsInterface(0xffffffff), false);

        interfaceId = type(IERC721Receiver).interfaceId;
        assertEq(example.supportsInterface(interfaceId), true);

        interfaceId = type(IERC1155Receiver).interfaceId;
        assertEq(example.supportsInterface(interfaceId), true);

        interfaceId = type(AdminControl).interfaceId;
        assertEq(example.supportsInterface(interfaceId), true);

        vm.stopPrank();
    }

    function testTransferFailures() public {
        IPhysicalClaim.BurnToken[] memory burnTokens = new IPhysicalClaim.BurnToken[](1);
        burnTokens[0] = IPhysicalClaim.BurnToken({
            contractAddress: address(creatorCore721),
            tokenId: 1,
            tokenSpec: IPhysicalClaim.TokenSpec.ERC721,
            burnSpec: IPhysicalClaim.BurnSpec.MANIFOLD,
            amount: 1
        });

        uint256 instanceId = 100;
        uint8 variation = 2;
        uint64 variationLimit = 0;
        address erc20 = address(0);
        uint256 price = 0;
        address payable fundsRecipient = payable(address(0));
        uint160 expiration = uint160(block.timestamp + 1000);
        uint256 burnFee = PhysicalClaim(example).BURN_FEE();
        bytes32 nonce = bytes32(bytes4(0xdeadbeef));

        IPhysicalClaim.BurnSubmission memory submission = constructSubmission(instanceId, burnTokens, variation, variationLimit, erc20, price, fundsRecipient, expiration, nonce);

        // Test redeem failure because token does not exist
        vm.startPrank(other1);
        vm.expectRevert("ERC721: invalid token ID");
        example.burnRedeem{value: burnFee}(submission);
        vm.stopPrank();

        vm.startPrank(owner);
        creatorCore721.mintBase(other1, "");
        vm.stopPrank();

        // Test redeem failure because token not approved
        vm.startPrank(other1);
        vm.expectRevert("Caller is not owner or approved");
        example.burnRedeem{value: burnFee}(submission);
        vm.stopPrank();

        // Test redeem failure because token is notowned by sender
        vm.startPrank(other1);
        creatorCore721.approve(address(example), 1);
        vm.stopPrank();
        vm.startPrank(other2);
        vm.expectRevert(IPhysicalClaim.TransferFailure.selector);
        example.burnRedeem{value: burnFee}(submission);
        vm.stopPrank();
    }

    function testInvalidPaymentAmountFee() public {
        vm.startPrank(owner);
        creatorCore721.mintBase(other1, "");
        vm.stopPrank();

        IPhysicalClaim.BurnToken[] memory burnTokens = new IPhysicalClaim.BurnToken[](1);
        burnTokens[0] = IPhysicalClaim.BurnToken({
            contractAddress: address(creatorCore721),
            tokenId: 1,
            tokenSpec: IPhysicalClaim.TokenSpec.ERC721,
            burnSpec: IPhysicalClaim.BurnSpec.MANIFOLD,
            amount: 1
        });

        uint256 instanceId = 100;
        uint8 variation = 2;
        uint64 variationLimit = 0;
        address erc20 = address(0);
        uint256 price = 0;
        address payable fundsRecipient = payable(address(0));
        uint160 expiration = uint160(block.timestamp + 1000);
        uint256 burnFee = PhysicalClaim(example).BURN_FEE();
        bytes32 nonce = bytes32(bytes4(0xdeadbeef));

        IPhysicalClaim.BurnSubmission memory submission = constructSubmission(instanceId, burnTokens, variation, variationLimit, erc20, price, fundsRecipient, expiration, nonce);

        // Test redeem
        vm.startPrank(other1);
        creatorCore721.approve(address(example), 1);
        vm.expectRevert(IPhysicalClaim.InvalidPaymentAmount.selector);
        example.burnRedeem{value: burnFee-1}(submission);
        vm.stopPrank();
    }
    
    function testInvalidPaymentAmountPrice() public {
        vm.startPrank(owner);
        creatorCore721.mintBase(other1, "");
        vm.stopPrank();

        IPhysicalClaim.BurnToken[] memory burnTokens = new IPhysicalClaim.BurnToken[](1);
        burnTokens[0] = IPhysicalClaim.BurnToken({
            contractAddress: address(creatorCore721),
            tokenId: 1,
            tokenSpec: IPhysicalClaim.TokenSpec.ERC721,
            burnSpec: IPhysicalClaim.BurnSpec.MANIFOLD,
            amount: 1
        });

        uint256 instanceId = 100;
        uint8 variation = 2;
        uint64 variationLimit = 0;
        address erc20 = address(0);
        uint256 price = 1;
        address payable fundsRecipient = payable(address(0));
        uint160 expiration = uint160(block.timestamp + 1000);
        uint256 burnFee = PhysicalClaim(example).BURN_FEE();
        bytes32 nonce = bytes32(bytes4(0xdeadbeef));

        IPhysicalClaim.BurnSubmission memory submission = constructSubmission(instanceId, burnTokens, variation, variationLimit, erc20, price, fundsRecipient, expiration, nonce);

        // Test redeem
        vm.startPrank(other1);
        creatorCore721.approve(address(example), 1);
        vm.expectRevert(IPhysicalClaim.InvalidPaymentAmount.selector);
        example.burnRedeem{value: burnFee}(submission);
        vm.stopPrank();
    }

    function testInvalidSignature() public {
        vm.startPrank(owner);
        creatorCore721.mintBase(other1, "");
        vm.stopPrank();

        IPhysicalClaim.BurnToken[] memory burnTokens = new IPhysicalClaim.BurnToken[](1);
        burnTokens[0] = IPhysicalClaim.BurnToken({
            contractAddress: address(creatorCore721),
            tokenId: 1,
            tokenSpec: IPhysicalClaim.TokenSpec.ERC721,
            burnSpec: IPhysicalClaim.BurnSpec.MANIFOLD,
            amount: 1
        });

        uint256 instanceId = 100;
        uint8 variation = 2;
        uint64 variationLimit = 0;
        address erc20 = address(0);
        uint256 price = 0;
        address payable fundsRecipient = payable(address(0));
        uint160 expiration = uint160(block.timestamp + 1000);
        uint256 burnFee = PhysicalClaim(example).BURN_FEE();
        bytes32 nonce = bytes32(bytes4(0xdeadbeef));

        IPhysicalClaim.BurnSubmission memory submission = constructSubmission(instanceId, burnTokens, variation, variationLimit, erc20, price, fundsRecipient, expiration, nonce);

        // Test redeem because we have an invalid signature
        // Change configured signer
        vm.startPrank(owner);
        example.updateSigner(other2);
        vm.stopPrank();
        vm.startPrank(other1);
        creatorCore721.approve(address(example), 1);
        vm.expectRevert(IPhysicalClaim.InvalidSignature.selector);
        example.burnRedeem{value: burnFee}(submission);
        vm.stopPrank();
    }

    function testInvalidMessage() public {
        vm.startPrank(owner);
        creatorCore721.mintBase(other1, "");
        vm.stopPrank();

        IPhysicalClaim.BurnToken[] memory burnTokens = new IPhysicalClaim.BurnToken[](1);
        burnTokens[0] = IPhysicalClaim.BurnToken({
            contractAddress: address(creatorCore721),
            tokenId: 1,
            tokenSpec: IPhysicalClaim.TokenSpec.ERC721,
            burnSpec: IPhysicalClaim.BurnSpec.MANIFOLD,
            amount: 1
        });

        uint256 instanceId = 100;
        uint8 variation = 2;
        uint64 variationLimit = 0;
        address erc20 = address(0);
        uint256 price = 0;
        address payable fundsRecipient = payable(address(0));
        uint160 expiration = uint160(block.timestamp + 1000);
        uint256 burnFee = PhysicalClaim(example).BURN_FEE();
        bytes32 nonce = bytes32(bytes4(0xdeadbeef));

        IPhysicalClaim.BurnSubmission memory submission = constructSubmission(instanceId, burnTokens, variation, variationLimit, erc20, price, fundsRecipient, expiration, nonce);

        // Test redeem because we change the data
        submission.message = bytes32(0);
        vm.startPrank(other1);
        creatorCore721.approve(address(example), 1);
        vm.expectRevert(IPhysicalClaim.InvalidSignature.selector);
        example.burnRedeem{value: burnFee}(submission);
        vm.stopPrank();
    }

    function testInvalidDueToDataChange() public {
        vm.startPrank(owner);
        creatorCore721.mintBase(other1, "");
        vm.stopPrank();

        IPhysicalClaim.BurnToken[] memory burnTokens = new IPhysicalClaim.BurnToken[](1);
        burnTokens[0] = IPhysicalClaim.BurnToken({
            contractAddress: address(creatorCore721),
            tokenId: 1,
            tokenSpec: IPhysicalClaim.TokenSpec.ERC721,
            burnSpec: IPhysicalClaim.BurnSpec.MANIFOLD,
            amount: 1
        });

        uint256 instanceId = 100;
        uint8 variation = 2;
        uint64 variationLimit = 0;
        address erc20 = address(0);
        uint256 price = 0;
        address payable fundsRecipient = payable(address(0));
        uint160 expiration = uint160(block.timestamp + 1000);
        uint256 burnFee = PhysicalClaim(example).BURN_FEE();
        bytes32 nonce = bytes32(bytes4(0xdeadbeef));

        IPhysicalClaim.BurnSubmission memory submission = constructSubmission(instanceId, burnTokens, variation, variationLimit, erc20, price, fundsRecipient, expiration, nonce);

        // Test redeem because we change the data
        submission.variationLimit = 10;
        vm.startPrank(other1);
        creatorCore721.approve(address(example), 1);
        vm.expectRevert(IPhysicalClaim.InvalidSignature.selector);
        example.burnRedeem{value: burnFee}(submission);
        vm.stopPrank();
    }

    function testInvalidDueToExpired() public {
        vm.startPrank(owner);
        creatorCore721.mintBase(other1, "");
        vm.stopPrank();

        IPhysicalClaim.BurnToken[] memory burnTokens = new IPhysicalClaim.BurnToken[](1);
        burnTokens[0] = IPhysicalClaim.BurnToken({
            contractAddress: address(creatorCore721),
            tokenId: 1,
            tokenSpec: IPhysicalClaim.TokenSpec.ERC721,
            burnSpec: IPhysicalClaim.BurnSpec.MANIFOLD,
            amount: 1
        });

        uint256 instanceId = 100;
        uint8 variation = 2;
        uint64 variationLimit = 0;
        address erc20 = address(0);
        uint256 price = 0;
        address payable fundsRecipient = payable(address(0));
        uint160 expiration = uint160(block.timestamp - 1);
        uint256 burnFee = PhysicalClaim(example).BURN_FEE();
        bytes32 nonce = bytes32(bytes4(0xdeadbeef));

        IPhysicalClaim.BurnSubmission memory submission = constructSubmission(instanceId, burnTokens, variation, variationLimit, erc20, price, fundsRecipient, expiration, nonce);

        // Test redeem because we change the data
        vm.startPrank(other1);
        creatorCore721.approve(address(example), 1);
        vm.expectRevert(IPhysicalClaim.ExpiredSignature.selector);
        example.burnRedeem{value: burnFee}(submission);
        vm.stopPrank();
    }

    function testInvalidBurnSpec721() public {
        IPhysicalClaim.BurnToken[] memory burnTokens = new IPhysicalClaim.BurnToken[](1);
        burnTokens[0] = IPhysicalClaim.BurnToken({
            contractAddress: address(creatorCore721),
            tokenId: 1,
            tokenSpec: IPhysicalClaim.TokenSpec.ERC721,
            burnSpec: IPhysicalClaim.BurnSpec.INVALID,
            amount: 1
        });

        uint256 instanceId = 100;
        uint8 variation = 2;
        uint64 variationLimit = 0;
        address erc20 = address(0);
        uint256 price = 0;
        address payable fundsRecipient = payable(address(0));
        uint160 expiration = uint160(block.timestamp + 1000);
        uint256 burnFee = PhysicalClaim(example).BURN_FEE();
        bytes32 nonce = bytes32(bytes4(0xdeadbeef));

        IPhysicalClaim.BurnSubmission memory submission = constructSubmission(instanceId, burnTokens, variation, variationLimit, erc20, price, fundsRecipient, expiration, nonce);

        // Test redeem
        vm.startPrank(other1);
        vm.expectRevert(IPhysicalClaim.InvalidBurnSpec.selector);
        example.burnRedeem{value: burnFee}(submission);
        vm.stopPrank();

    }

    function testInvalidBurnSpec1155() public {
        IPhysicalClaim.BurnToken[] memory burnTokens = new IPhysicalClaim.BurnToken[](1);
        burnTokens[0] = IPhysicalClaim.BurnToken({
            contractAddress: address(creatorCore1155),
            tokenId: 1,
            tokenSpec: IPhysicalClaim.TokenSpec.ERC1155,
            burnSpec: IPhysicalClaim.BurnSpec.INVALID,
            amount: 1
        });

        uint256 instanceId = 100;
        uint8 variation = 2;
        uint64 variationLimit = 0;
        address erc20 = address(0);
        uint256 price = 0;
        address payable fundsRecipient = payable(address(0));
        uint160 expiration = uint160(block.timestamp + 1000);
        uint256 burnFee = PhysicalClaim(example).BURN_FEE();
        bytes32 nonce = bytes32(bytes4(0xdeadbeef));

        IPhysicalClaim.BurnSubmission memory submission = constructSubmission(instanceId, burnTokens, variation, variationLimit, erc20, price, fundsRecipient, expiration, nonce);

        // Test redeem
        vm.startPrank(other1);
        vm.expectRevert(IPhysicalClaim.InvalidBurnSpec.selector);
        example.burnRedeem{value: burnFee}(submission);
        vm.stopPrank();

    }


    function testInvalidTokeSpec() public {
        vm.startPrank(owner);
        creatorCore721.mintBase(other1, "");
        vm.stopPrank();

        IPhysicalClaim.BurnToken[] memory burnTokens = new IPhysicalClaim.BurnToken[](1);
        burnTokens[0] = IPhysicalClaim.BurnToken({
            contractAddress: address(creatorCore721),
            tokenId: 1,
            tokenSpec: IPhysicalClaim.TokenSpec.INVALID,
            burnSpec: IPhysicalClaim.BurnSpec.NONE,
            amount: 1
        });

        uint256 instanceId = 100;
        uint8 variation = 2;
        uint64 variationLimit = 0;
        address erc20 = address(0);
        uint256 price = 0;
        address payable fundsRecipient = payable(address(0));
        uint160 expiration = uint160(block.timestamp + 1000);
        uint256 burnFee = PhysicalClaim(example).BURN_FEE();
        bytes32 nonce = bytes32(bytes4(0xdeadbeef));

        IPhysicalClaim.BurnSubmission memory submission = constructSubmission(instanceId, burnTokens, variation, variationLimit, erc20, price, fundsRecipient, expiration, nonce);

        // Test redeem
        vm.startPrank(other1);
        creatorCore721.approve(address(example), 1);
        vm.expectRevert(IPhysicalClaim.InvalidTokenSpec.selector);
        example.burnRedeem{value: burnFee}(submission);
        vm.stopPrank();

    }

    function testNoBurnFromNonOwnerInvalid() public {
        vm.startPrank(owner);
        creatorCore721.mintBase(other1, "");
        vm.stopPrank();

        IPhysicalClaim.BurnToken[] memory burnTokens = new IPhysicalClaim.BurnToken[](1);
        burnTokens[0] = IPhysicalClaim.BurnToken({
            contractAddress: address(creatorCore721),
            tokenId: 1,
            tokenSpec: IPhysicalClaim.TokenSpec.ERC721_NO_BURN,
            burnSpec: IPhysicalClaim.BurnSpec.NONE,
            amount: 1
        });

        uint256 instanceId = 100;
        uint8 variation = 2;
        uint64 variationLimit = 0;
        address erc20 = address(0);
        uint256 price = 0;
        address payable fundsRecipient = payable(address(0));
        uint160 expiration = uint160(block.timestamp + 1000);
        uint256 burnFee = PhysicalClaim(example).BURN_FEE();
        bytes32 nonce = bytes32(bytes4(0xdeadbeef));

        IPhysicalClaim.BurnSubmission memory submission = constructSubmission(instanceId, burnTokens, variation, variationLimit, erc20, price, fundsRecipient, expiration, nonce);

        // Test redeem from non-owner should fail
        vm.startPrank(other2);
        vm.expectRevert(IPhysicalClaim.TransferFailure.selector);
        example.burnRedeem{value: burnFee}(submission);
        vm.stopPrank();

    }

    function testNoBurnMultiUseInvalid() public {
        vm.startPrank(owner);
        creatorCore721.mintBase(other1, "");
        vm.stopPrank();

        IPhysicalClaim.BurnToken[] memory burnTokens = new IPhysicalClaim.BurnToken[](1);
        burnTokens[0] = IPhysicalClaim.BurnToken({
            contractAddress: address(creatorCore721),
            tokenId: 1,
            tokenSpec: IPhysicalClaim.TokenSpec.ERC721_NO_BURN,
            burnSpec: IPhysicalClaim.BurnSpec.NONE,
            amount: 1
        });

        uint256 instanceId = 100;
        uint8 variation = 2;
        uint64 variationLimit = 0;
        address erc20 = address(0);
        uint256 price = 0;
        address payable fundsRecipient = payable(address(0));
        uint160 expiration = uint160(block.timestamp + 1000);
        uint256 burnFee = PhysicalClaim(example).BURN_FEE();
        bytes32 nonce = bytes32(bytes4(0xdeadbeef));

        IPhysicalClaim.BurnSubmission memory submission = constructSubmission(instanceId, burnTokens, variation, variationLimit, erc20, price, fundsRecipient, expiration, nonce);

        // Test redeem
        vm.startPrank(other1);
        example.burnRedeem{value: burnFee}(submission);
        vm.stopPrank();

        // Check token not burned
        assertEq(creatorCore721.ownerOf(1), other1);

        // Try redemption again, not allowed because nonce was used marked as consumed
        vm.startPrank(other1);
        vm.expectRevert(IPhysicalClaim.InvalidNonce.selector);
        example.burnRedeem{value: burnFee}(submission);
        vm.stopPrank();

        // Try redemption again (different nonce), not allowed because it was marked as consumed
        nonce = bytes32(bytes4(0xdeafbeef));
        submission = constructSubmission(instanceId, burnTokens, variation, variationLimit, erc20, price, fundsRecipient, expiration, nonce);
        vm.startPrank(other1);
        vm.expectRevert(abi.encodeWithSelector(IPhysicalClaim.InvalidToken.selector, address(creatorCore721), 1));
        example.burnRedeem{value: burnFee}(submission);
        vm.stopPrank();
    }

    function testInvalidBurnAmount721() public {
        vm.startPrank(owner);
        creatorCore721.mintBase(other1, "");
        vm.stopPrank();

        IPhysicalClaim.BurnToken[] memory burnTokens = new IPhysicalClaim.BurnToken[](1);
        burnTokens[0] = IPhysicalClaim.BurnToken({
            contractAddress: address(creatorCore721),
            tokenId: 1,
            tokenSpec: IPhysicalClaim.TokenSpec.ERC721,
            burnSpec: IPhysicalClaim.BurnSpec.MANIFOLD,
            amount: 2
        });

        uint256 instanceId = 100;
        uint8 variation = 2;
        uint64 variationLimit = 0;
        address erc20 = address(0);
        uint256 price = 0;
        address payable fundsRecipient = payable(address(0));
        uint160 expiration = uint160(block.timestamp + 1000);
        uint256 burnFee = PhysicalClaim(example).BURN_FEE();
        bytes32 nonce = bytes32(bytes4(0xdeadbeef));

        IPhysicalClaim.BurnSubmission memory submission = constructSubmission(instanceId, burnTokens, variation, variationLimit, erc20, price, fundsRecipient, expiration, nonce);

        // Test redeem
        vm.startPrank(other1);
        creatorCore721.approve(address(example), 1);
        vm.expectRevert(abi.encodeWithSelector(IPhysicalClaim.InvalidToken.selector, address(creatorCore721), 1));
        example.burnRedeem{value: burnFee}(submission);
        vm.stopPrank();
    }

    function testPhysicalClaim721() public {
        vm.startPrank(owner);
        creatorCore721.mintBase(other1, "");
        vm.stopPrank();

        IPhysicalClaim.BurnToken[] memory burnTokens = new IPhysicalClaim.BurnToken[](1);
        burnTokens[0] = IPhysicalClaim.BurnToken({
            contractAddress: address(creatorCore721),
            tokenId: 1,
            tokenSpec: IPhysicalClaim.TokenSpec.ERC721,
            burnSpec: IPhysicalClaim.BurnSpec.MANIFOLD,
            amount: 1
        });

        uint256 instanceId = 100;
        uint8 variation = 2;
        uint64 variationLimit = 0;
        address erc20 = address(0);
        uint256 price = 0;
        address payable fundsRecipient = payable(address(0));
        uint160 expiration = uint160(block.timestamp + 1000);
        uint256 burnFee = PhysicalClaim(example).BURN_FEE();
        bytes32 nonce = bytes32(bytes4(0xdeadbeef));

        IPhysicalClaim.BurnSubmission memory submission = constructSubmission(instanceId, burnTokens, variation, variationLimit, erc20, price, fundsRecipient, expiration, nonce);

        // Test redeem
        vm.startPrank(other1);
        creatorCore721.approve(address(example), 1);
        example.burnRedeem{value: burnFee}(submission);
        vm.stopPrank();

        // Check token burned
        vm.expectRevert("ERC721: invalid token ID");
        creatorCore721.ownerOf(1);
    }

    function testPhysicalClaim721BurnSpecNone() public {
        vm.startPrank(owner);
        creatorCore721.mintBase(other1, "");
        vm.stopPrank();

        IPhysicalClaim.BurnToken[] memory burnTokens = new IPhysicalClaim.BurnToken[](1);
        burnTokens[0] = IPhysicalClaim.BurnToken({
            contractAddress: address(creatorCore721),
            tokenId: 1,
            tokenSpec: IPhysicalClaim.TokenSpec.ERC721,
            burnSpec: IPhysicalClaim.BurnSpec.NONE,
            amount: 1
        });

        uint256 instanceId = 100;
        uint8 variation = 2;
        uint64 variationLimit = 0;
        address erc20 = address(0);
        uint256 price = 0;
        address payable fundsRecipient = payable(address(0));
        uint160 expiration = uint160(block.timestamp + 1000);
        uint256 burnFee = PhysicalClaim(example).BURN_FEE();
        bytes32 nonce = bytes32(bytes4(0xdeadbeef));

        IPhysicalClaim.BurnSubmission memory submission = constructSubmission(instanceId, burnTokens, variation, variationLimit, erc20, price, fundsRecipient, expiration, nonce);

        // Test redeem
        vm.startPrank(other1);
        creatorCore721.approve(address(example), 1);
        example.burnRedeem{value: burnFee}(submission);
        vm.stopPrank();

        // Check token burned
        assertEq(creatorCore721.ownerOf(1), address(0xdead));
    }

    function testPhysicalClaim1155() public {
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
            amount: 2
        });

        uint256 instanceId = 100;
        uint8 variation = 2;
        uint64 variationLimit = 0;
        address erc20 = address(0);
        uint256 price = 0;
        address payable fundsRecipient = payable(address(0));
        uint160 expiration = uint160(block.timestamp + 1000);
        uint256 burnFee = PhysicalClaim(example).BURN_FEE();
        bytes32 nonce = bytes32(bytes4(0xdeadbeef));

        IPhysicalClaim.BurnSubmission memory submission = constructSubmission(instanceId, burnTokens, variation, variationLimit, erc20, price, fundsRecipient, expiration, nonce);

        // Test redeem
        vm.startPrank(other1);
        creatorCore1155.setApprovalForAll(address(example), true);
        example.burnRedeem{value: burnFee}(submission);
        vm.stopPrank();

        // Check token burned
        assertEq(creatorCore1155.balanceOf(other1, 1), 8);
    }

    function testPhysicalClaim1155BurnSpecNone() public {
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
            burnSpec: IPhysicalClaim.BurnSpec.NONE,
            amount: 2
        });

        uint256 instanceId = 100;
        uint8 variation = 2;
        uint64 variationLimit = 0;
        address erc20 = address(0);
        uint256 price = 0;
        address payable fundsRecipient = payable(address(0));
        uint160 expiration = uint160(block.timestamp + 1000);
        uint256 burnFee = PhysicalClaim(example).BURN_FEE();
        bytes32 nonce = bytes32(bytes4(0xdeadbeef));

        IPhysicalClaim.BurnSubmission memory submission = constructSubmission(instanceId, burnTokens, variation, variationLimit, erc20, price, fundsRecipient, expiration, nonce);

        // Test redeem
        vm.startPrank(other1);
        creatorCore1155.setApprovalForAll(address(example), true);
        example.burnRedeem{value: burnFee}(submission);
        vm.stopPrank();

        // Check token burned
        assertEq(creatorCore1155.balanceOf(other1, 1), 8);
        assertEq(creatorCore1155.balanceOf(address(0xdead), 1), 2);
    }

    function testPhysicalClaimWithPrice() public {
        vm.startPrank(owner);
        creatorCore721.mintBase(other1, "");
        vm.stopPrank();

        IPhysicalClaim.BurnToken[] memory burnTokens = new IPhysicalClaim.BurnToken[](1);
        burnTokens[0] = IPhysicalClaim.BurnToken({
            contractAddress: address(creatorCore721),
            tokenId: 1,
            tokenSpec: IPhysicalClaim.TokenSpec.ERC721,
            burnSpec: IPhysicalClaim.BurnSpec.MANIFOLD,
            amount: 1
        });

        uint256 instanceId = 100;
        uint8 variation = 2;
        uint64 variationLimit = 0;
        address erc20 = address(0);
        uint256 price = 1 ether;
        address payable fundsRecipient = payable(seller);
        uint160 expiration = uint160(block.timestamp + 1000);
        uint256 burnFee = PhysicalClaim(example).BURN_FEE();
        bytes32 nonce = bytes32(bytes4(0xdeadbeef));

        IPhysicalClaim.BurnSubmission memory submission = constructSubmission(instanceId, burnTokens, variation, variationLimit, erc20, price, fundsRecipient, expiration, nonce);

        // Test redeem
        vm.startPrank(other1);
        creatorCore721.approve(address(example), 1);
        example.burnRedeem{value: burnFee+price}(submission);
        vm.stopPrank();

        // Check token burned
        vm.expectRevert("ERC721: invalid token ID");
        creatorCore721.ownerOf(1);

        // Check seller got price
        assertEq(address(seller).balance, 1 ether);
    }

    function testPhysicalClaimWithPriceManifoldMember() public {
        vm.startPrank(owner);
        example.setMembershipAddress(address(manifoldMembership));
        manifoldMembership.setMember(other1, true);
        creatorCore721.mintBase(other1, "");
        vm.stopPrank();

        IPhysicalClaim.BurnToken[] memory burnTokens = new IPhysicalClaim.BurnToken[](1);
        burnTokens[0] = IPhysicalClaim.BurnToken({
            contractAddress: address(creatorCore721),
            tokenId: 1,
            tokenSpec: IPhysicalClaim.TokenSpec.ERC721,
            burnSpec: IPhysicalClaim.BurnSpec.MANIFOLD,
            amount: 1
        });

        uint256 instanceId = 100;
        uint8 variation = 2;
        uint64 variationLimit = 0;
        address erc20 = address(0);
        uint256 price = 1 ether;
        address payable fundsRecipient = payable(seller);
        uint160 expiration = uint160(block.timestamp + 1000);
        bytes32 nonce = bytes32(bytes4(0xdeadbeef));

        IPhysicalClaim.BurnSubmission memory submission = constructSubmission(instanceId, burnTokens, variation, variationLimit, erc20, price, fundsRecipient, expiration, nonce);

        // Test redeem
        vm.startPrank(other1);
        creatorCore721.approve(address(example), 1);
        example.burnRedeem{value: price}(submission);
        vm.stopPrank();

        // Check token burned
        vm.expectRevert("ERC721: invalid token ID");
        creatorCore721.ownerOf(1);

        // Check seller got price
        assertEq(address(seller).balance, 1 ether);
    }

    function testPhysicalClaimWithERC20PriceInvalid() public {
        vm.startPrank(owner);
        creatorCore721.mintBase(other1, "");
        mockERC20.fakeMint(other2, 200);
        vm.stopPrank();

        IPhysicalClaim.BurnToken[] memory burnTokens = new IPhysicalClaim.BurnToken[](1);
        burnTokens[0] = IPhysicalClaim.BurnToken({
            contractAddress: address(creatorCore721),
            tokenId: 1,
            tokenSpec: IPhysicalClaim.TokenSpec.ERC721,
            burnSpec: IPhysicalClaim.BurnSpec.MANIFOLD,
            amount: 1
        });

        uint256 instanceId = 100;
        uint8 variation = 2;
        uint64 variationLimit = 0;
        address erc20 = address(mockERC20);
        uint256 price = 15;
        address payable fundsRecipient = payable(seller);
        uint160 expiration = uint160(block.timestamp + 1000);
        uint256 burnFee = PhysicalClaim(example).BURN_FEE();
        bytes32 nonce = bytes32(bytes4(0xdeadbeef));

        IPhysicalClaim.BurnSubmission memory submission = constructSubmission(instanceId, burnTokens, variation, variationLimit, erc20, price, fundsRecipient, expiration, nonce);

        // Approve spend from other2
        vm.startPrank(other2);
        mockERC20.approve(address(example), 15);
        vm.stopPrank();

        // Test redeem (should fail, cannot steal someone else's balance)
        vm.startPrank(other1);
        creatorCore721.approve(address(example), 1);
        vm.expectRevert("ERC20: insufficient allowance");
        example.burnRedeem{value: burnFee}(submission);
        mockERC20.approve(address(example), 15);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        example.burnRedeem{value: burnFee}(submission);
        vm.stopPrank();
    }

    function testPhysicalClaimWithERC20Price() public {
        vm.startPrank(owner);
        creatorCore721.mintBase(other1, "");
        mockERC20.fakeMint(other1, 200);
        vm.stopPrank();

        IPhysicalClaim.BurnToken[] memory burnTokens = new IPhysicalClaim.BurnToken[](1);
        burnTokens[0] = IPhysicalClaim.BurnToken({
            contractAddress: address(creatorCore721),
            tokenId: 1,
            tokenSpec: IPhysicalClaim.TokenSpec.ERC721,
            burnSpec: IPhysicalClaim.BurnSpec.MANIFOLD,
            amount: 1
        });

        uint256 instanceId = 100;
        uint8 variation = 2;
        uint64 variationLimit = 0;
        address erc20 = address(mockERC20);
        uint256 price = 15;
        address payable fundsRecipient = payable(seller);
        uint160 expiration = uint160(block.timestamp + 1000);
        uint256 burnFee = PhysicalClaim(example).BURN_FEE();
        bytes32 nonce = bytes32(bytes4(0xdeadbeef));

        IPhysicalClaim.BurnSubmission memory submission = constructSubmission(instanceId, burnTokens, variation, variationLimit, erc20, price, fundsRecipient, expiration, nonce);

        // Test redeem
        vm.startPrank(other1);
        creatorCore721.approve(address(example), 1);
        vm.expectRevert("ERC20: insufficient allowance");
        example.burnRedeem{value: burnFee}(submission);
        mockERC20.approve(address(example), 15);
        example.burnRedeem{value: burnFee}(submission);
        vm.stopPrank();

        // Check token burned
        vm.expectRevert("ERC721: invalid token ID");
        creatorCore721.ownerOf(1);

        // Check seller got price
        assertEq(mockERC20.balanceOf(address(seller)), 15);
        assertEq(mockERC20.balanceOf(address(other1)), 185);
    }

    function testPhysicalClaimMultiBurn() public {
        vm.startPrank(owner);
        creatorCore721.mintBase(other1, "");
        address[] memory recipients = new address[](1);
        recipients[0] = other1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10;
        string[] memory uris = new string[](1);
        creatorCore1155.mintBaseNew(recipients, amounts, uris);
        vm.stopPrank();

        IPhysicalClaim.BurnToken[] memory burnTokens = new IPhysicalClaim.BurnToken[](2);
        burnTokens[0] = IPhysicalClaim.BurnToken({
            contractAddress: address(creatorCore721),
            tokenId: 1,
            tokenSpec: IPhysicalClaim.TokenSpec.ERC721,
            burnSpec: IPhysicalClaim.BurnSpec.MANIFOLD,
            amount: 1
        });
        burnTokens[1] = IPhysicalClaim.BurnToken({
            contractAddress: address(creatorCore1155),
            tokenId: 1,
            tokenSpec: IPhysicalClaim.TokenSpec.ERC1155,
            burnSpec: IPhysicalClaim.BurnSpec.MANIFOLD,
            amount: 2
        });

        uint256 instanceId = 100;
        uint8 variation = 2;
        uint64 variationLimit = 0;
        address erc20 = address(0);
        uint256 price = 0;
        address payable fundsRecipient = payable(address(0));
        uint160 expiration = uint160(block.timestamp + 1000);
        uint256 burnFee = PhysicalClaim(example).MULTI_BURN_FEE();
        bytes32 nonce = bytes32(bytes4(0xdeadbeef));

        IPhysicalClaim.BurnSubmission memory submission = constructSubmission(instanceId, burnTokens, variation, variationLimit, erc20, price, fundsRecipient, expiration, nonce);

        // Test redeem
        vm.startPrank(other1);
        creatorCore721.approve(address(example), 1);
        creatorCore1155.setApprovalForAll(address(example), true);
        example.burnRedeem{value: burnFee}(submission);
        vm.stopPrank();

        // Check token burned
        vm.expectRevert("ERC721: invalid token ID");
        creatorCore721.ownerOf(1);
        assertEq(creatorCore1155.balanceOf(other1, 1), 8);
    }

    function testPhysicalMultiSubmission() public {
        vm.startPrank(owner);
        creatorCore721.mintBase(other1, "");
        creatorCore721.mintBase(other1, "");
        vm.stopPrank();

        IPhysicalClaim.BurnToken[] memory burnTokens1 = new IPhysicalClaim.BurnToken[](1);
        burnTokens1[0] = IPhysicalClaim.BurnToken({
            contractAddress: address(creatorCore721),
            tokenId: 1,
            tokenSpec: IPhysicalClaim.TokenSpec.ERC721,
            burnSpec: IPhysicalClaim.BurnSpec.MANIFOLD,
            amount: 1
        });
        IPhysicalClaim.BurnToken[] memory burnTokens2 = new IPhysicalClaim.BurnToken[](1);
        burnTokens2[0] = IPhysicalClaim.BurnToken({
            contractAddress: address(creatorCore721),
            tokenId: 2,
            tokenSpec: IPhysicalClaim.TokenSpec.ERC721,
            burnSpec: IPhysicalClaim.BurnSpec.MANIFOLD,
            amount: 1
        });

        uint256 instanceId = 100;
        uint8 variation = 2;
        uint64 variationLimit = 0;
        address erc20 = address(0);
        uint256 price = 0;
        address payable fundsRecipient = payable(address(0));
        uint160 expiration = uint160(block.timestamp + 1000);
        uint256 burnFee = PhysicalClaim(example).BURN_FEE() * 2;
        bytes32 nonce = bytes32(bytes4(0xdeadbeef));

        IPhysicalClaim.BurnSubmission[] memory submissions = new IPhysicalClaim.BurnSubmission[](2);
        submissions[0] = constructSubmission(instanceId, burnTokens1, variation, variationLimit, erc20, price, fundsRecipient, expiration, nonce);
        nonce = bytes32(bytes4(0xdeadbee2));
        submissions[1] = constructSubmission(instanceId, burnTokens2, variation, variationLimit, erc20, price, fundsRecipient, expiration, nonce);


        // Test redeem
        vm.startPrank(other1);
        creatorCore721.approve(address(example), 1);
        creatorCore721.approve(address(example), 2);
        example.burnRedeem{value: burnFee}(submissions);
        vm.stopPrank();

        // Check token burned
        vm.expectRevert("ERC721: invalid token ID");
        creatorCore721.ownerOf(1);
        vm.expectRevert("ERC721: invalid token ID");
        creatorCore721.ownerOf(2);
        assertEq(address(example).balance, burnFee);
    }

    function testPhysicalMultiSubmissionSoldOut() public {
        vm.startPrank(owner);
        creatorCore721.mintBase(other1, "");
        creatorCore721.mintBase(other1, "");
        vm.stopPrank();

        IPhysicalClaim.BurnToken[] memory burnTokens1 = new IPhysicalClaim.BurnToken[](1);
        burnTokens1[0] = IPhysicalClaim.BurnToken({
            contractAddress: address(creatorCore721),
            tokenId: 1,
            tokenSpec: IPhysicalClaim.TokenSpec.ERC721,
            burnSpec: IPhysicalClaim.BurnSpec.MANIFOLD,
            amount: 1
        });
        IPhysicalClaim.BurnToken[] memory burnTokens2 = new IPhysicalClaim.BurnToken[](1);
        burnTokens2[0] = IPhysicalClaim.BurnToken({
            contractAddress: address(creatorCore721),
            tokenId: 2,
            tokenSpec: IPhysicalClaim.TokenSpec.ERC721,
            burnSpec: IPhysicalClaim.BurnSpec.MANIFOLD,
            amount: 1
        });

        uint256 instanceId = 100;
        uint8 variation = 2;
        uint64 variationLimit = 1;
        address erc20 = address(0);
        uint256 price = 0;
        address payable fundsRecipient = payable(address(0));
        uint160 expiration = uint160(block.timestamp + 1000);
        uint256 burnFee = PhysicalClaim(example).BURN_FEE() * 2;
        bytes32 nonce = bytes32(bytes4(0xdeadbeef));

        IPhysicalClaim.BurnSubmission[] memory submissions = new IPhysicalClaim.BurnSubmission[](2);
        submissions[0] = constructSubmission(instanceId, burnTokens1, variation, variationLimit, erc20, price, fundsRecipient, expiration, nonce);
        nonce = bytes32(bytes4(0xdeadbee2));
        submissions[1] = constructSubmission(instanceId, burnTokens2, variation, variationLimit, erc20, price, fundsRecipient, expiration, nonce);


        // Test redeem
        vm.startPrank(other1);
        creatorCore721.approve(address(example), 1);
        creatorCore721.approve(address(example), 2);
        example.burnRedeem{value: burnFee}(submissions);
        vm.stopPrank();

        // Check token burned
        vm.expectRevert("ERC721: invalid token ID");
        creatorCore721.ownerOf(1);
        // Token 2 not burned because we were sold out and it didn't process
        assertEq(creatorCore721.ownerOf(2), other1);
        assertEq(address(example).balance, burnFee/2);
    }

    function testPhysicalClaimSoldOut() public {
        IPhysicalClaim.BurnToken[] memory burnTokens = new IPhysicalClaim.BurnToken[](0);
        uint256 instanceId = 100;
        uint8 variation = 1;
        uint64 variationLimit = 2;
        address erc20 = address(0);
        uint256 price = 0;
        address payable fundsRecipient = payable(address(0));
        uint160 expiration = uint160(block.timestamp + 1000);
        uint256 burnFee = PhysicalClaim(example).BURN_FEE();
        bytes32 nonce = bytes32(bytes4(0xdeadbeef));

        IPhysicalClaim.BurnSubmission memory submission = constructSubmission(instanceId, burnTokens, variation, variationLimit, erc20, price, fundsRecipient, expiration, nonce);

        // Test redeem (third time should fail because sold out)
        vm.startPrank(other1);
        example.burnRedeem{value: burnFee}(submission);
        vm.stopPrank();
        nonce = bytes32(bytes4(0xdeadbee1));
        submission = constructSubmission(instanceId, burnTokens, variation, variationLimit, erc20, price, fundsRecipient, expiration, nonce);
        vm.startPrank(other1);
        example.burnRedeem{value: burnFee}(submission);
        vm.stopPrank();
        nonce = bytes32(bytes4(0xdeadbee2));
        submission = constructSubmission(instanceId, burnTokens, variation, variationLimit, erc20, price, fundsRecipient, expiration, nonce);
        vm.startPrank(other1);
        vm.expectRevert(IPhysicalClaim.SoldOut.selector);
        example.burnRedeem{value: burnFee}(submission);
        vm.stopPrank();
    }

    function constructSubmission(uint256 instanceId, IPhysicalClaim.BurnToken[] memory burnTokens, uint8 variation, uint64 variationLimit, address erc20, uint256 price, address payable fundsRecipient, uint160 expiration, bytes32 nonce) private view returns (IPhysicalClaim.BurnSubmission memory submission) {
        bytes memory messageData = abi.encode(instanceId, burnTokens, variation, variationLimit, erc20, price, fundsRecipient, expiration, nonce);
        bytes32 message = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageData));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, message);
        bytes memory signature = abi.encodePacked(r, s, v);

        submission.signature = signature;
        submission.message = message;
        submission.instanceId = instanceId;
        submission.burnTokens = burnTokens;
        submission.variation = variation;
        submission.variationLimit = variationLimit;
        submission.erc20 = erc20;
        submission.price = price;
        submission.fundsRecipient = fundsRecipient;
        submission.expiration = expiration;
        submission.nonce = nonce;
    }

  }
