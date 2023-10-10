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

  function testHappyCase() public {
    vm.startPrank(owner);

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
      burnSet: new IPhysicalClaimCore.BurnGroup[](0)
    });

    // Initialize the physical claim
    example.initializePhysicalClaim(instanceId, claimPs);

    // Can update
    claimPs.redeemAmount = 2;
    example.updatePhysicalClaim(instanceId, claimPs);

    // Can't update _not_ your own
    vm.stopPrank();
    vm.startPrank(other);
    vm.expectRevert(bytes("Must be admin"));
    example.updatePhysicalClaim(instanceId, claimPs);


    vm.stopPrank();
  }

}
