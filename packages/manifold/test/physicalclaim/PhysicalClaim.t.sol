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
      redeemAmount: 1,
      redeemedCount: 0,
      totalSupply: 0,
      startDate: 0,
      endDate: 0,
      cost: 0,
      location: "",
      burnSet: new IPhysicalClaimCore.BurnGroup[](0),
      signer: signerForCost
    });

    // Cannot do instanceId of 0
    vm.expectRevert();
    example.initializePhysicalClaim(0, claimPs);

    // Cannot do largest instanceID
    vm.expectRevert();
    example.initializePhysicalClaim(2**56, claimPs);

    // Cannot do a burn redeem with non-matching lengths of inputs

    example.initializePhysicalClaim(instanceId, claimPs);

    uint[] memory instanceIds = new uint[](2);
    instanceIds[0] = instanceId;
    instanceIds[1] = instanceId;

    uint32[] memory physicalClaimCounts = new uint32[](1);
    physicalClaimCounts[0] = 1;

    IPhysicalClaimCore.BurnToken[][] memory burnTokens = new IPhysicalClaimCore.BurnToken[][](1);
    burnTokens[0] = new IPhysicalClaimCore.BurnToken[](1);
    burnTokens[0][0] = IPhysicalClaimCore.BurnToken({
      groupIndex: 0,
      itemIndex: 0,
      contractAddress: address(creatorCore721),
      id: 1,
      merkleProof: new bytes32[](0)
    });

    bytes[] memory data = new bytes[](1);
    data[0] = "";

    vm.expectRevert();
    example.burnRedeem(instanceIds, physicalClaimCounts, burnTokens, data);

    physicalClaimCounts = new uint32[](2);
    physicalClaimCounts[0] = 1;
    physicalClaimCounts[1] = 1;

    vm.expectRevert();
    example.burnRedeem(instanceIds, physicalClaimCounts, burnTokens, data);


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

    // Create claim initialization parameters
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      redeemAmount: 1,
      redeemedCount: 0,
      totalSupply: 0,
      startDate: 0,
      endDate: 0,
      cost: 0,
      location: "",
      burnSet: burnSet,
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
    claimPs.redeemAmount = 2;
    example.updatePhysicalClaim(instanceId, claimPs);

    // Can't update _not_ your own
    vm.stopPrank();
    vm.startPrank(other);
    vm.expectRevert(bytes("Must be admin"));
    example.updatePhysicalClaim(instanceId, claimPs);
    // Actually do a burnRedeem

    // Approve token for burning
    creatorCore721.approve(address(example), 1);

    uint[] memory instanceIds = new uint[](1);
    instanceIds[0] = instanceId;

    uint32[] memory physicalClaimCounts = new uint32[](1);
    physicalClaimCounts[0] = 1;

    IPhysicalClaimCore.BurnToken[][] memory burnTokens = new IPhysicalClaimCore.BurnToken[][](1);
    burnTokens[0] = new IPhysicalClaimCore.BurnToken[](1);
    burnTokens[0][0] = IPhysicalClaimCore.BurnToken({
      groupIndex: 0,
      itemIndex: 0,
      contractAddress: address(creatorCore721),
      id: 1,
      merkleProof: new bytes32[](0)
    });

    bytes[] memory data = new bytes[](1);
    data[0] = "";

    example.burnRedeem(instanceIds, physicalClaimCounts, burnTokens, data);

    vm.stopPrank();

    vm.startPrank(owner);
    // Mint new token to "other"
    creatorCore721.mintBase(other, "");

    vm.stopPrank();
    vm.startPrank(other);

    // Approve token for burning
    creatorCore721.approve(address(example), 2);

    burnTokens[0][0] = IPhysicalClaimCore.BurnToken({
      groupIndex: 0,
      itemIndex: 0,
      contractAddress: address(creatorCore721),
      id: 2,
      merkleProof: new bytes32[](0)
    });

    // Send a non-zero value burn
    example.burnRedeem{value: 1 ether}(instanceIds, physicalClaimCounts, burnTokens, data);

    vm.stopPrank();

    // Case where total supply is not unlimited and they use remaining supply
    vm.startPrank(owner);

    claimPs.totalSupply = 1;
    claimPs.redeemAmount = 1;
    example.initializePhysicalClaim(instanceId+1, claimPs);

    creatorCore721.mintBase(owner, "");

    // Approve token for burning
    creatorCore721.approve(address(example), 3);

    instanceIds = new uint[](1);
    instanceIds[0] = instanceId+1;

    burnTokens = new IPhysicalClaimCore.BurnToken[][](1);
    burnTokens[0] = new IPhysicalClaimCore.BurnToken[](1);
    burnTokens[0][0] = IPhysicalClaimCore.BurnToken({
      groupIndex: 0,
      itemIndex: 0,
      contractAddress: address(creatorCore721),
      id: 3,
      merkleProof: new bytes32[](0)
    });

    example.burnRedeem(instanceIds, physicalClaimCounts, burnTokens, data);

    // Case where total supply is huge, and they just redeem 1
    claimPs.totalSupply = 10;
    claimPs.redeemAmount = 1;
    example.initializePhysicalClaim(instanceId+2, claimPs);

    creatorCore721.mintBase(owner, "");

    // Approve token for burning
    creatorCore721.approve(address(example), 4);

    instanceIds = new uint[](1);
    instanceIds[0] = instanceId+2;

    burnTokens = new IPhysicalClaimCore.BurnToken[][](1);
    burnTokens[0] = new IPhysicalClaimCore.BurnToken[](1);
    burnTokens[0][0] = IPhysicalClaimCore.BurnToken({
      groupIndex: 0,
      itemIndex: 0,
      contractAddress: address(creatorCore721),
      id: 4,
      merkleProof: new bytes32[](0)
    });

    example.burnRedeem(instanceIds, physicalClaimCounts, burnTokens, data);

    vm.stopPrank();
  }

}
