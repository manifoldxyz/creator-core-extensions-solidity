// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./CrossChainBurnBase.t.sol";
import "../../contracts/crossChainBurn/CrossChainBurn.sol";
import "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC721Creator.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC1155Creator.sol";
import "../mocks/Mock.sol";

contract CrossChainBurnTest is CrossChainBurnBase {
  CrossChainBurn public example;
  ERC721Creator public creatorCore721;
  ERC1155Creator public creatorCore1155;

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

    signingAddress = vm.addr(privateKey);
    example = new CrossChainBurn(owner, signingAddress);

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

    // Test updateSigner
    vm.startPrank(owner);
    example.updateSigner(seller);
    vm.stopPrank();
  }

  function testSupportsInterface() public {
    vm.startPrank(owner);

    bytes4 interfaceId = type(ICrossChainBurn).interfaceId;
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
    ICrossChainBurn.BurnToken[] memory burnTokens = new ICrossChainBurn.BurnToken[](1);
    burnTokens[0] = ICrossChainBurn.BurnToken({
      contractAddress: address(creatorCore721),
      tokenId: 1,
      tokenSpec: ICrossChainBurn.TokenSpec.ERC721,
      burnSpec: ICrossChainBurn.BurnSpec.MANIFOLD,
      amount: 1
    });

    uint256 instanceId = 100;
    uint64 redeemAmount = 1;
    uint64 totalLimit = 0;
    uint160 expiration = uint160(block.timestamp + 1000);

    ICrossChainBurn.BurnSubmission memory submission = constructSubmission(
      instanceId,
      burnTokens,
      redeemAmount,
      totalLimit,
      expiration
    );

    // Test redeem failure because token does not exist
    vm.startPrank(other1);
    vm.expectRevert("ERC721: invalid token ID");
    example.burnRedeem(submission);
    vm.stopPrank();

    vm.startPrank(owner);
    creatorCore721.mintBase(other1, "");
    vm.stopPrank();

    // Test redeem failure because token not approved
    vm.startPrank(other1);
    vm.expectRevert("Caller is not owner or approved");
    example.burnRedeem(submission);
    vm.stopPrank();

    // Test redeem failure because token is notowned by sender
    vm.startPrank(other1);
    creatorCore721.approve(address(example), 1);
    vm.stopPrank();
    vm.startPrank(other2);
    vm.expectRevert(ICrossChainBurn.TransferFailure.selector);
    example.burnRedeem(submission);
    vm.stopPrank();
  }

  function testInvalidSignature() public {
    vm.startPrank(owner);
    creatorCore721.mintBase(other1, "");
    vm.stopPrank();

    ICrossChainBurn.BurnToken[] memory burnTokens = new ICrossChainBurn.BurnToken[](1);
    burnTokens[0] = ICrossChainBurn.BurnToken({
      contractAddress: address(creatorCore721),
      tokenId: 1,
      tokenSpec: ICrossChainBurn.TokenSpec.ERC721,
      burnSpec: ICrossChainBurn.BurnSpec.MANIFOLD,
      amount: 1
    });

    uint256 instanceId = 100;
    uint64 redeemAmount = 1;
    uint64 totalLimit = 0;
    uint160 expiration = uint160(block.timestamp + 1000);

    ICrossChainBurn.BurnSubmission memory submission = constructSubmission(
      instanceId,
      burnTokens,
      redeemAmount,
      totalLimit,
      expiration
    );

    // Test redeem because we have an invalid signature
    // Change configured signer
    vm.startPrank(owner);
    example.updateSigner(other2);
    vm.stopPrank();
    vm.startPrank(other1);
    creatorCore721.approve(address(example), 1);
    vm.expectRevert(ICrossChainBurn.InvalidSignature.selector);
    example.burnRedeem(submission);
    vm.stopPrank();
  }

  function testInvalidMessage() public {
    vm.startPrank(owner);
    creatorCore721.mintBase(other1, "");
    vm.stopPrank();

    ICrossChainBurn.BurnToken[] memory burnTokens = new ICrossChainBurn.BurnToken[](1);
    burnTokens[0] = ICrossChainBurn.BurnToken({
      contractAddress: address(creatorCore721),
      tokenId: 1,
      tokenSpec: ICrossChainBurn.TokenSpec.ERC721,
      burnSpec: ICrossChainBurn.BurnSpec.MANIFOLD,
      amount: 1
    });

    uint256 instanceId = 100;
    uint64 redeemAmount = 1;
    uint64 totalLimit = 0;
    uint160 expiration = uint160(block.timestamp + 1000);

    ICrossChainBurn.BurnSubmission memory submission = constructSubmission(
      instanceId,
      burnTokens,
      redeemAmount,
      totalLimit,
      expiration
    );

    // Test redeem because we change the data
    submission.message = bytes32(0);
    vm.startPrank(other1);
    creatorCore721.approve(address(example), 1);
    vm.expectRevert(ICrossChainBurn.InvalidSignature.selector);
    example.burnRedeem(submission);
    vm.stopPrank();
  }

  function testInvalidDueToDataChange() public {
    vm.startPrank(owner);
    creatorCore721.mintBase(other1, "");
    vm.stopPrank();

    ICrossChainBurn.BurnToken[] memory burnTokens = new ICrossChainBurn.BurnToken[](1);
    burnTokens[0] = ICrossChainBurn.BurnToken({
      contractAddress: address(creatorCore721),
      tokenId: 1,
      tokenSpec: ICrossChainBurn.TokenSpec.ERC721,
      burnSpec: ICrossChainBurn.BurnSpec.MANIFOLD,
      amount: 1
    });

    uint256 instanceId = 100;
    uint64 redeemAmount = 1;
    uint64 totalLimit = 0;
    uint160 expiration = uint160(block.timestamp + 1000);

    ICrossChainBurn.BurnSubmission memory submission = constructSubmission(
      instanceId,
      burnTokens,
      redeemAmount,
      totalLimit,
      expiration
    );

    // Test redeem because we change the data
    submission.totalLimit = 10;
    vm.startPrank(other1);
    creatorCore721.approve(address(example), 1);
    vm.expectRevert(ICrossChainBurn.InvalidSignature.selector);
    example.burnRedeem(submission);
    vm.stopPrank();
  }

  function testInvalidDueToExpired() public {
    vm.startPrank(owner);
    creatorCore721.mintBase(other1, "");
    vm.stopPrank();

    ICrossChainBurn.BurnToken[] memory burnTokens = new ICrossChainBurn.BurnToken[](1);
    burnTokens[0] = ICrossChainBurn.BurnToken({
      contractAddress: address(creatorCore721),
      tokenId: 1,
      tokenSpec: ICrossChainBurn.TokenSpec.ERC721,
      burnSpec: ICrossChainBurn.BurnSpec.MANIFOLD,
      amount: 1
    });

    uint256 instanceId = 100;
    uint64 redeemAmount = 1;
    uint64 totalLimit = 0;
    uint160 expiration = uint160(block.timestamp - 1);

    ICrossChainBurn.BurnSubmission memory submission = constructSubmission(
      instanceId,
      burnTokens,
      redeemAmount,
      totalLimit,
      expiration
    );

    // Test redeem because it is expired
    vm.startPrank(other1);
    creatorCore721.approve(address(example), 1);
    vm.expectRevert(ICrossChainBurn.ExpiredSignature.selector);
    example.burnRedeem(submission);
    vm.stopPrank();
  }

  function testInvalidBurnSpec721() public {
    ICrossChainBurn.BurnToken[] memory burnTokens = new ICrossChainBurn.BurnToken[](1);
    burnTokens[0] = ICrossChainBurn.BurnToken({
      contractAddress: address(creatorCore721),
      tokenId: 1,
      tokenSpec: ICrossChainBurn.TokenSpec.ERC721,
      burnSpec: ICrossChainBurn.BurnSpec.INVALID,
      amount: 1
    });

    uint256 instanceId = 100;
    uint64 redeemAmount = 1;
    uint64 totalLimit = 0;
    uint160 expiration = uint160(block.timestamp + 1000);

    ICrossChainBurn.BurnSubmission memory submission = constructSubmission(
      instanceId,
      burnTokens,
      redeemAmount,
      totalLimit,
      expiration
    );

    // Test redeem
    vm.startPrank(other1);
    vm.expectRevert(ICrossChainBurn.InvalidBurnSpec.selector);
    example.burnRedeem(submission);
    vm.stopPrank();
  }

  function testInvalidBurnSpec1155() public {
    ICrossChainBurn.BurnToken[] memory burnTokens = new ICrossChainBurn.BurnToken[](1);
    burnTokens[0] = ICrossChainBurn.BurnToken({
      contractAddress: address(creatorCore1155),
      tokenId: 1,
      tokenSpec: ICrossChainBurn.TokenSpec.ERC1155,
      burnSpec: ICrossChainBurn.BurnSpec.INVALID,
      amount: 1
    });

    uint256 instanceId = 100;
    uint64 redeemAmount = 1;
    uint64 totalLimit = 0;
    uint160 expiration = uint160(block.timestamp + 1000);

    ICrossChainBurn.BurnSubmission memory submission = constructSubmission(
      instanceId,
      burnTokens,
      redeemAmount,
      totalLimit,
      expiration
    );

    // Test redeem
    vm.startPrank(other1);
    vm.expectRevert(ICrossChainBurn.InvalidBurnSpec.selector);
    example.burnRedeem(submission);
    vm.stopPrank();
  }

  function testInvalidTokeSpec() public {
    vm.startPrank(owner);
    creatorCore721.mintBase(other1, "");
    vm.stopPrank();

    ICrossChainBurn.BurnToken[] memory burnTokens = new ICrossChainBurn.BurnToken[](1);
    burnTokens[0] = ICrossChainBurn.BurnToken({
      contractAddress: address(creatorCore721),
      tokenId: 1,
      tokenSpec: ICrossChainBurn.TokenSpec.INVALID,
      burnSpec: ICrossChainBurn.BurnSpec.NONE,
      amount: 1
    });

    uint256 instanceId = 100;
    uint64 redeemAmount = 1;
    uint64 totalLimit = 0;
    uint160 expiration = uint160(block.timestamp + 1000);

    ICrossChainBurn.BurnSubmission memory submission = constructSubmission(
      instanceId,
      burnTokens,
      redeemAmount,
      totalLimit,
      expiration
    );

    // Test redeem
    vm.startPrank(other1);
    creatorCore721.approve(address(example), 1);
    vm.expectRevert(ICrossChainBurn.InvalidTokenSpec.selector);
    example.burnRedeem(submission);
    vm.stopPrank();
  }

  function testNoBurnFromNonOwnerInvalid() public {
    vm.startPrank(owner);
    creatorCore721.mintBase(other1, "");
    vm.stopPrank();

    ICrossChainBurn.BurnToken[] memory burnTokens = new ICrossChainBurn.BurnToken[](1);
    burnTokens[0] = ICrossChainBurn.BurnToken({
      contractAddress: address(creatorCore721),
      tokenId: 1,
      tokenSpec: ICrossChainBurn.TokenSpec.ERC721_NO_BURN,
      burnSpec: ICrossChainBurn.BurnSpec.NONE,
      amount: 1
    });

    uint256 instanceId = 100;
    uint64 redeemAmount = 1;
    uint64 totalLimit = 0;
    uint160 expiration = uint160(block.timestamp + 1000);

    ICrossChainBurn.BurnSubmission memory submission = constructSubmission(
      instanceId,
      burnTokens,
      redeemAmount,
      totalLimit,
      expiration
    );

    // Test redeem from non-owner should fail
    vm.startPrank(other2);
    vm.expectRevert(ICrossChainBurn.TransferFailure.selector);
    example.burnRedeem(submission);
    vm.stopPrank();
  }

  function testNoBurnMultiUseInvalid() public {
    vm.startPrank(owner);
    creatorCore721.mintBase(other1, "");
    vm.stopPrank();

    ICrossChainBurn.BurnToken[] memory burnTokens = new ICrossChainBurn.BurnToken[](1);
    burnTokens[0] = ICrossChainBurn.BurnToken({
      contractAddress: address(creatorCore721),
      tokenId: 1,
      tokenSpec: ICrossChainBurn.TokenSpec.ERC721_NO_BURN,
      burnSpec: ICrossChainBurn.BurnSpec.NONE,
      amount: 1
    });

    uint256 instanceId = 100;
    uint64 redeemAmount = 1;
    uint64 totalLimit = 0;
    uint160 expiration = uint160(block.timestamp + 1000);

    ICrossChainBurn.BurnSubmission memory submission = constructSubmission(
      instanceId,
      burnTokens,
      redeemAmount,
      totalLimit,
      expiration
    );

    // Test redeem
    vm.startPrank(other1);
    example.burnRedeem(submission);
    vm.stopPrank();

    // Check token not burned
    assertEq(creatorCore721.ownerOf(1), other1);

    // Try redemption again, not allowed because token already used
    submission = constructSubmission(instanceId, burnTokens, redeemAmount, totalLimit, expiration);
    vm.startPrank(other1);
    vm.expectRevert(abi.encodeWithSelector(ICrossChainBurn.InvalidToken.selector, address(creatorCore721), 1));
    example.burnRedeem(submission);
    vm.stopPrank();
  }

  function testInvalidBurnAmount721() public {
    vm.startPrank(owner);
    creatorCore721.mintBase(other1, "");
    vm.stopPrank();

    ICrossChainBurn.BurnToken[] memory burnTokens = new ICrossChainBurn.BurnToken[](1);
    burnTokens[0] = ICrossChainBurn.BurnToken({
      contractAddress: address(creatorCore721),
      tokenId: 1,
      tokenSpec: ICrossChainBurn.TokenSpec.ERC721,
      burnSpec: ICrossChainBurn.BurnSpec.MANIFOLD,
      amount: 2
    });

    uint256 instanceId = 100;
    uint64 redeemAmount = 1;
    uint64 totalLimit = 0;
    uint160 expiration = uint160(block.timestamp + 1000);

    ICrossChainBurn.BurnSubmission memory submission = constructSubmission(
      instanceId,
      burnTokens,
      redeemAmount,
      totalLimit,
      expiration
    );

    // Test redeem
    vm.startPrank(other1);
    creatorCore721.approve(address(example), 1);
    vm.expectRevert(abi.encodeWithSelector(ICrossChainBurn.InvalidToken.selector, address(creatorCore721), 1));
    example.burnRedeem(submission);
    vm.stopPrank();
  }

  function testCrossChainBurn721() public {
    vm.startPrank(owner);
    creatorCore721.mintBase(other1, "");
    creatorCore721.mintBase(other1, "");
    vm.stopPrank();

    ICrossChainBurn.BurnToken[] memory burnTokens = new ICrossChainBurn.BurnToken[](2);
    burnTokens[0] = ICrossChainBurn.BurnToken({
      contractAddress: address(creatorCore721),
      tokenId: 1,
      tokenSpec: ICrossChainBurn.TokenSpec.ERC721,
      burnSpec: ICrossChainBurn.BurnSpec.MANIFOLD,
      amount: 1
    });
    burnTokens[1] = ICrossChainBurn.BurnToken({
      contractAddress: address(creatorCore721),
      tokenId: 2,
      tokenSpec: ICrossChainBurn.TokenSpec.ERC721,
      burnSpec: ICrossChainBurn.BurnSpec.MANIFOLD,
      amount: 1
    });

    uint256 instanceId = 100;
    uint64 redeemAmount = 2;
    uint64 totalLimit = 5;
    uint160 expiration = uint160(block.timestamp + 1000);

    ICrossChainBurn.BurnSubmission memory submission = constructSubmission(
      instanceId,
      burnTokens,
      redeemAmount,
      totalLimit,
      expiration
    );

    // Test redeem
    vm.startPrank(other1);
    creatorCore721.approve(address(example), 1);
    creatorCore721.approve(address(example), 2);
    example.burnRedeem(submission);
    vm.stopPrank();

    // Check token burned
    vm.expectRevert("ERC721: invalid token ID");
    creatorCore721.ownerOf(1);
    vm.expectRevert("ERC721: invalid token ID");
    creatorCore721.ownerOf(2);
  }

  function testCrossChainBurn721BurnSpecNone() public {
    vm.startPrank(owner);
    creatorCore721.mintBase(other1, "");
    vm.stopPrank();

    ICrossChainBurn.BurnToken[] memory burnTokens = new ICrossChainBurn.BurnToken[](1);
    burnTokens[0] = ICrossChainBurn.BurnToken({
      contractAddress: address(creatorCore721),
      tokenId: 1,
      tokenSpec: ICrossChainBurn.TokenSpec.ERC721,
      burnSpec: ICrossChainBurn.BurnSpec.NONE,
      amount: 1
    });

    uint256 instanceId = 100;
    uint64 redeemAmount = 1;
    uint64 totalLimit = 0;
    uint160 expiration = uint160(block.timestamp + 1000);
    ICrossChainBurn.BurnSubmission memory submission = constructSubmission(
      instanceId,
      burnTokens,
      redeemAmount,
      totalLimit,
      expiration
    );

    // Test redeem
    vm.startPrank(other1);
    creatorCore721.approve(address(example), 1);
    example.burnRedeem(submission);
    vm.stopPrank();

    // Check token burned
    assertEq(creatorCore721.ownerOf(1), address(0xdead));
  }

  function testCrossChainBurn1155() public {
    vm.startPrank(owner);
    address[] memory recipients = new address[](1);
    recipients[0] = other1;
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = 10;
    string[] memory uris = new string[](1);
    creatorCore1155.mintBaseNew(recipients, amounts, uris);
    vm.stopPrank();

    ICrossChainBurn.BurnToken[] memory burnTokens = new ICrossChainBurn.BurnToken[](1);
    burnTokens[0] = ICrossChainBurn.BurnToken({
      contractAddress: address(creatorCore1155),
      tokenId: 1,
      tokenSpec: ICrossChainBurn.TokenSpec.ERC1155,
      burnSpec: ICrossChainBurn.BurnSpec.MANIFOLD,
      amount: 2
    });

    uint256 instanceId = 100;
    uint64 redeemAmount = 2;
    uint64 totalLimit = 0;
    uint160 expiration = uint160(block.timestamp + 1000);

    ICrossChainBurn.BurnSubmission memory submission = constructSubmission(
      instanceId,
      burnTokens,
      redeemAmount,
      totalLimit,
      expiration
    );

    // Test redeem
    vm.startPrank(other1);
    creatorCore1155.setApprovalForAll(address(example), true);
    example.burnRedeem(submission);
    vm.stopPrank();

    // Check token burned
    assertEq(creatorCore1155.balanceOf(other1, 1), 8);
  }

  function testCrossChainBurn1155BurnSpecNone() public {
    vm.startPrank(owner);
    address[] memory recipients = new address[](1);
    recipients[0] = other1;
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = 10;
    string[] memory uris = new string[](1);
    creatorCore1155.mintBaseNew(recipients, amounts, uris);
    vm.stopPrank();

    ICrossChainBurn.BurnToken[] memory burnTokens = new ICrossChainBurn.BurnToken[](1);
    burnTokens[0] = ICrossChainBurn.BurnToken({
      contractAddress: address(creatorCore1155),
      tokenId: 1,
      tokenSpec: ICrossChainBurn.TokenSpec.ERC1155,
      burnSpec: ICrossChainBurn.BurnSpec.NONE,
      amount: 2
    });

    uint256 instanceId = 100;
    uint64 redeemAmount = 1;
    uint64 totalLimit = 0;
    uint160 expiration = uint160(block.timestamp + 1000);

    ICrossChainBurn.BurnSubmission memory submission = constructSubmission(
      instanceId,
      burnTokens,
      redeemAmount,
      totalLimit,
      expiration
    );

    // Test redeem
    vm.startPrank(other1);
    creatorCore1155.setApprovalForAll(address(example), true);
    example.burnRedeem(submission);
    vm.stopPrank();

    // Check token burned
    assertEq(creatorCore1155.balanceOf(other1, 1), 8);
    assertEq(creatorCore1155.balanceOf(address(0xdead), 1), 2);
  }

  function testCrossChainBurnMultiBurn() public {
    vm.startPrank(owner);
    creatorCore721.mintBase(other1, "");
    address[] memory recipients = new address[](1);
    recipients[0] = other1;
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = 10;
    string[] memory uris = new string[](1);
    creatorCore1155.mintBaseNew(recipients, amounts, uris);
    vm.stopPrank();

    ICrossChainBurn.BurnToken[] memory burnTokens = new ICrossChainBurn.BurnToken[](2);
    burnTokens[0] = ICrossChainBurn.BurnToken({
      contractAddress: address(creatorCore721),
      tokenId: 1,
      tokenSpec: ICrossChainBurn.TokenSpec.ERC721,
      burnSpec: ICrossChainBurn.BurnSpec.MANIFOLD,
      amount: 1
    });
    burnTokens[1] = ICrossChainBurn.BurnToken({
      contractAddress: address(creatorCore1155),
      tokenId: 1,
      tokenSpec: ICrossChainBurn.TokenSpec.ERC1155,
      burnSpec: ICrossChainBurn.BurnSpec.MANIFOLD,
      amount: 2
    });

    uint256 instanceId = 100;
    uint64 redeemAmount = 1;
    uint64 totalLimit = 0;
    uint160 expiration = uint160(block.timestamp + 1000);

    ICrossChainBurn.BurnSubmission memory submission = constructSubmission(
      instanceId,
      burnTokens,
      redeemAmount,
      totalLimit,
      expiration
    );

    // Test redeem
    vm.startPrank(other1);
    creatorCore721.approve(address(example), 1);
    creatorCore1155.setApprovalForAll(address(example), true);
    example.burnRedeem(submission);
    vm.stopPrank();

    // Check token burned
    vm.expectRevert("ERC721: invalid token ID");
    creatorCore721.ownerOf(1);
    assertEq(creatorCore1155.balanceOf(other1, 1), 8);
  }

  function testCrossChainBurnMultiSubmission() public {
    vm.startPrank(owner);
    creatorCore721.mintBase(other1, "");
    creatorCore721.mintBase(other1, "");
    vm.stopPrank();

    ICrossChainBurn.BurnToken[] memory burnTokens1 = new ICrossChainBurn.BurnToken[](1);
    burnTokens1[0] = ICrossChainBurn.BurnToken({
      contractAddress: address(creatorCore721),
      tokenId: 1,
      tokenSpec: ICrossChainBurn.TokenSpec.ERC721,
      burnSpec: ICrossChainBurn.BurnSpec.MANIFOLD,
      amount: 1
    });
    ICrossChainBurn.BurnToken[] memory burnTokens2 = new ICrossChainBurn.BurnToken[](1);
    burnTokens2[0] = ICrossChainBurn.BurnToken({
      contractAddress: address(creatorCore721),
      tokenId: 2,
      tokenSpec: ICrossChainBurn.TokenSpec.ERC721,
      burnSpec: ICrossChainBurn.BurnSpec.MANIFOLD,
      amount: 1
    });

    uint256 instanceId = 100;
    uint64 redeemAmount = 1;
    uint64 totalLimit = 0;
    uint160 expiration = uint160(block.timestamp + 1000);

    ICrossChainBurn.BurnSubmission[] memory submissions = new ICrossChainBurn.BurnSubmission[](2);
    submissions[0] = constructSubmission(instanceId, burnTokens1, redeemAmount, totalLimit, expiration);
    submissions[1] = constructSubmission(instanceId, burnTokens2, redeemAmount, totalLimit, expiration);

    // Test redeem
    vm.startPrank(other1);
    creatorCore721.approve(address(example), 1);
    creatorCore721.approve(address(example), 2);
    example.burnRedeem(submissions);
    vm.stopPrank();

    // Check token burned
    vm.expectRevert("ERC721: invalid token ID");
    creatorCore721.ownerOf(1);
    vm.expectRevert("ERC721: invalid token ID");
    creatorCore721.ownerOf(2);
  }

  /**
   * Sold out due to total limit (single-submission)
   */
  function testCrossChainBurnSoldOut() public {
    ICrossChainBurn.BurnToken[] memory burnTokens = new ICrossChainBurn.BurnToken[](0);
    uint256 instanceId = 100;
    uint64 redeemAmount = 2;
    uint64 totalLimit = 2;
    uint160 expiration = uint160(block.timestamp + 1000);

    ICrossChainBurn.BurnSubmission memory submission = constructSubmission(
      instanceId,
      burnTokens,
      redeemAmount,
      totalLimit,
      expiration
    );

    // Test redeem (second time should fail because exceeding totalLimit)
    vm.startPrank(other1);
    example.burnRedeem(submission);
    vm.stopPrank();

    submission = constructSubmission(instanceId, burnTokens, redeemAmount, totalLimit, expiration);
    vm.startPrank(other1);
    vm.expectRevert(ICrossChainBurn.InsufficientSupply.selector);
    example.burnRedeem(submission);
    vm.stopPrank();
  }

  /**
   * Sold out due to total limit (multi-submissions)
   */
  function testCrossChainBurnMultiSubmissionSoldOut() public {
    vm.startPrank(owner);
    creatorCore721.mintBase(other1, "");
    creatorCore721.mintBase(other1, "");
    vm.stopPrank();

    ICrossChainBurn.BurnToken[] memory burnTokens1 = new ICrossChainBurn.BurnToken[](1);
    burnTokens1[0] = ICrossChainBurn.BurnToken({
      contractAddress: address(creatorCore721),
      tokenId: 1,
      tokenSpec: ICrossChainBurn.TokenSpec.ERC721,
      burnSpec: ICrossChainBurn.BurnSpec.MANIFOLD,
      amount: 1
    });
    ICrossChainBurn.BurnToken[] memory burnTokens2 = new ICrossChainBurn.BurnToken[](1);
    burnTokens2[0] = ICrossChainBurn.BurnToken({
      contractAddress: address(creatorCore721),
      tokenId: 2,
      tokenSpec: ICrossChainBurn.TokenSpec.ERC721,
      burnSpec: ICrossChainBurn.BurnSpec.MANIFOLD,
      amount: 1
    });

    uint256 instanceId = 100;
    uint64 redeemAmount = 1;
    uint64 totalLimit = 1;
    uint160 expiration = uint160(block.timestamp + 1000);

    ICrossChainBurn.BurnSubmission[] memory submissions = new ICrossChainBurn.BurnSubmission[](2);
    submissions[0] = constructSubmission(instanceId, burnTokens1, redeemAmount, totalLimit, expiration);

    submissions[1] = constructSubmission(instanceId, burnTokens2, redeemAmount, totalLimit, expiration);

    // Test redeem
    vm.startPrank(other1);
    creatorCore721.approve(address(example), 1);
    creatorCore721.approve(address(example), 2);
    example.burnRedeem(submissions);
    vm.stopPrank();

    // Check token burned
    vm.expectRevert("ERC721: invalid token ID");
    creatorCore721.ownerOf(1);
    // Token 2 not burned because we were sold out and it didn't process
    assertEq(creatorCore721.ownerOf(2), other1);
  }
}
