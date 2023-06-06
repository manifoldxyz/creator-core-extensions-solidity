// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../contracts/metadata/ERC1155FrozenMetadataNoFilterer.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC1155Creator.sol";
import "../mocks/Mock.sol";
import "../../contracts/operatorfilterer/CreatorOperatorFilterer.sol";

contract ERC1155FrozenMetadataNoFiltererTest is Test {
  ERC1155FrozenMetadata public example;
  ERC1155Creator public creatorCore;

  address public owner = 0x6140F00e4Ff3936702E68744f2b5978885464cbB;
  address public other = 0xc78Dc443c126af6E4f6Ed540c1e740C1b5be09cd;
  address public other2 = 0x80AAC46bbd3C2FcE33681541a52CacBEd14bF425;
  address public other3 = 0x5174cD462b60c536eb51D4ceC1D561D3Ea31004F;

  address public zeroAddress = address(0);

  function setUp() public {
    vm.startPrank(owner);
    creatorCore = new ERC1155Creator("Token", "NFT");
    example = new ERC1155FrozenMetadata();

    creatorCore.registerExtension(address(example), "");

    vm.deal(owner, 10 ether);
    vm.deal(other, 10 ether);
    vm.deal(other2, 10 ether);
    vm.deal(other3, 10 ether);
    vm.stopPrank();
  }

  function testAccess() public {
    vm.startPrank(other2);

    uint[] memory ids = new uint[](1);
    ids[0] = 1;
    string[] memory uris = new string[](1);
    uris[0] = "{hey:hey}";
    address[] memory recipients = new address[](1);
    recipients[0] = other2;

    vm.expectRevert("Must be owner or admin of creator contract");
    example.mintTokenNew(address(creatorCore), recipients, ids, uris);
    vm.expectRevert("Must be owner or admin of creator contract");
    example.mintTokenExisting(address(creatorCore), recipients, ids, ids);
    vm.stopPrank();
  }

  function testBlankURI() public {
    vm.startPrank(owner);
    uint[] memory ids = new uint[](1);
    ids[0] = 1;
    string[] memory uris = new string[](1);
    uris[0] = "";
    address[] memory recipients = new address[](1);
    recipients[0] = other2;
    vm.expectRevert("Cannot mint blank string");
    example.mintTokenNew(address(creatorCore), recipients, ids, uris);
    vm.stopPrank();
  }

  function testMintToken() public {
    vm.startPrank(owner);
    uint[] memory ids = new uint[](1);
    ids[0] = 1;
    string[] memory uris = new string[](1);
    uris[0] = "{hey:hey}";
    address[] memory recipients = new address[](1);
    recipients[0] = other2;
    example.mintTokenNew(address(creatorCore), recipients, ids, uris);
    assertEq(creatorCore.balanceOf(other2, 1), 1);
    assertEq(creatorCore.uri(1), "{hey:hey}");
    vm.stopPrank();
  }

  function testCannotUpdateURI() public {
    vm.startPrank(owner);
    uint[] memory ids = new uint[](1);
    ids[0] = 1;
    string[] memory uris = new string[](1);
    uris[0] = "{hey:hey}";
    address[] memory recipients = new address[](1);
    recipients[0] = other2;
    example.mintTokenNew(address(creatorCore), recipients, ids, uris);
    assertEq(creatorCore.balanceOf(other2, 1), 1);
    assertEq(creatorCore.uri(1), "{hey:hey}");

    vm.expectRevert("Must be registered extension");
    creatorCore.setTokenURIExtension(1, "{hey2:hey2}");
    vm.stopPrank();
  }

  function testTransferRestriction() public {
    vm.startPrank(owner);
    uint[] memory ids = new uint[](1);
    ids[0] = 1;
    string[] memory uris = new string[](1);
    uris[0] = "{hey:hey}";
    address[] memory recipients = new address[](1);
    recipients[0] = owner;
    example.mintTokenNew(address(creatorCore), recipients, ids, uris);

    CreatorOperatorFilterer filter = new CreatorOperatorFilterer();
    address[] memory blockedAddresses = new address[](1);
    blockedAddresses[0] = address(owner);

    bool[] memory blocked = new bool[](1);
    blocked[0] = true;
    creatorCore.setApproveTransfer(address(filter));
    filter.configureBlockedOperators(address(creatorCore), blockedAddresses, blocked);

    creatorCore.safeTransferFrom(owner, other2, 1, 1, "0x0");
    vm.stopPrank();
  }
}
