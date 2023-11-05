// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../contracts/physicalclaim/PhysicalClaim.sol";
import "../../contracts/physicalclaim/PhysicalClaimLib.sol";
import "../../contracts/physicalclaim/IPhysicalClaimCore.sol";
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
  address public zeroSigner = address(0);

  address public zeroAddress = address(0);

  uint256 privateKey = 0x1010101010101010101010101010101010101010101010101010101010101010;

  uint56 instanceId = 1;

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
    vm.expectRevert("AdminControl: Must be owner or admin");
    example.recover(address(creatorCore721), 1, other);
    vm.stopPrank();

    // Accidentally send token to contract
    vm.startPrank(owner);

    creatorCore721.mintBase(owner, "");
    creatorCore721.transferFrom(owner, address(example), 1);
    
    example.recover(address(creatorCore721), 1, owner);

    vm.stopPrank();
  }

  function testSupportsInterface() public {
    vm.startPrank(owner);

    bytes4 interfaceId = type(IPhysicalClaimCore).interfaceId;
    assertEq(example.supportsInterface(interfaceId), true);
    assertEq(example.supportsInterface(0xffffffff), false);

    interfaceId = type(IERC721Receiver).interfaceId;
    assertEq(example.supportsInterface(interfaceId), true);

    interfaceId = type(IERC1155Receiver).interfaceId;
    assertEq(example.supportsInterface(interfaceId), true);

    vm.stopPrank();
  }

  function testInputs() public {
    vm.startPrank(owner);

    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 0,
      startDate: 0,
      endDate: 0,
      burnSet: new IPhysicalClaimCore.BurnGroup[](0),
      variationLimits: new IPhysicalClaimCore.VariationLimit[](0),
      signer: zeroSigner
    });

    // Cannot do instanceId of 0
    vm.expectRevert(IPhysicalClaimCore.InvalidInput.selector);
    example.initializePhysicalClaim(0, claimPs);

    // Cannot do largest instanceID
    vm.expectRevert(IPhysicalClaimCore.InvalidInput.selector);
    example.initializePhysicalClaim(2**56, claimPs);

    vm.stopPrank();
  }
  
  function testHappyCaseERC721Burn() public {
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

    IPhysicalClaimCore.VariationLimit[] memory variations = new IPhysicalClaimCore.VariationLimit[](1);
    variations[0] = IPhysicalClaimCore.VariationLimit({
      id: 1,
      totalSupply: 10
    });

    // Create claim initialization parameters
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 0,
      startDate: 0,
      endDate: 0,
      burnSet: burnSet,
      variationLimits: variations,
      signer: zeroSigner
    });

    // Initialize the physical claim
    example.initializePhysicalClaim(instanceId, claimPs);

    // Can get the claim
    IPhysicalClaimCore.PhysicalClaimView memory claim = example.getPhysicalClaim(instanceId);
    assertEq(claim.paymentReceiver, owner);

    // Cannot get claim that doesn't exist
    vm.expectRevert(IPhysicalClaimCore.InvalidInstance.selector);
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
    submissions[0].instanceId = uint56(instanceId);
    submissions[0].count = 1;
    submissions[0].currentClaimCount = 0;
    submissions[0].burnTokens = burnTokens;
    submissions[0].variation = 1;
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
    
    submissions[0].currentClaimCount = 1;

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

    submissions[0].instanceId = uint56(instanceId+1);

    submissions[0].currentClaimCount = 0;

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

    submissions[0].instanceId = uint56(instanceId+2);

    submissions[0].currentClaimCount = 0;

    example.burnRedeem(submissions);

    vm.stopPrank();
  }

  function testEmptySubmissionsArray() public {
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

    IPhysicalClaimCore.VariationLimit[] memory variations = new IPhysicalClaimCore.VariationLimit[](1);
    variations[0] = IPhysicalClaimCore.VariationLimit({
      id: 1,
      totalSupply: 10
    });

    // Create claim initialization parameters
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 0,
      startDate: 0,
      endDate: 0,
      burnSet: burnSet,
      variationLimits: variations,
      signer: zeroSigner
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


    IPhysicalClaimCore.PhysicalClaimSubmission[] memory submissions = new IPhysicalClaimCore.PhysicalClaimSubmission[](0);

    vm.expectRevert(IPhysicalClaimCore.InvalidInput.selector);
    example.burnRedeem(submissions);
    vm.stopPrank();
  }

  function testGetRedemptionsCountCorrect() public {
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

    IPhysicalClaimCore.VariationLimit[] memory variations = new IPhysicalClaimCore.VariationLimit[](1);
    variations[0] = IPhysicalClaimCore.VariationLimit({
      id: 1,
      totalSupply: 10
    });

    // Create claim initialization parameters
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 0,
      startDate: 0,
      endDate: 0,
      burnSet: burnSet,
      variationLimits: variations,
      signer: zeroSigner
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
    submissions[0].instanceId = uint56(instanceId);
    submissions[0].count = 1;
    submissions[0].currentClaimCount = 0;
    submissions[0].burnTokens = burnTokens;
    submissions[0].variation = 1;
    submissions[0].data = "";

    example.burnRedeem(submissions);

    // Check get redemptions, should be 1
    uint redemptions = example.getRedemptions(instanceId, other);
    assertEq(redemptions, 1);

    vm.stopPrank();
  }

  function testGetVariationState() public {
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

    IPhysicalClaimCore.VariationLimit[] memory variations = new IPhysicalClaimCore.VariationLimit[](1);
    variations[0] = IPhysicalClaimCore.VariationLimit({
      id: 1,
      totalSupply: 10
    });

    // Create claim initialization parameters
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 0,
      startDate: 0,
      endDate: 0,
      burnSet: burnSet,
      variationLimits: variations,
      signer: zeroSigner
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
    submissions[0].instanceId = uint56(instanceId);
    submissions[0].count = 1;
    submissions[0].currentClaimCount = 0;
    submissions[0].burnTokens = burnTokens;
    submissions[0].variation = 1;
    submissions[0].data = "";

    example.burnRedeem(submissions);

    // Check get redemptions, should be 1
    IPhysicalClaimCore.VariationState memory variationStateReturn = example.getVariationState(instanceId, 1);
    assertEq(variationStateReturn.totalSupply, 10);
    assertEq(variationStateReturn.redeemedCount, 1);
    assertEq(variationStateReturn.active, true);

    vm.stopPrank();
  }

  function testERC721SafeTransferFromWithSigner() public {
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

    IPhysicalClaimCore.VariationLimit[] memory variations = new IPhysicalClaimCore.VariationLimit[](1);
    variations[0] = IPhysicalClaimCore.VariationLimit({
      id: 1,
      totalSupply: 10
    });

    // Create claim initialization parameters
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 0,
      startDate: 0,
      endDate: 0,
      burnSet: burnSet,
      variationLimits: variations,
      signer: signerForCost
    });

    // Initialize the physical claim
    example.initializePhysicalClaim(instanceId, claimPs);

    vm.stopPrank();
    vm.startPrank(other);

    // Actually do a burnRedeem
    IPhysicalClaimCore.BurnToken[] memory burnTokens = new IPhysicalClaimCore.BurnToken[](1);
    burnTokens[0] = IPhysicalClaimCore.BurnToken({
      groupIndex: 0,
      itemIndex: 0,
      contractAddress: address(creatorCore721),
      id: 1,
      merkleProof: new bytes32[](0)
    });


    IPhysicalClaimCore.PhysicalClaimSubmission[] memory submissions = new IPhysicalClaimCore.PhysicalClaimSubmission[](1);
    submissions[0].instanceId = uint56(instanceId);
    submissions[0].count = 1;
    submissions[0].currentClaimCount = 0;
    submissions[0].burnTokens = burnTokens;
    submissions[0].variation = 1;
    submissions[0].data = "";

    // Cannot burn via safeTransferFrom because we have a signer (paid burn)
    vm.expectRevert(IPhysicalClaimCore.InvalidInput.selector);
    creatorCore721.safeTransferFrom(other, address(example), 1, abi.encode(uint56(instanceId), uint256(0), "", uint8(1)));


    vm.stopPrank();

  }

  function testERC721SafeTransferFrom() public {
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

    IPhysicalClaimCore.VariationLimit[] memory variations = new IPhysicalClaimCore.VariationLimit[](1);
    variations[0] = IPhysicalClaimCore.VariationLimit({
      id: 1,
      totalSupply: 10
    });

    // Create claim initialization parameters
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 0,
      startDate: 0,
      endDate: 0,
      burnSet: burnSet,
      variationLimits: variations,
      signer: zeroSigner
    });

    // Initialize the physical claim
    example.initializePhysicalClaim(instanceId, claimPs);

    vm.stopPrank();
    vm.startPrank(other);

    // Burn via safeTransferFrom
    creatorCore721.safeTransferFrom(other, address(example), 1, abi.encode(uint56(instanceId), uint256(0), "", uint8(1)));

    assertEq(creatorCore721.balanceOf(address(other)), 0);

    vm.stopPrank();

  }

  function testERC721SafeTransferFromBadLengthData() public {
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

    IPhysicalClaimCore.VariationLimit[] memory variations = new IPhysicalClaimCore.VariationLimit[](1);
    variations[0] = IPhysicalClaimCore.VariationLimit({
      id: 1,
      totalSupply: 10
    });

    // Create claim initialization parameters
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 0,
      startDate: 0,
      endDate: 0,
      burnSet: burnSet,
      variationLimits: variations,
      signer: zeroSigner
    });

    // Initialize the physical claim
    example.initializePhysicalClaim(instanceId, claimPs);

    vm.stopPrank();
    vm.startPrank(other);

    vm.expectRevert(IPhysicalClaimCore.InvalidData.selector);
    creatorCore721.safeTransferFrom(other, address(example), 1, "a");

    vm.stopPrank();

  }

  function testIdempotencyViaIncorrectCurrentClaimCount() public {
    vm.startPrank(owner);

    // Mint token 2 to other
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
      maxTokenId: 2,
      merkleRoot: ""
    });

    IPhysicalClaimCore.BurnGroup[] memory burnSet = new IPhysicalClaimCore.BurnGroup[](1);
    burnSet[0] = IPhysicalClaimCore.BurnGroup({
        requiredCount: 1,
        items: burnItems
      });

    IPhysicalClaimCore.VariationLimit[] memory variations = new IPhysicalClaimCore.VariationLimit[](1);
    variations[0] = IPhysicalClaimCore.VariationLimit({
      id: 1,
      totalSupply: 10
    });

    // Create claim initialization parameters
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 0,
      startDate: 0,
      endDate: 0,
      burnSet: burnSet,
      variationLimits: variations,
      signer: zeroSigner
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
    submissions[0].instanceId = uint56(instanceId);
    submissions[0].count = 1;
    submissions[0].currentClaimCount = 0;
    submissions[0].burnTokens = burnTokens;
    submissions[0].variation = 1;
    submissions[0].data = "";

    example.burnRedeem(submissions);

    // Idempotency test, wrong currentClaimCount
    submissions[0].burnTokens[0].id = 2;
    vm.expectRevert(IPhysicalClaimCore.InvalidInput.selector);
    example.burnRedeem(submissions);


    vm.stopPrank();

  }

  function testCannotInitializeTwice() public {
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

    IPhysicalClaimCore.VariationLimit[] memory variations = new IPhysicalClaimCore.VariationLimit[](1);
    variations[0] = IPhysicalClaimCore.VariationLimit({
      id: 1,
      totalSupply: 10
    });

    // Create claim initialization parameters
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 0,
      startDate: 0,
      endDate: 0,

      burnSet: burnSet,
      variationLimits: variations,
      signer: zeroSigner
    });

    // Initialize the physical claim
    example.initializePhysicalClaim(instanceId, claimPs);

    vm.expectRevert(IPhysicalClaimCore.InvalidInstance.selector);
    example.initializePhysicalClaim(instanceId, claimPs);
    
    vm.stopPrank();
  }

  function testCannotInitializeAfterDeprecation() public {
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

    IPhysicalClaimCore.VariationLimit[] memory variations = new IPhysicalClaimCore.VariationLimit[](1);
    variations[0] = IPhysicalClaimCore.VariationLimit({
      id: 1,
      totalSupply: 10
    });

    // Create claim initialization parameters
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 0,
      startDate: 0,
      endDate: 0,

      burnSet: burnSet,
      variationLimits: variations,
      signer: zeroSigner
    });

    // Initialize the physical claim
    example.initializePhysicalClaim(instanceId, claimPs);

    example.deprecate(true);

    vm.expectRevert(IPhysicalClaimCore.ContractDeprecated.selector);
    example.initializePhysicalClaim(instanceId, claimPs);

    example.deprecate(false);

    example.initializePhysicalClaim(instanceId+1, claimPs);

    vm.stopPrank();

    // Cannot deprecate if now admin
    vm.startPrank(other);
    vm.expectRevert(bytes("AdminControl: Must be owner or admin"));
    example.deprecate(true);
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

    IPhysicalClaimCore.VariationLimit[] memory variations = new IPhysicalClaimCore.VariationLimit[](1);
    variations[0] = IPhysicalClaimCore.VariationLimit({
      id: 1,
      totalSupply: 100
    });

    // Create claim initialization parameters. Total supply is 1 so they will use the whole supply
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 1,
      startDate: 0,
      endDate: 0,

      burnSet: burnSet,
      variationLimits: variations,
      signer: zeroSigner
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
    submissions[0].instanceId = uint56(instanceId);
    submissions[0].count = 1;
    submissions[0].currentClaimCount = 0;
    submissions[0].burnTokens = burnTokens;
    submissions[0].variation = 1;
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

    submissions[0].instanceId = uint56(instanceId);
    submissions[0].count = 1;
    submissions[0].currentClaimCount = 1;
    submissions[0].burnTokens = burnTokens;
    submissions[0].variation = 1;
    submissions[0].data = "";

    vm.expectRevert(IPhysicalClaimCore.InvalidRedeemAmount.selector); // should revert cause none remaining and the setting is to revert it...
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

    IPhysicalClaimCore.VariationLimit[] memory variations = new IPhysicalClaimCore.VariationLimit[](1);
    variations[0] = IPhysicalClaimCore.VariationLimit({
      id: 1,
      totalSupply: 1
    });

    // Create claim initialization parameters. Total supply is 1 so they will use the whole supply
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 1,
      startDate: 0,
      endDate: 0,

      burnSet: burnSet,
      variationLimits: variations,
      signer: zeroSigner
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
    submissions[0].instanceId = uint56(instanceId);
    submissions[0].count = 1;
    submissions[0].currentClaimCount = 0;
    submissions[0].burnTokens = burnTokens;
    submissions[0].variation = 1;
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

    IPhysicalClaimCore.VariationLimit[] memory variations = new IPhysicalClaimCore.VariationLimit[](1);
    variations[0] = IPhysicalClaimCore.VariationLimit({
      id: 1,
      totalSupply: 10
    });

    // Create claim initialization parameters. Total supply is 1 so they will use the whole supply
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 2,
      startDate: 0,
      endDate: 0,

      burnSet: burnSet,
      variationLimits: variations,
      signer: zeroSigner
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
    submissions[0].instanceId = uint56(instanceId);
    submissions[0].count = 1;
    submissions[0].currentClaimCount = 0;
    submissions[0].burnTokens = burnTokens;
    submissions[0].variation = 1;
    submissions[0].data = "";

    IPhysicalClaimCore.BurnToken[] memory burnTokens2 = new IPhysicalClaimCore.BurnToken[](1);
    burnTokens2[0] = IPhysicalClaimCore.BurnToken({
      groupIndex: 0,
      itemIndex: 0,
      contractAddress: address(creatorCore721),
      id: 2,
      merkleProof: new bytes32[](0)
    });
    submissions[1].instanceId = uint56(instanceId);
    submissions[1].count = 1;
    submissions[1].currentClaimCount = 1;
    submissions[1].burnTokens = burnTokens2;
    submissions[1].variation = 1;
    submissions[1].data = "";

    example.burnRedeem(submissions);

    vm.stopPrank();
  }

  function testPhysicalClaimCount2() public {
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

    IPhysicalClaimCore.VariationLimit[] memory variations = new IPhysicalClaimCore.VariationLimit[](1);
    variations[0] = IPhysicalClaimCore.VariationLimit({
      id: 1,
      totalSupply: 1
    });

    // Create claim initialization parameters. Total supply is 1 so they will use the whole supply
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 2,
      startDate: 0,
      endDate: 0,

      burnSet: burnSet,
      variationLimits: variations,
      signer: zeroSigner
    });

    // Initialize the physical claim
    example.initializePhysicalClaim(instanceId, claimPs);

    vm.stopPrank();
    vm.startPrank(other);

    // Approve tokens for burning
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
      itemIndex: 0,
      contractAddress: address(creatorCore721),
      id: 2,
      merkleProof: new bytes32[](0)
    });

    IPhysicalClaimCore.PhysicalClaimSubmission[] memory submissions = new IPhysicalClaimCore.PhysicalClaimSubmission[](1);
    submissions[0].instanceId = uint56(instanceId);
    submissions[0].count = 2;
    submissions[0].currentClaimCount = 0;
    submissions[0].burnTokens = burnTokens;
    submissions[0].variation = 1;
    submissions[0].data = "";

    assertEq(creatorCore721.balanceOf(address(other)), 2);

    vm.expectRevert(IPhysicalClaimCore.InvalidBurnAmount.selector);
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

    IPhysicalClaimCore.VariationLimit[] memory variations = new IPhysicalClaimCore.VariationLimit[](1);
    variations[0] = IPhysicalClaimCore.VariationLimit({
      id: 1,
      totalSupply: 1
    });

    // Create claim initialization parameters. Total supply is 1 so they will use the whole supply
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 0,
      startDate: 0,
      endDate: 0,

      burnSet: burnSet,
      variationLimits: variations,
      signer: zeroSigner
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
    submissions[0].instanceId = uint56(instanceId);
    submissions[0].count = 2;
    submissions[0].currentClaimCount = 0;
    submissions[0].burnTokens = burnTokens;
    submissions[0].variation = 1;
    submissions[0].data = "";

    example.burnRedeem(submissions);
    vm.stopPrank();
  }

  function testERC1155() public {
    vm.startPrank(owner);

    // Mint 10 tokens to other
    address[] memory recipientsInput = new address[](1);
    recipientsInput[0] = other;
    uint[] memory mintsInput = new uint[](1);
    mintsInput[0] = 10;
    string[] memory urisInput = new string[](1);
    urisInput[0] = "";
    // base mint something in between
    creatorCore1155.mintBaseNew(recipientsInput, mintsInput, urisInput);

    IPhysicalClaimCore.BurnItem[] memory burnItems = new IPhysicalClaimCore.BurnItem[](1);
    burnItems[0] = IPhysicalClaimCore.BurnItem({
      validationType: IPhysicalClaimCore.ValidationType.CONTRACT,
      contractAddress: address(creatorCore1155),
      tokenSpec: IPhysicalClaimCore.TokenSpec.ERC1155,
      burnSpec: IPhysicalClaimCore.BurnSpec.MANIFOLD,
      amount: 3,
      minTokenId: 1,
      maxTokenId: 3,
      merkleRoot: ""
    });

    IPhysicalClaimCore.BurnGroup[] memory burnSet = new IPhysicalClaimCore.BurnGroup[](1);
    burnSet[0] = IPhysicalClaimCore.BurnGroup({
      requiredCount: 1,
      items: burnItems
    });

    IPhysicalClaimCore.VariationLimit[] memory variations = new IPhysicalClaimCore.VariationLimit[](1);
    variations[0] = IPhysicalClaimCore.VariationLimit({
      id: 1,
      totalSupply: 2
    });

    // Create claim initialization parameters. Total supply is 1 so they will use the whole supply
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 0,
      startDate: 0,
      endDate: 0,

      burnSet: burnSet,
      variationLimits: variations,
      signer: zeroSigner
    });

    // Initialize the physical claim
    example.initializePhysicalClaim(instanceId, claimPs);

    vm.stopPrank();
    vm.startPrank(other);

    // Approve token for burning
    creatorCore1155.setApprovalForAll(address(example), true);

    IPhysicalClaimCore.BurnToken[] memory burnTokens = new IPhysicalClaimCore.BurnToken[](1);
    burnTokens[0] = IPhysicalClaimCore.BurnToken({
      groupIndex: 0,
      itemIndex: 0,
      contractAddress: address(creatorCore1155),
      id: 1,
      merkleProof: new bytes32[](0)
    });

    IPhysicalClaimCore.PhysicalClaimSubmission[] memory submissions = new IPhysicalClaimCore.PhysicalClaimSubmission[](1);
    submissions[0].instanceId = uint56(instanceId);
    submissions[0].count = 2;
    submissions[0].currentClaimCount = 0;
    submissions[0].burnTokens = burnTokens;
    submissions[0].variation = 1;
    submissions[0].data = "";

    example.burnRedeem(submissions);

    assertEq(creatorCore1155.balanceOf(address(other), 1), 4);
    vm.stopPrank();
  }

  function testERC1155SafeTransferFrom() public {
    vm.startPrank(owner);

    // Mint 10 tokens to other
    address[] memory recipientsInput = new address[](1);
    recipientsInput[0] = other;
    uint[] memory mintsInput = new uint[](1);
    mintsInput[0] = 10;
    string[] memory urisInput = new string[](1);
    urisInput[0] = "";
    // base mint something in between
    creatorCore1155.mintBaseNew(recipientsInput, mintsInput, urisInput);

    IPhysicalClaimCore.BurnItem[] memory burnItems = new IPhysicalClaimCore.BurnItem[](1);
    burnItems[0] = IPhysicalClaimCore.BurnItem({
      validationType: IPhysicalClaimCore.ValidationType.CONTRACT,
      contractAddress: address(creatorCore1155),
      tokenSpec: IPhysicalClaimCore.TokenSpec.ERC1155,
      burnSpec: IPhysicalClaimCore.BurnSpec.MANIFOLD,
      amount: 3,
      minTokenId: 1,
      maxTokenId: 3,
      merkleRoot: ""
    });

    IPhysicalClaimCore.BurnGroup[] memory burnSet = new IPhysicalClaimCore.BurnGroup[](1);
    burnSet[0] = IPhysicalClaimCore.BurnGroup({
      requiredCount: 1,
      items: burnItems
    });

    IPhysicalClaimCore.VariationLimit[] memory variations = new IPhysicalClaimCore.VariationLimit[](1);
    variations[0] = IPhysicalClaimCore.VariationLimit({
      id: 1,
      totalSupply: 2
    });

    // Create claim initialization parameters. Total supply is 1 so they will use the whole supply
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 0,
      startDate: 0,
      endDate: 0,

      burnSet: burnSet,
      variationLimits: variations,
      signer: zeroSigner
    });

    // Initialize the physical claim
    example.initializePhysicalClaim(instanceId, claimPs);

    vm.stopPrank();
    vm.startPrank(other);

    // Burn via safeTransferFrom
    creatorCore1155.safeTransferFrom(address(other), address(example), 1, 6, abi.encode(uint56(instanceId), uint16(2), uint256(0), "", uint8(1)));

    assertEq(creatorCore1155.balanceOf(address(other), 1), 4);
    vm.stopPrank();
  }

  function testTransfer721To1155Claim() public {
    vm.startPrank(owner);

    // Mint 10 tokens to other
    address[] memory recipientsInput = new address[](1);
    recipientsInput[0] = other;
    uint[] memory mintsInput = new uint[](1);
    mintsInput[0] = 10;
    string[] memory urisInput = new string[](1);
    urisInput[0] = "";
    // base mint something in between
    creatorCore1155.mintBaseNew(recipientsInput, mintsInput, urisInput);

    // Mint 721 to other
    creatorCore721.mintBase(other, "");

    IPhysicalClaimCore.BurnItem[] memory burnItems = new IPhysicalClaimCore.BurnItem[](1);
    burnItems[0] = IPhysicalClaimCore.BurnItem({
      validationType: IPhysicalClaimCore.ValidationType.CONTRACT,
      contractAddress: address(creatorCore1155),
      tokenSpec: IPhysicalClaimCore.TokenSpec.ERC1155,
      burnSpec: IPhysicalClaimCore.BurnSpec.MANIFOLD,
      amount: 3,
      minTokenId: 1,
      maxTokenId: 3,
      merkleRoot: ""
    });

    IPhysicalClaimCore.BurnGroup[] memory burnSet = new IPhysicalClaimCore.BurnGroup[](1);
    burnSet[0] = IPhysicalClaimCore.BurnGroup({
      requiredCount: 1,
      items: burnItems
    });

    IPhysicalClaimCore.VariationLimit[] memory variations = new IPhysicalClaimCore.VariationLimit[](1);
    variations[0] = IPhysicalClaimCore.VariationLimit({
      id: 1,
      totalSupply: 2
    });

    // Create claim initialization parameters. Total supply is 1 so they will use the whole supply
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 0,
      startDate: 0,
      endDate: 0,

      burnSet: burnSet,
      variationLimits: variations,
      signer: zeroSigner
    });

    // Initialize the physical claim
    example.initializePhysicalClaim(instanceId, claimPs);

    vm.stopPrank();
    vm.startPrank(other);

    // Transfer in the 721
    vm.expectRevert(IPhysicalClaimCore.InvalidInput.selector);
    creatorCore721.safeTransferFrom(other, address(example), 1, abi.encode(uint56(instanceId), uint256(0), "", uint8(1)));
    vm.stopPrank();
  }


  function testERC1155SafeTransferFromBadAmount() public {
    vm.startPrank(owner);

    // Mint 10 tokens to other
    address[] memory recipientsInput = new address[](1);
    recipientsInput[0] = other;
    uint[] memory mintsInput = new uint[](1);
    mintsInput[0] = 10;
    string[] memory urisInput = new string[](1);
    urisInput[0] = "";
    // base mint something in between
    creatorCore1155.mintBaseNew(recipientsInput, mintsInput, urisInput);

    IPhysicalClaimCore.BurnItem[] memory burnItems = new IPhysicalClaimCore.BurnItem[](1);
    burnItems[0] = IPhysicalClaimCore.BurnItem({
      validationType: IPhysicalClaimCore.ValidationType.CONTRACT,
      contractAddress: address(creatorCore1155),
      tokenSpec: IPhysicalClaimCore.TokenSpec.ERC1155,
      burnSpec: IPhysicalClaimCore.BurnSpec.MANIFOLD,
      amount: 3,
      minTokenId: 1,
      maxTokenId: 3,
      merkleRoot: ""
    });

    IPhysicalClaimCore.BurnGroup[] memory burnSet = new IPhysicalClaimCore.BurnGroup[](1);
    burnSet[0] = IPhysicalClaimCore.BurnGroup({
      requiredCount: 1,
      items: burnItems
    });

    IPhysicalClaimCore.VariationLimit[] memory variations = new IPhysicalClaimCore.VariationLimit[](1);
    variations[0] = IPhysicalClaimCore.VariationLimit({
      id: 1,
      totalSupply: 2
    });

    // Create claim initialization parameters. Total supply is 1 so they will use the whole supply
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 0,
      startDate: 0,
      endDate: 0,

      burnSet: burnSet,
      variationLimits: variations,
      signer: zeroSigner
    });

    // Initialize the physical claim
    example.initializePhysicalClaim(instanceId, claimPs);

    vm.stopPrank();
    vm.startPrank(other);

    // Burn via safeTransferFrom but with not enough tokens
    // Note: this will revert with a non-ERC1155Receiver implementer error
    vm.expectRevert("ERC1155: transfer to non-ERC1155Receiver implementer");
    creatorCore1155.safeTransferFrom(address(other), address(example), 1, 4, abi.encode(uint56(instanceId), uint16(2), uint256(0), "", uint8(1)));

    assertEq(creatorCore1155.balanceOf(address(other), 1), 10);
    vm.stopPrank();
  }

  function testERC1155SafeTransferWithSigner() public {
    vm.startPrank(owner);

    // Mint 10 tokens to other
    address[] memory recipientsInput = new address[](1);
    recipientsInput[0] = other;
    uint[] memory mintsInput = new uint[](1);
    mintsInput[0] = 10;
    string[] memory urisInput = new string[](1);
    urisInput[0] = "";
    // base mint something in between
    creatorCore1155.mintBaseNew(recipientsInput, mintsInput, urisInput);

    IPhysicalClaimCore.BurnItem[] memory burnItems = new IPhysicalClaimCore.BurnItem[](1);
    burnItems[0] = IPhysicalClaimCore.BurnItem({
      validationType: IPhysicalClaimCore.ValidationType.CONTRACT,
      contractAddress: address(creatorCore1155),
      tokenSpec: IPhysicalClaimCore.TokenSpec.ERC1155,
      burnSpec: IPhysicalClaimCore.BurnSpec.MANIFOLD,
      amount: 3,
      minTokenId: 1,
      maxTokenId: 3,
      merkleRoot: ""
    });

    IPhysicalClaimCore.BurnGroup[] memory burnSet = new IPhysicalClaimCore.BurnGroup[](1);
    burnSet[0] = IPhysicalClaimCore.BurnGroup({
      requiredCount: 1,
      items: burnItems
    });

    IPhysicalClaimCore.VariationLimit[] memory variations = new IPhysicalClaimCore.VariationLimit[](1);
    variations[0] = IPhysicalClaimCore.VariationLimit({
      id: 1,
      totalSupply: 2
    });

    // Create claim initialization parameters. Total supply is 1 so they will use the whole supply
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 0,
      startDate: 0,
      endDate: 0,

      burnSet: burnSet,
      variationLimits: variations,
      signer: signerForCost
    });

    // Initialize the physical claim
    example.initializePhysicalClaim(instanceId, claimPs);

    vm.stopPrank();
    vm.startPrank(other);

    // Burn via safeTransferFrom but with not enough tokens
    // Note: this will revert with a non-ERC1155Receiver implementer error
    vm.expectRevert("ERC1155: transfer to non-ERC1155Receiver implementer");
    creatorCore1155.safeTransferFrom(address(other), address(example), 1, 6, abi.encode(uint56(instanceId), uint16(2), uint256(0), "", uint8(1)));

    assertEq(creatorCore1155.balanceOf(address(other), 1), 10);
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

    IPhysicalClaimCore.VariationLimit[] memory variations = new IPhysicalClaimCore.VariationLimit[](1);
    variations[0] = IPhysicalClaimCore.VariationLimit({
      id: 1,
      totalSupply: 1
    });

    // Create claim initialization parameters. Total supply is 1 so they will use the whole supply
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 0,
      startDate: 0,
      endDate: 0,

      burnSet: burnSet,
      variationLimits: variations,
      signer: zeroSigner
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
    submissions[0].instanceId = uint56(instanceId);
    submissions[0].count = 1;
    submissions[0].currentClaimCount = 0;
    submissions[0].burnTokens = burnTokens;
    submissions[0].variation = 1;
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

    IPhysicalClaimCore.VariationLimit[] memory variations = new IPhysicalClaimCore.VariationLimit[](1);
    variations[0] = IPhysicalClaimCore.VariationLimit({
      id: 1,
      totalSupply: 1
    });

    // Create claim initialization parameters. Total supply is 1 so they will use the whole supply
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 0,
      startDate: 0,
      endDate: 0,

      burnSet: burnSet,
      variationLimits: variations,
      signer: zeroSigner
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
    submissions[0].instanceId = uint56(instanceId);
    submissions[0].count = 1;
    submissions[0].currentClaimCount = 0;
    submissions[0].burnTokens = burnTokens;
    submissions[0].variation = 1;
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

    IPhysicalClaimCore.VariationLimit[] memory variations = new IPhysicalClaimCore.VariationLimit[](1);
    variations[0] = IPhysicalClaimCore.VariationLimit({
      id: 1,
      totalSupply: 1
    });

    // Create claim initialization parameters. Total supply is 1 so they will use the whole supply
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 0,
      startDate: 0,
      endDate: 0,

      burnSet: burnSet,
      variationLimits: variations,
      signer: zeroSigner
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
    submissions[0].instanceId = uint56(instanceId);
    submissions[0].count = 1;
    submissions[0].currentClaimCount = 0;
    submissions[0].burnTokens = burnTokens;
    submissions[0].variation = 1;
    submissions[0].data = "";

    vm.expectRevert(PhysicalClaimLib.InvalidBurnToken.selector);
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

    IPhysicalClaimCore.VariationLimit[] memory variations = new IPhysicalClaimCore.VariationLimit[](1);
    variations[0] = IPhysicalClaimCore.VariationLimit({
      id: 1,
      totalSupply: 1
    });

    // Create claim initialization parameters. Total supply is 1 so they will use the whole supply
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 0,
      startDate: 0,
      endDate: 0,

      burnSet: burnSet,
      variationLimits: variations,
      signer: zeroSigner
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
    submissions[0].instanceId = uint56(instanceId);
    submissions[0].count = 1;
    submissions[0].currentClaimCount = 0;
    submissions[0].burnTokens = burnTokens;
    submissions[0].variation = 1;
    submissions[0].data = "";

    vm.expectRevert(abi.encodePacked(IPhysicalClaimCore.InvalidToken.selector, uint256(1)));
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

    IPhysicalClaimCore.VariationLimit[] memory variations = new IPhysicalClaimCore.VariationLimit[](1);
    variations[0] = IPhysicalClaimCore.VariationLimit({
      id: 1,
      totalSupply: 1
    });

    // Create claim initialization parameters. Total supply is 1 so they will use the whole supply
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(0),
      totalSupply: 0,
      startDate: 0,
      endDate: 0,

      burnSet: burnSet,
      variationLimits: variations,
      signer: zeroSigner
    });

    // Initialize the physical claim
    vm.expectRevert(PhysicalClaimLib.InvalidPaymentReceiver.selector);
    example.initializePhysicalClaim(instanceId, claimPs);

    claimPs.paymentReceiver = payable(owner);
    claimPs.startDate = 2;
    claimPs.endDate = 1;

    vm.expectRevert(PhysicalClaimLib.InvalidDates.selector);
    example.initializePhysicalClaim(instanceId, claimPs);

    claimPs.startDate = 0;
    claimPs.endDate = 0;

    burnSet[0].requiredCount = 0;
    claimPs.burnSet = burnSet;

    vm.expectRevert(IPhysicalClaimCore.InvalidInput.selector);
    example.initializePhysicalClaim(instanceId, claimPs);

    burnSet[0].requiredCount = 1;
    burnSet[0].items = new IPhysicalClaimCore.BurnItem[](0);
    claimPs.burnSet = burnSet;

    vm.expectRevert(IPhysicalClaimCore.InvalidInput.selector);
    example.initializePhysicalClaim(instanceId, claimPs);

    vm.stopPrank();
  }

  function testSend0EthButHasCost() public {
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

    IPhysicalClaimCore.VariationLimit[] memory variations = new IPhysicalClaimCore.VariationLimit[](1);
    variations[0] = IPhysicalClaimCore.VariationLimit({
      id: 1,
      totalSupply: 1
    });

    // Create claim initialization parameters. Total supply is 1 so they will use the whole supply
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 0,
      startDate: 0,
      endDate: 0,
      burnSet: burnSet,
      variationLimits: variations,
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
    submissions[0].instanceId = uint56(instanceId);
    submissions[0].count = 1;
    submissions[0].currentClaimCount = 0;
    submissions[0].burnTokens = burnTokens;
    submissions[0].totalCost = 1;
    submissions[0].variation = 1;
    submissions[0].data = "";

    vm.expectRevert(IPhysicalClaimCore.InvalidPaymentAmount.selector);
    example.burnRedeem(submissions);
    vm.stopPrank();
  }

  function testRightAmountOfEthNoSignatureTho() public {
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

    IPhysicalClaimCore.VariationLimit[] memory variations = new IPhysicalClaimCore.VariationLimit[](1);
    variations[0] = IPhysicalClaimCore.VariationLimit({
      id: 1,
      totalSupply: 1
    });

    // Create claim initialization parameters. Total supply is 1 so they will use the whole supply
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 0,
      startDate: 0,
      endDate: 0,
      burnSet: burnSet,
      variationLimits: variations,
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
    submissions[0].instanceId = uint56(instanceId);
    submissions[0].count = 1;
    submissions[0].currentClaimCount = 0;
    submissions[0].burnTokens = burnTokens;
    submissions[0].totalCost = 1;
    submissions[0].variation = 1;
    submissions[0].data = "";

    vm.expectRevert("ECDSA: invalid signature length");
    example.burnRedeem{value: 1}(submissions);
    vm.stopPrank();
  }

  function testWrongSigner() public {
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

    IPhysicalClaimCore.VariationLimit[] memory variations = new IPhysicalClaimCore.VariationLimit[](1);
    variations[0] = IPhysicalClaimCore.VariationLimit({
      id: 1,
      totalSupply: 1
    });

    // Create claim initialization parameters. Total supply is 1 so they will use the whole supply
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 0,
      startDate: 0,
      endDate: 0,
      burnSet: burnSet,
      variationLimits: variations,
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
    submissions[0].instanceId = uint56(instanceId);
    submissions[0].count = 1;
    submissions[0].currentClaimCount = 0;
    submissions[0].burnTokens = burnTokens;
    submissions[0].totalCost = 1;
    submissions[0].variation = 1;
    submissions[0].data = "";
    submissions[0].message = "Hello";
    submissions[0].nonce = "";

    bytes32 message = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", instanceId, uint(1)));

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, message);
    bytes memory signature = abi.encodePacked(r, s, v);

    submissions[0].signature = signature;

    vm.expectRevert(IPhysicalClaimCore.InvalidSignature.selector);
    example.burnRedeem{value: 1}(submissions);
    vm.stopPrank();
  }

  function testRightSignerWrongMessage() public {
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

    IPhysicalClaimCore.VariationLimit[] memory variations = new IPhysicalClaimCore.VariationLimit[](1);
    variations[0] = IPhysicalClaimCore.VariationLimit({
      id: 1,
      totalSupply: 1
    });

    // Create claim initialization parameters. Total supply is 1 so they will use the whole supply
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 0,
      startDate: 0,
      endDate: 0,
      burnSet: burnSet,
      variationLimits: variations,
      signer: vm.addr(privateKey)
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
    submissions[0].instanceId = uint56(instanceId);
    submissions[0].count = 1;
    submissions[0].currentClaimCount = 0;
    submissions[0].burnTokens = burnTokens;
    submissions[0].totalCost = 1;
    submissions[0].variation = 1;
    submissions[0].data = "";
    submissions[0].message = "Hello";
    submissions[0].nonce = "";

    bytes32 message = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", instanceId));

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, message);
    bytes memory signature = abi.encodePacked(r, s, v);

    submissions[0].signature = signature;

    vm.expectRevert(IPhysicalClaimCore.InvalidSignature.selector);
    example.burnRedeem{value: 1}(submissions);
    vm.stopPrank();
  }

  function testAllCorrectWithPayment() public {
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

    IPhysicalClaimCore.VariationLimit[] memory variations = new IPhysicalClaimCore.VariationLimit[](1);
    variations[0] = IPhysicalClaimCore.VariationLimit({
      id: 1,
      totalSupply: 1
    });

    // Create claim initialization parameters. Total supply is 1 so they will use the whole supply
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 0,
      startDate: 0,
      endDate: 0,
      burnSet: burnSet,
      variationLimits: variations,
      signer: vm.addr(privateKey)
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
    submissions[0].instanceId = uint56(instanceId);
    submissions[0].count = 1;
    submissions[0].currentClaimCount = 0;
    submissions[0].burnTokens = burnTokens;
    submissions[0].totalCost = 1;
    submissions[0].variation = 1;
    submissions[0].data = "";
    submissions[0].nonce = "abcd";

    bytes32 message = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", instanceId, uint(1)));

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, message);
    bytes memory signature = abi.encodePacked(r, s, v);

    submissions[0].signature = signature;
    submissions[0].message = message;

    example.burnRedeem{value: 1}(submissions);
    vm.stopPrank();
  }

  function testReUseNonce() public {
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

    IPhysicalClaimCore.VariationLimit[] memory variations = new IPhysicalClaimCore.VariationLimit[](1);
    variations[0] = IPhysicalClaimCore.VariationLimit({
      id: 1,
      totalSupply: 2
    });

    // Create claim initialization parameters. Total supply is 1 so they will use the whole supply
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 0,
      startDate: 0,
      endDate: 0,
      burnSet: burnSet,
      variationLimits: variations,
      signer: vm.addr(privateKey)
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
    submissions[0].instanceId = uint56(instanceId);
    submissions[0].count = 1;
    submissions[0].currentClaimCount = 0;
    submissions[0].burnTokens = burnTokens;
    submissions[0].totalCost = 1;
    submissions[0].variation = 1;
    submissions[0].data = "";
    submissions[0].nonce = "abcd";

    bytes32 message = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", instanceId, uint(1)));

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, message);
    bytes memory signature = abi.encodePacked(r, s, v);

    submissions[0].signature = signature;
    submissions[0].message = message;

    // Fine
    example.burnRedeem{value: 1}(submissions);

    // Reuse nonce
    submissions[0].currentClaimCount = 1;
    submissions[0].burnTokens[0].id = 2;
    vm.expectRevert("Cannot replay transaction");
    example.burnRedeem{value: 1}(submissions);
    vm.stopPrank();
  }

  function testChangeVariationsToLower() public {
    vm.startPrank(owner);

    // Mint 2 tokens to other
    creatorCore721.mintBase(other, "");
    creatorCore721.mintBase(other, "");
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

    IPhysicalClaimCore.VariationLimit[] memory variations = new IPhysicalClaimCore.VariationLimit[](1);
    variations[0] = IPhysicalClaimCore.VariationLimit({
      id: 1,
      totalSupply: 10
    });

    // Create claim initialization parameters. Total supply is 1 so they will use the whole supply
    IPhysicalClaimCore.PhysicalClaimParameters memory claimPs = IPhysicalClaimCore.PhysicalClaimParameters({
      paymentReceiver: payable(owner),
      totalSupply: 20,
      startDate: 0,
      endDate: 0,

      burnSet: burnSet,
      variationLimits: variations,
      signer: zeroSigner
    });

    // Initialize the physical claim
    example.initializePhysicalClaim(instanceId, claimPs);

    vm.stopPrank();
    vm.startPrank(other);

    // Approve tokens for burning
    creatorCore721.approve(address(example), 1);
    creatorCore721.approve(address(example), 2);
    creatorCore721.approve(address(example), 3);
    creatorCore721.approve(address(example), 4);

    IPhysicalClaimCore.BurnToken[] memory burnTokens = new IPhysicalClaimCore.BurnToken[](1);
    burnTokens[0] = IPhysicalClaimCore.BurnToken({
      groupIndex: 0,
      itemIndex: 0,
      contractAddress: address(creatorCore721),
      id: 1,
      merkleProof: new bytes32[](0)
    });

    IPhysicalClaimCore.PhysicalClaimSubmission[] memory submissions = new IPhysicalClaimCore.PhysicalClaimSubmission[](1);
    submissions[0].instanceId = uint56(instanceId);
    submissions[0].count = 1;
    submissions[0].currentClaimCount = 0;
    submissions[0].burnTokens = burnTokens;
    submissions[0].variation = 1;
    submissions[0].data = "";

    assertEq(creatorCore721.balanceOf(address(other)), 4);

    // Burn 1
    example.burnRedeem(submissions);

    assertEq(creatorCore721.balanceOf(address(other)), 3);
    
    // Burn another
    burnTokens[0].id = 2;
    submissions[0].currentClaimCount = 1;
    example.burnRedeem(submissions);

    assertEq(creatorCore721.balanceOf(address(other)), 2);
    // Burn another
    burnTokens[0].id = 3;
    submissions[0].currentClaimCount = 2;
    example.burnRedeem(submissions);

    // Change variations to lower...
    vm.stopPrank();
    vm.startPrank(owner);

    variations[0].totalSupply = 2;
    example.updatePhysicalClaim(instanceId, claimPs);

    // Get variations...
    // Check get redemptions, should be 3
    IPhysicalClaimCore.VariationState memory variationStateReturn = example.getVariationState(instanceId, 1);

    // Total Supply isn't "lower" than redeem count, even though we "lowered" it to 2
    assertEq(variationStateReturn.totalSupply, 3);
    assertEq(variationStateReturn.redeemedCount, 3);
    assertEq(variationStateReturn.active, true);
    // Total supply still unchanged
    IPhysicalClaimCore.PhysicalClaimView memory claim = example.getPhysicalClaim(instanceId);
    assertEq(claim.totalSupply, 20);

    vm.stopPrank();
    vm.startPrank(other);

    // Cant do another redemption
    burnTokens[0].id = 4;
    submissions[0].currentClaimCount = 3;
    vm.expectRevert(IPhysicalClaimCore.InvalidRedeemAmount.selector);
    example.burnRedeem(submissions);

    // If owner sets to unlimited for that variation, they can

    vm.stopPrank();
    vm.startPrank(owner);

    variations[0].totalSupply = 0;
    example.updatePhysicalClaim(instanceId, claimPs);

    // Check get redemptions, should be 3
    variationStateReturn = example.getVariationState(instanceId, 1);
    assertEq(variationStateReturn.totalSupply, 0);
    assertEq(variationStateReturn.redeemedCount, 3);
    assertEq(variationStateReturn.active, true);

    vm.stopPrank();
    vm.startPrank(other);

    example.burnRedeem(submissions);

    // Check get redemptions, should be 4
    variationStateReturn = example.getVariationState(instanceId, 1);
    assertEq(variationStateReturn.totalSupply, 0);
    assertEq(variationStateReturn.redeemedCount, 4);
    assertEq(variationStateReturn.active, true);


    vm.stopPrank();
  }
}
