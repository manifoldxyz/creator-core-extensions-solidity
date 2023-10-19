// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../contracts/physicalclaim/PhysicalClaim.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC721Creator.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC1155Creator.sol";
import "../../contracts/libraries/delegation-registry/DelegationRegistry.sol";
import "../mocks/Mock.sol";
import "../../lib/murky/src/Merkle.sol";

contract PhysicalClaimTest is Test {
  PhysicalClaim public example;
  ERC721Creator public creatorCore721;
  ERC1155Creator public creatorCore1155;

  DelegationRegistry public delegationRegistry;
  Merkle public merkle;

  address public owner = 0x6140F00e4Ff3936702E68744f2b5978885464cbB;
  address public other = 0xc78Dc443c126af6E4f6Ed540c1e740C1b5be09cd;
  address public other2 = 0x80AAC46bbd3C2FcE33681541a52CacBEd14bF425;
  address public other3 = 0x5174cD462b60c536eb51D4ceC1D561D3Ea31004F;

  address public signerForCost = 0x6140F00E4Ff3936702e68744f2b5978885464CBc;

  address public zeroAddress = address(0);

  uint instanceId = 1;

  function setUp() public {
    vm.startPrank(owner);
    creatorCore721 = new ERC721Creator("Token", "NFT");
    creatorCore1155 = new ERC1155Creator("Token", "NFT");

    delegationRegistry = new DelegationRegistry();
    example = new PhysicalClaim(owner);

    merkle = new Merkle();

    vm.deal(owner, 10 ether);
    vm.deal(other, 10 ether);
    vm.deal(other2, 10 ether);
    vm.deal(other3, 10 ether);
    vm.stopPrank();
  }

  function testAccess() public {
    vm.startPrank(other);
    vm.expectRevert();
    example.recover(address(creatorCore721), 1, other);
    vm.stopPrank();

    // Accidentally send token to contract
    vm.startPrank(owner);

    creatorCore721.mintBase(owner, "");
    creatorCore721.transferFrom(owner, address(example), 1);
    
    example.recover(address(creatorCore721), 1, owner);

    vm.stopPrank();
  }

  function testInputs() public {
    vm.startPrank(owner);

    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 0,
      startDate: 0,
      endDate: 0,
      cost: 0,
      burnSet: new IPhysicalClaimCore.BurnGroup[](0),
      variations: new IPhysicalClaimCore.Variation[](0),
      signer: signerForCost
    });

    // Cannot do instanceId of 0
    vm.expectRevert();
    example.initializePhysicalClaim(0, claimPs);

    // Cannot do largest instanceID
    vm.expectRevert();
    example.initializePhysicalClaim(2**56, claimPs);

    vm.stopPrank();
  }

  function testHappyCase() public {
    vm.startPrank(owner);

    // Mint token 1 to other
    creatorCore721.mintBase(other, "");

    IPhysicalClaimCore.BurnItem[] memory burnItems = new IPhysicalClaimCore.BurnItem[](1);
    burnItems[0] = IPhysicalClaimCore.BurnItem({
      validationType: IPhysicalClaimCore.ValidationType.CONTRACT,
      contractAddress: address(creatorCore721),
      tokenSpec: IPhysicalClaimCore.TokenSpec.ERC721,
      burnSpec: IPhysicalClaimCore.BurnSpec.MANIFOLD,
      amount: 1,
      minTokenId: 1,
      maxTokenId: 1,
      merkleRoot: ""
    });

    IPhysicalClaimCore.BurnGroup[] memory burnSet = new IPhysicalClaimCore.BurnGroup[](1);
    burnSet[0] = IPhysicalClaimCore.BurnGroup({
        requiredCount: 1,
        items: burnItems
      });

    IPhysicalClaimCore.Variation[] memory variations = new IPhysicalClaimCore.Variation[](1);
    variations[0] = IPhysicalClaimCore.Variation({
      id: 1,
      max: 1
    });

    // Create claim initialization parameters
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 0,
      startDate: 0,
      endDate: 0,
      cost: 0,
      burnSet: burnSet,
      variations: variations,
      signer: signerForCost
    });

    // Initialize the physical claim
    example.initializePhysicalClaim(instanceId, claimPs);

    // Can get the claim
    IPhysicalClaimCore.PhysicalClaim memory claim = example.getPhysicalClaim(instanceId);
    assertEq(claim.paymentReceiver, owner);

    // Cannot get claim that doesn't exist
    vm.expectRevert();
    example.getPhysicalClaim(2);

    // Can update
    claimPs.totalSupply = 2;
    example.updatePhysicalClaim(instanceId, claimPs);

    // Can't update _not_ your own
    vm.stopPrank();
    vm.startPrank(other);
    vm.expectRevert(bytes("Must be admin"));
    example.updatePhysicalClaim(instanceId, claimPs);
    // Actually do a burnRedeem

    // Approve token for burning
    creatorCore721.approve(address(example), 1);

    IPhysicalClaimCore.BurnToken[] memory burnTokens = new IPhysicalClaimCore.BurnToken[](1);
    burnTokens[0] = IPhysicalClaimCore.BurnToken({
      groupIndex: 0,
      itemIndex: 0,
      contractAddress: address(creatorCore721),
      id: 1,
      merkleProof: new bytes32[](0)
    });


    IPhysicalClaimCore.PhysicalClaimSubmission[] memory submissions = new IPhysicalClaimCore.PhysicalClaimSubmission[](1);
    submissions[0].instanceId = instanceId;
    submissions[0].physicalClaimCount = 1;
    submissions[0].currentClaimCount = 0;
    submissions[0].burnTokens = burnTokens;
    submissions[0].variation = 0;
    submissions[0].data = "";

    example.burnRedeem(submissions);

    vm.stopPrank();

    vm.startPrank(owner);
    // Mint new token to "other"
    creatorCore721.mintBase(other, "");

    vm.stopPrank();
    vm.startPrank(other);

    // Approve token for burning
    creatorCore721.approve(address(example), 2);

    burnTokens[0] = IPhysicalClaimCore.BurnToken({
      groupIndex: 0,
      itemIndex: 0,
      contractAddress: address(creatorCore721),
      id: 2,
      merkleProof: new bytes32[](0)
    });

    // Send a non-zero value burn
    example.burnRedeem{value: 1 ether}(submissions);

    vm.stopPrank();

    // Case where total supply is not unlimited and they use remaining supply
    vm.startPrank(owner);

    claimPs.totalSupply = 1;
    example.initializePhysicalClaim(instanceId+1, claimPs);

    creatorCore721.mintBase(owner, "");

    // Approve token for burning
    creatorCore721.approve(address(example), 3);

    burnTokens[0] = IPhysicalClaimCore.BurnToken({
      groupIndex: 0,
      itemIndex: 0,
      contractAddress: address(creatorCore721),
      id: 3,
      merkleProof: new bytes32[](0)
    });

    submissions[0].instanceId = instanceId+1;

    example.burnRedeem(submissions);

    // Case where total supply is huge, and they just redeem 1
    claimPs.totalSupply = 10;
    example.initializePhysicalClaim(instanceId+2, claimPs);

    creatorCore721.mintBase(owner, "");

    // Approve token for burning
    creatorCore721.approve(address(example), 4);

    burnTokens[0] = IPhysicalClaimCore.BurnToken({
      groupIndex: 0,
      itemIndex: 0,
      contractAddress: address(creatorCore721),
      id: 4,
      merkleProof: new bytes32[](0)
    });

    submissions[0].instanceId = instanceId+2;

    example.burnRedeem(submissions);

    vm.stopPrank();
  }

  function testBurnFinalToken() public {
    vm.startPrank(owner);

    // Mint 2 tokens to other
    creatorCore721.mintBase(other, "");
    creatorCore721.mintBase(other, "");

    IPhysicalClaimCore.BurnItem[] memory burnItems = new IPhysicalClaimCore.BurnItem[](1);
    burnItems[0] = IPhysicalClaimCore.BurnItem({
      validationType: IPhysicalClaimCore.ValidationType.CONTRACT,
      contractAddress: address(creatorCore721),
      tokenSpec: IPhysicalClaimCore.TokenSpec.ERC721,
      burnSpec: IPhysicalClaimCore.BurnSpec.MANIFOLD,
      amount: 1,
      minTokenId: 1,
      maxTokenId: 1,
      merkleRoot: ""
    });

    IPhysicalClaimCore.BurnGroup[] memory burnSet = new IPhysicalClaimCore.BurnGroup[](1);
    burnSet[0] = IPhysicalClaimCore.BurnGroup({
      requiredCount: 1,
      items: burnItems
    });

    IPhysicalClaimCore.Variation[] memory variations = new IPhysicalClaimCore.Variation[](1);
    variations[0] = IPhysicalClaimCore.Variation({
      id: 1,
      max: 1
    });

    // Create claim initialization parameters. Total supply is 1 so they will use the whole supply
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 1,
      startDate: 0,
      endDate: 0,
      cost: 0,
      burnSet: burnSet,
      variations: variations,
      signer: signerForCost
    });

    // Initialize the physical claim
    example.initializePhysicalClaim(instanceId, claimPs);

    vm.stopPrank();
    vm.startPrank(other);

    // Approve token for burning
    creatorCore721.approve(address(example), 1);

    IPhysicalClaimCore.BurnToken[] memory burnTokens = new IPhysicalClaimCore.BurnToken[](1);
    burnTokens[0] = IPhysicalClaimCore.BurnToken({
      groupIndex: 0,
      itemIndex: 0,
      contractAddress: address(creatorCore721),
      id: 1,
      merkleProof: new bytes32[](0)
    });

    IPhysicalClaimCore.PhysicalClaimSubmission[] memory submissions = new IPhysicalClaimCore.PhysicalClaimSubmission[](1);
    submissions[0].instanceId = instanceId;
    submissions[0].physicalClaimCount = 1;
    submissions[0].currentClaimCount = 0;
    submissions[0].burnTokens = burnTokens;
    submissions[0].variation = 0;
    submissions[0].data = "";

    example.burnRedeem(submissions);

    // Approve token for burning
    creatorCore721.approve(address(example), 2);

    burnTokens[0] = IPhysicalClaimCore.BurnToken({
      groupIndex: 0,
      itemIndex: 0,
      contractAddress: address(creatorCore721),
      id: 2,
      merkleProof: new bytes32[](0)
    });

    submissions[0].instanceId = instanceId;
    submissions[0].physicalClaimCount = 1;
    submissions[0].currentClaimCount = 1;
    submissions[0].burnTokens = burnTokens;
    submissions[0].variation = 0;
    submissions[0].data = "";

    vm.expectRevert(); // should revert cause none remaining and the setting is to revert it...
    example.burnRedeem(submissions);

    vm.stopPrank();
  }

  function testTwoForOneBurn() public {
    vm.startPrank(owner);

    // Mint 2 tokens to other
    creatorCore721.mintBase(other, "");
    creatorCore721.mintBase(other, "");

    IPhysicalClaimCore.BurnItem[] memory burnItems = new IPhysicalClaimCore.BurnItem[](2);
    burnItems[0] = IPhysicalClaimCore.BurnItem({
      validationType: IPhysicalClaimCore.ValidationType.CONTRACT,
      contractAddress: address(creatorCore721),
      tokenSpec: IPhysicalClaimCore.TokenSpec.ERC721,
      burnSpec: IPhysicalClaimCore.BurnSpec.MANIFOLD,
      amount: 1,
      minTokenId: 1,
      maxTokenId: 1,
      merkleRoot: ""
    });
    burnItems[1] = IPhysicalClaimCore.BurnItem({
      validationType: IPhysicalClaimCore.ValidationType.CONTRACT,
      contractAddress: address(creatorCore721),
      tokenSpec: IPhysicalClaimCore.TokenSpec.ERC721,
      burnSpec: IPhysicalClaimCore.BurnSpec.MANIFOLD,
      amount: 1,
      minTokenId: 2,
      maxTokenId: 2,
      merkleRoot: ""
    });

    IPhysicalClaimCore.BurnGroup[] memory burnSet = new IPhysicalClaimCore.BurnGroup[](1);
    burnSet[0] = IPhysicalClaimCore.BurnGroup({
      requiredCount: 2,
      items: burnItems
    });

    IPhysicalClaimCore.Variation[] memory variations = new IPhysicalClaimCore.Variation[](1);
    variations[0] = IPhysicalClaimCore.Variation({
      id: 1,
      max: 1
    });

    // Create claim initialization parameters. Total supply is 1 so they will use the whole supply
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 1,
      startDate: 0,
      endDate: 0,
      cost: 0,
      burnSet: burnSet,
      variations: variations,
      signer: signerForCost
    });

    // Initialize the physical claim
    example.initializePhysicalClaim(instanceId, claimPs);

    vm.stopPrank();
    vm.startPrank(other);

    // Approve token for burning
    creatorCore721.approve(address(example), 1);
    creatorCore721.approve(address(example), 2);

    IPhysicalClaimCore.BurnToken[] memory burnTokens = new IPhysicalClaimCore.BurnToken[](2);
    burnTokens[0] = IPhysicalClaimCore.BurnToken({
      groupIndex: 0,
      itemIndex: 0,
      contractAddress: address(creatorCore721),
      id: 1,
      merkleProof: new bytes32[](0)
    });
    burnTokens[1] = IPhysicalClaimCore.BurnToken({
      groupIndex: 0,
      itemIndex: 1,
      contractAddress: address(creatorCore721),
      id: 2,
      merkleProof: new bytes32[](0)
    });

    IPhysicalClaimCore.PhysicalClaimSubmission[] memory submissions = new IPhysicalClaimCore.PhysicalClaimSubmission[](1);
    submissions[0].instanceId = instanceId;
    submissions[0].physicalClaimCount = 1;
    submissions[0].currentClaimCount = 0;
    submissions[0].burnTokens = burnTokens;
    submissions[0].variation = 0;
    submissions[0].data = "";

    example.burnRedeem(submissions);

    vm.stopPrank();
  }

  function testClaimMoreThanOneAtOnce() public {
    vm.startPrank(owner);

    // Mint 2 tokens to other
    creatorCore721.mintBase(other, "");
    creatorCore721.mintBase(other, "");

    IPhysicalClaimCore.BurnItem[] memory burnItems = new IPhysicalClaimCore.BurnItem[](1);
    burnItems[0] = IPhysicalClaimCore.BurnItem({
      validationType: IPhysicalClaimCore.ValidationType.CONTRACT,
      contractAddress: address(creatorCore721),
      tokenSpec: IPhysicalClaimCore.TokenSpec.ERC721,
      burnSpec: IPhysicalClaimCore.BurnSpec.MANIFOLD,
      amount: 1,
      minTokenId: 1,
      maxTokenId: 3,
      merkleRoot: ""
    });

    IPhysicalClaimCore.BurnGroup[] memory burnSet = new IPhysicalClaimCore.BurnGroup[](1);
    burnSet[0] = IPhysicalClaimCore.BurnGroup({
      requiredCount: 1,
      items: burnItems
    });

    IPhysicalClaimCore.Variation[] memory variations = new IPhysicalClaimCore.Variation[](1);
    variations[0] = IPhysicalClaimCore.Variation({
      id: 1,
      max: 1
    });

    // Create claim initialization parameters. Total supply is 1 so they will use the whole supply
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 2,
      startDate: 0,
      endDate: 0,
      cost: 0,
      burnSet: burnSet,
      variations: variations,
      signer: signerForCost
    });

    // Initialize the physical claim
    example.initializePhysicalClaim(instanceId, claimPs);

    vm.stopPrank();
    vm.startPrank(other);

    // Approve token for burning
    creatorCore721.approve(address(example), 1);
    creatorCore721.approve(address(example), 2);

    IPhysicalClaimCore.BurnToken[] memory burnTokens = new IPhysicalClaimCore.BurnToken[](1);
    burnTokens[0] = IPhysicalClaimCore.BurnToken({
      groupIndex: 0,
      itemIndex: 0,
      contractAddress: address(creatorCore721),
      id: 1,
      merkleProof: new bytes32[](0)
    });

    IPhysicalClaimCore.PhysicalClaimSubmission[] memory submissions = new IPhysicalClaimCore.PhysicalClaimSubmission[](2);
    submissions[0].instanceId = instanceId;
    submissions[0].physicalClaimCount = 1;
    submissions[0].currentClaimCount = 0;
    submissions[0].burnTokens = burnTokens;
    submissions[0].variation = 0;
    submissions[0].data = "";

    IPhysicalClaimCore.BurnToken[] memory burnTokens2 = new IPhysicalClaimCore.BurnToken[](1);
    burnTokens2[0] = IPhysicalClaimCore.BurnToken({
      groupIndex: 0,
      itemIndex: 0,
      contractAddress: address(creatorCore721),
      id: 2,
      merkleProof: new bytes32[](0)
    });
    submissions[1].instanceId = instanceId;
    submissions[1].physicalClaimCount = 1;
    submissions[1].currentClaimCount = 0;
    submissions[1].burnTokens = burnTokens2;
    submissions[1].variation = 0;
    submissions[1].data = "";

    example.burnRedeem(submissions);

    vm.stopPrank();
  }

  function testNonZeroCost() public {
    vm.startPrank(owner);

    // Mint 2 tokens to other
    creatorCore721.mintBase(other, "");

    IPhysicalClaimCore.BurnItem[] memory burnItems = new IPhysicalClaimCore.BurnItem[](1);
    burnItems[0] = IPhysicalClaimCore.BurnItem({
      validationType: IPhysicalClaimCore.ValidationType.CONTRACT,
      contractAddress: address(creatorCore721),
      tokenSpec: IPhysicalClaimCore.TokenSpec.ERC721,
      burnSpec: IPhysicalClaimCore.BurnSpec.MANIFOLD,
      amount: 1,
      minTokenId: 1,
      maxTokenId: 3,
      merkleRoot: ""
    });

    IPhysicalClaimCore.BurnGroup[] memory burnSet = new IPhysicalClaimCore.BurnGroup[](1);
    burnSet[0] = IPhysicalClaimCore.BurnGroup({
      requiredCount: 1,
      items: burnItems
    });

    IPhysicalClaimCore.Variation[] memory variations = new IPhysicalClaimCore.Variation[](1);
    variations[0] = IPhysicalClaimCore.Variation({
      id: 1,
      max: 1
    });

    // Create claim initialization parameters. Total supply is 1 so they will use the whole supply
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 2,
      startDate: 0,
      endDate: 0,
      cost: 1,
      burnSet: burnSet,
      variations: variations,
      signer: signerForCost
    });

    // Initialize the physical claim
    example.initializePhysicalClaim(instanceId, claimPs);

    vm.stopPrank();
    vm.startPrank(other);

    // Approve token for burning
    creatorCore721.approve(address(example), 1);

    IPhysicalClaimCore.BurnToken[] memory burnTokens = new IPhysicalClaimCore.BurnToken[](1);
    burnTokens[0] = IPhysicalClaimCore.BurnToken({
      groupIndex: 0,
      itemIndex: 0,
      contractAddress: address(creatorCore721),
      id: 1,
      merkleProof: new bytes32[](0)
    });

    IPhysicalClaimCore.PhysicalClaimSubmission[] memory submissions = new IPhysicalClaimCore.PhysicalClaimSubmission[](1);
    submissions[0].instanceId = instanceId;
    submissions[0].physicalClaimCount = 1;
    submissions[0].currentClaimCount = 0;
    submissions[0].burnTokens = burnTokens;
    submissions[0].variation = 0;
    submissions[0].data = "";

    vm.expectRevert();
    example.burnRedeem{value: 0}(submissions);

    example.burnRedeem{value: 1}(submissions);

    vm.stopPrank();
  }

  function testPhysicalClaimCount2() public {
    vm.startPrank(owner);

    // Mint 2 tokens to other
    creatorCore721.mintBase(other, "");

    IPhysicalClaimCore.BurnItem[] memory burnItems = new IPhysicalClaimCore.BurnItem[](1);
    burnItems[0] = IPhysicalClaimCore.BurnItem({
      validationType: IPhysicalClaimCore.ValidationType.CONTRACT,
      contractAddress: address(creatorCore721),
      tokenSpec: IPhysicalClaimCore.TokenSpec.ERC721,
      burnSpec: IPhysicalClaimCore.BurnSpec.MANIFOLD,
      amount: 1,
      minTokenId: 1,
      maxTokenId: 3,
      merkleRoot: ""
    });

    IPhysicalClaimCore.BurnGroup[] memory burnSet = new IPhysicalClaimCore.BurnGroup[](1);
    burnSet[0] = IPhysicalClaimCore.BurnGroup({
      requiredCount: 1,
      items: burnItems
    });

    IPhysicalClaimCore.Variation[] memory variations = new IPhysicalClaimCore.Variation[](1);
    variations[0] = IPhysicalClaimCore.Variation({
      id: 1,
      max: 1
    });

    // Create claim initialization parameters. Total supply is 1 so they will use the whole supply
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 2,
      startDate: 0,
      endDate: 0,
      cost: 0,
      burnSet: burnSet,
      variations: variations,
      signer: signerForCost
    });

    // Initialize the physical claim
    example.initializePhysicalClaim(instanceId, claimPs);

    vm.stopPrank();
    vm.startPrank(other);

    // Approve token for burning
    creatorCore721.approve(address(example), 1);

    IPhysicalClaimCore.BurnToken[] memory burnTokens = new IPhysicalClaimCore.BurnToken[](1);
    burnTokens[0] = IPhysicalClaimCore.BurnToken({
      groupIndex: 0,
      itemIndex: 0,
      contractAddress: address(creatorCore721),
      id: 1,
      merkleProof: new bytes32[](0)
    });

    IPhysicalClaimCore.PhysicalClaimSubmission[] memory submissions = new IPhysicalClaimCore.PhysicalClaimSubmission[](1);
    submissions[0].instanceId = instanceId;
    submissions[0].physicalClaimCount = 2;
    submissions[0].currentClaimCount = 0;
    submissions[0].burnTokens = burnTokens;
    submissions[0].variation = 0;
    submissions[0].data = "";

    example.burnRedeem(submissions);
    vm.stopPrank();
  }

  function testTotalSupplyZero() public {
    vm.startPrank(owner);

    // Mint 2 tokens to other
    creatorCore721.mintBase(other, "");

    IPhysicalClaimCore.BurnItem[] memory burnItems = new IPhysicalClaimCore.BurnItem[](1);
    burnItems[0] = IPhysicalClaimCore.BurnItem({
      validationType: IPhysicalClaimCore.ValidationType.CONTRACT,
      contractAddress: address(creatorCore721),
      tokenSpec: IPhysicalClaimCore.TokenSpec.ERC721,
      burnSpec: IPhysicalClaimCore.BurnSpec.MANIFOLD,
      amount: 1,
      minTokenId: 1,
      maxTokenId: 3,
      merkleRoot: ""
    });

    IPhysicalClaimCore.BurnGroup[] memory burnSet = new IPhysicalClaimCore.BurnGroup[](1);
    burnSet[0] = IPhysicalClaimCore.BurnGroup({
      requiredCount: 1,
      items: burnItems
    });

    IPhysicalClaimCore.Variation[] memory variations = new IPhysicalClaimCore.Variation[](1);
    variations[0] = IPhysicalClaimCore.Variation({
      id: 1,
      max: 1
    });

    // Create claim initialization parameters. Total supply is 1 so they will use the whole supply
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 0,
      startDate: 0,
      endDate: 0,
      cost: 0,
      burnSet: burnSet,
      variations: variations,
      signer: signerForCost
    });

    // Initialize the physical claim
    example.initializePhysicalClaim(instanceId, claimPs);

    vm.stopPrank();
    vm.startPrank(other);

    // Approve token for burning
    creatorCore721.approve(address(example), 1);

    IPhysicalClaimCore.BurnToken[] memory burnTokens = new IPhysicalClaimCore.BurnToken[](1);
    burnTokens[0] = IPhysicalClaimCore.BurnToken({
      groupIndex: 0,
      itemIndex: 0,
      contractAddress: address(creatorCore721),
      id: 1,
      merkleProof: new bytes32[](0)
    });

    IPhysicalClaimCore.PhysicalClaimSubmission[] memory submissions = new IPhysicalClaimCore.PhysicalClaimSubmission[](1);
    submissions[0].instanceId = instanceId;
    submissions[0].physicalClaimCount = 2;
    submissions[0].currentClaimCount = 0;
    submissions[0].burnTokens = burnTokens;
    submissions[0].variation = 0;
    submissions[0].data = "";

    example.burnRedeem(submissions);
    vm.stopPrank();
  }

  function test1155NotSupportedYet() public {
    vm.startPrank(owner);

    // Mint 2 tokens to other
    creatorCore721.mintBase(other, "");

    IPhysicalClaimCore.BurnItem[] memory burnItems = new IPhysicalClaimCore.BurnItem[](1);
    burnItems[0] = IPhysicalClaimCore.BurnItem({
      validationType: IPhysicalClaimCore.ValidationType.CONTRACT,
      contractAddress: address(creatorCore1155),
      tokenSpec: IPhysicalClaimCore.TokenSpec.ERC1155,
      burnSpec: IPhysicalClaimCore.BurnSpec.MANIFOLD,
      amount: 1,
      minTokenId: 1,
      maxTokenId: 3,
      merkleRoot: ""
    });

    IPhysicalClaimCore.BurnGroup[] memory burnSet = new IPhysicalClaimCore.BurnGroup[](1);
    burnSet[0] = IPhysicalClaimCore.BurnGroup({
      requiredCount: 1,
      items: burnItems
    });

    IPhysicalClaimCore.Variation[] memory variations = new IPhysicalClaimCore.Variation[](1);
    variations[0] = IPhysicalClaimCore.Variation({
      id: 1,
      max: 1
    });

    // Create claim initialization parameters. Total supply is 1 so they will use the whole supply
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 0,
      startDate: 0,
      endDate: 0,
      cost: 0,
      burnSet: burnSet,
      variations: variations,
      signer: signerForCost
    });

    // Initialize the physical claim
    example.initializePhysicalClaim(instanceId, claimPs);

    vm.stopPrank();
    vm.startPrank(other);

    // Approve token for burning
    creatorCore721.approve(address(example), 1);

    IPhysicalClaimCore.BurnToken[] memory burnTokens = new IPhysicalClaimCore.BurnToken[](1);
    burnTokens[0] = IPhysicalClaimCore.BurnToken({
      groupIndex: 0,
      itemIndex: 0,
      contractAddress: address(creatorCore1155),
      id: 1,
      merkleProof: new bytes32[](0)
    });

    IPhysicalClaimCore.PhysicalClaimSubmission[] memory submissions = new IPhysicalClaimCore.PhysicalClaimSubmission[](1);
    submissions[0].instanceId = instanceId;
    submissions[0].physicalClaimCount = 2;
    submissions[0].currentClaimCount = 0;
    submissions[0].burnTokens = burnTokens;
    submissions[0].variation = 0;
    submissions[0].data = "";

    vm.expectRevert();
    example.burnRedeem(submissions);
    vm.stopPrank();
  }

  function testBurnSpecNoneTransferToDead() public {
    vm.startPrank(owner);

    // Mint 2 tokens to other
    creatorCore721.mintBase(other, "");

    IPhysicalClaimCore.BurnItem[] memory burnItems = new IPhysicalClaimCore.BurnItem[](1);
    burnItems[0] = IPhysicalClaimCore.BurnItem({
      validationType: IPhysicalClaimCore.ValidationType.CONTRACT,
      contractAddress: address(creatorCore721),
      tokenSpec: IPhysicalClaimCore.TokenSpec.ERC721,
      burnSpec: IPhysicalClaimCore.BurnSpec.NONE,
      amount: 1,
      minTokenId: 1,
      maxTokenId: 3,
      merkleRoot: ""
    });

    IPhysicalClaimCore.BurnGroup[] memory burnSet = new IPhysicalClaimCore.BurnGroup[](1);
    burnSet[0] = IPhysicalClaimCore.BurnGroup({
      requiredCount: 1,
      items: burnItems
    });

    IPhysicalClaimCore.Variation[] memory variations = new IPhysicalClaimCore.Variation[](1);
    variations[0] = IPhysicalClaimCore.Variation({
      id: 1,
      max: 1
    });

    // Create claim initialization parameters. Total supply is 1 so they will use the whole supply
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 0,
      startDate: 0,
      endDate: 0,
      cost: 0,
      burnSet: burnSet,
      variations: variations,
      signer: signerForCost
    });

    // Initialize the physical claim
    example.initializePhysicalClaim(instanceId, claimPs);

    vm.stopPrank();
    vm.startPrank(other);

    // Approve token for burning
    creatorCore721.approve(address(example), 1);

    IPhysicalClaimCore.BurnToken[] memory burnTokens = new IPhysicalClaimCore.BurnToken[](1);
    burnTokens[0] = IPhysicalClaimCore.BurnToken({
      groupIndex: 0,
      itemIndex: 0,
      contractAddress: address(creatorCore721),
      id: 1,
      merkleProof: new bytes32[](0)
    });

    IPhysicalClaimCore.PhysicalClaimSubmission[] memory submissions = new IPhysicalClaimCore.PhysicalClaimSubmission[](1);
    submissions[0].instanceId = instanceId;
    submissions[0].physicalClaimCount = 1;
    submissions[0].currentClaimCount = 0;
    submissions[0].burnTokens = burnTokens;
    submissions[0].variation = 0;
    submissions[0].data = "";

    example.burnRedeem(submissions);
    vm.stopPrank();
  }

  function testBurnSpecOZ() public {
    vm.startPrank(owner);

    // Mint 2 tokens to other
    creatorCore721.mintBase(other, "");

    IPhysicalClaimCore.BurnItem[] memory burnItems = new IPhysicalClaimCore.BurnItem[](1);
    burnItems[0] = IPhysicalClaimCore.BurnItem({
      validationType: IPhysicalClaimCore.ValidationType.CONTRACT,
      contractAddress: address(creatorCore721),
      tokenSpec: IPhysicalClaimCore.TokenSpec.ERC721,
      burnSpec: IPhysicalClaimCore.BurnSpec.OPENZEPPELIN,
      amount: 1,
      minTokenId: 1,
      maxTokenId: 3,
      merkleRoot: ""
    });

    IPhysicalClaimCore.BurnGroup[] memory burnSet = new IPhysicalClaimCore.BurnGroup[](1);
    burnSet[0] = IPhysicalClaimCore.BurnGroup({
      requiredCount: 1,
      items: burnItems
    });

    IPhysicalClaimCore.Variation[] memory variations = new IPhysicalClaimCore.Variation[](1);
    variations[0] = IPhysicalClaimCore.Variation({
      id: 1,
      max: 1
    });

    // Create claim initialization parameters. Total supply is 1 so they will use the whole supply
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 0,
      startDate: 0,
      endDate: 0,
      cost: 0,
      burnSet: burnSet,
      variations: variations,
      signer: signerForCost
    });

    // Initialize the physical claim
    example.initializePhysicalClaim(instanceId, claimPs);

    vm.stopPrank();
    vm.startPrank(other);

    // Approve token for burning
    creatorCore721.approve(address(example), 1);

    IPhysicalClaimCore.BurnToken[] memory burnTokens = new IPhysicalClaimCore.BurnToken[](1);
    burnTokens[0] = IPhysicalClaimCore.BurnToken({
      groupIndex: 0,
      itemIndex: 0,
      contractAddress: address(creatorCore721),
      id: 1,
      merkleProof: new bytes32[](0)
    });

    IPhysicalClaimCore.PhysicalClaimSubmission[] memory submissions = new IPhysicalClaimCore.PhysicalClaimSubmission[](1);
    submissions[0].instanceId = instanceId;
    submissions[0].physicalClaimCount = 1;
    submissions[0].currentClaimCount = 0;
    submissions[0].burnTokens = burnTokens;
    submissions[0].variation = 0;
    submissions[0].data = "";

    example.burnRedeem(submissions);
    vm.stopPrank();
  }

  function testInvalidContractAddress() public {
    vm.startPrank(owner);

    // Mint 2 tokens to other
    creatorCore721.mintBase(other, "");

    IPhysicalClaimCore.BurnItem[] memory burnItems = new IPhysicalClaimCore.BurnItem[](1);
    burnItems[0] = IPhysicalClaimCore.BurnItem({
      validationType: IPhysicalClaimCore.ValidationType.CONTRACT,
      contractAddress: address(creatorCore721),
      tokenSpec: IPhysicalClaimCore.TokenSpec.ERC721,
      burnSpec: IPhysicalClaimCore.BurnSpec.MANIFOLD,
      amount: 1,
      minTokenId: 1,
      maxTokenId: 3,
      merkleRoot: ""
    });

    IPhysicalClaimCore.BurnGroup[] memory burnSet = new IPhysicalClaimCore.BurnGroup[](1);
    burnSet[0] = IPhysicalClaimCore.BurnGroup({
      requiredCount: 1,
      items: burnItems
    });

    IPhysicalClaimCore.Variation[] memory variations = new IPhysicalClaimCore.Variation[](1);
    variations[0] = IPhysicalClaimCore.Variation({
      id: 1,
      max: 1
    });

    // Create claim initialization parameters. Total supply is 1 so they will use the whole supply
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 0,
      startDate: 0,
      endDate: 0,
      cost: 0,
      burnSet: burnSet,
      variations: variations,
      signer: signerForCost
    });

    // Initialize the physical claim
    example.initializePhysicalClaim(instanceId, claimPs);

    vm.stopPrank();
    vm.startPrank(other);

    // Approve token for burning
    creatorCore721.approve(address(example), 1);

    IPhysicalClaimCore.BurnToken[] memory burnTokens = new IPhysicalClaimCore.BurnToken[](1);
    burnTokens[0] = IPhysicalClaimCore.BurnToken({
      groupIndex: 0,
      itemIndex: 0,
      contractAddress: address(creatorCore1155),
      id: 1,
      merkleProof: new bytes32[](0)
    });

    IPhysicalClaimCore.PhysicalClaimSubmission[] memory submissions = new IPhysicalClaimCore.PhysicalClaimSubmission[](1);
    submissions[0].instanceId = instanceId;
    submissions[0].physicalClaimCount = 1;
    submissions[0].currentClaimCount = 0;
    submissions[0].burnTokens = burnTokens;
    submissions[0].variation = 0;
    submissions[0].data = "";

    vm.expectRevert();
    example.burnRedeem(submissions);
    vm.stopPrank();
  }

  function testRangeValidationType() public {
    vm.startPrank(owner);

    // Mint 2 tokens to other
    creatorCore721.mintBase(other, "");
    creatorCore721.mintBase(other, "");

    IPhysicalClaimCore.BurnItem[] memory burnItems = new IPhysicalClaimCore.BurnItem[](1);
    burnItems[0] = IPhysicalClaimCore.BurnItem({
      validationType: IPhysicalClaimCore.ValidationType.RANGE,
      contractAddress: address(creatorCore721),
      tokenSpec: IPhysicalClaimCore.TokenSpec.ERC721,
      burnSpec: IPhysicalClaimCore.BurnSpec.MANIFOLD,
      amount: 1,
      minTokenId: 2,
      maxTokenId: 4,
      merkleRoot: ""
    });

    IPhysicalClaimCore.BurnGroup[] memory burnSet = new IPhysicalClaimCore.BurnGroup[](1);
    burnSet[0] = IPhysicalClaimCore.BurnGroup({
      requiredCount: 1,
      items: burnItems
    });

    IPhysicalClaimCore.Variation[] memory variations = new IPhysicalClaimCore.Variation[](1);
    variations[0] = IPhysicalClaimCore.Variation({
      id: 1,
      max: 1
    });

    // Create claim initialization parameters. Total supply is 1 so they will use the whole supply
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 0,
      startDate: 0,
      endDate: 0,
      cost: 0,
      burnSet: burnSet,
      variations: variations,
      signer: signerForCost
    });

    // Initialize the physical claim
    example.initializePhysicalClaim(instanceId, claimPs);

    vm.stopPrank();
    vm.startPrank(other);

    // Approve token for burning
    creatorCore721.approve(address(example), 1);
    creatorCore721.approve(address(example), 2);

    IPhysicalClaimCore.BurnToken[] memory burnTokens = new IPhysicalClaimCore.BurnToken[](1);
    burnTokens[0] = IPhysicalClaimCore.BurnToken({
      groupIndex: 0,
      itemIndex: 0,
      contractAddress: address(creatorCore721),
      id: 1,
      merkleProof: new bytes32[](0)
    });

    IPhysicalClaimCore.PhysicalClaimSubmission[] memory submissions = new IPhysicalClaimCore.PhysicalClaimSubmission[](1);
    submissions[0].instanceId = instanceId;
    submissions[0].physicalClaimCount = 1;
    submissions[0].currentClaimCount = 0;
    submissions[0].burnTokens = burnTokens;
    submissions[0].variation = 0;
    submissions[0].data = "";

    vm.expectRevert();
    example.burnRedeem(submissions);

    burnTokens[0] = IPhysicalClaimCore.BurnToken({
      groupIndex: 0,
      itemIndex: 0,
      contractAddress: address(creatorCore721),
      id: 2,
      merkleProof: new bytes32[](0)
    });
    example.burnRedeem(submissions);

    vm.stopPrank();
  }

  function testCreateWithInvalidParameters() public {
    vm.startPrank(owner);

    // Mint 2 tokens to other
    creatorCore721.mintBase(other, "");
    creatorCore721.mintBase(other, "");

    IPhysicalClaimCore.BurnItem[] memory burnItems = new IPhysicalClaimCore.BurnItem[](1);
    burnItems[0] = IPhysicalClaimCore.BurnItem({
      validationType: IPhysicalClaimCore.ValidationType.RANGE,
      contractAddress: address(creatorCore721),
      tokenSpec: IPhysicalClaimCore.TokenSpec.ERC721,
      burnSpec: IPhysicalClaimCore.BurnSpec.MANIFOLD,
      amount: 1,
      minTokenId: 2,
      maxTokenId: 4,
      merkleRoot: ""
    });

    IPhysicalClaimCore.BurnGroup[] memory burnSet = new IPhysicalClaimCore.BurnGroup[](1);
    burnSet[0] = IPhysicalClaimCore.BurnGroup({
      requiredCount: 1,
      items: burnItems
    });

    IPhysicalClaimCore.Variation[] memory variations = new IPhysicalClaimCore.Variation[](1);
    variations[0] = IPhysicalClaimCore.Variation({
      id: 1,
      max: 1
    });

    // Create claim initialization parameters. Total supply is 1 so they will use the whole supply
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(0),
      totalSupply: 0,
      startDate: 0,
      endDate: 0,
      cost: 0,
      burnSet: burnSet,
      variations: variations,
      signer: signerForCost
    });

    // Initialize the physical claim
    vm.expectRevert();
    example.initializePhysicalClaim(instanceId, claimPs);

    claimPs.paymentReceiver = payable(owner);
    claimPs.startDate = 2;
    claimPs.endDate = 1;

    vm.expectRevert();
    example.initializePhysicalClaim(instanceId, claimPs);

    claimPs.startDate = 0;
    claimPs.endDate = 0;

    burnSet[0].requiredCount = 0;
    claimPs.burnSet = burnSet;

    vm.expectRevert();
    example.initializePhysicalClaim(instanceId, claimPs);

    burnSet[0].requiredCount = 1;
    burnSet[0].items = new IPhysicalClaimCore.BurnItem[](0);
    claimPs.burnSet = burnSet;

    vm.expectRevert();
    example.initializePhysicalClaim(instanceId, claimPs);

    vm.stopPrank();
  }


}
