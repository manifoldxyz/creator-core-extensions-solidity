// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../contracts/metadata/ERC721FrozenMetadata.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC721Creator.sol";
import "../mocks/Mock.sol";

contract ERC721FrozenMetadataTest is Test {
  ERC721FrozenMetadata public example;
  ERC721Creator public creatorCore;

  address public owner = 0x6140F00e4Ff3936702E68744f2b5978885464cbB;
  address public other = 0xc78Dc443c126af6E4f6Ed540c1e740C1b5be09cd;
  address public other2 = 0x80AAC46bbd3C2FcE33681541a52CacBEd14bF425;
  address public other3 = 0x5174cD462b60c536eb51D4ceC1D561D3Ea31004F;

  address public zeroAddress = address(0);

  function setUp() public {
    vm.startPrank(owner);
    creatorCore = new ERC721Creator("Token", "NFT");
    example = new ERC721FrozenMetadata();

    creatorCore.registerExtension(address(example), "");

    vm.deal(owner, 10 ether);
    vm.deal(other, 10 ether);
    vm.deal(other2, 10 ether);
    vm.deal(other3, 10 ether);
    vm.stopPrank();
  }

  function testAccess() public {
    vm.startPrank(other2);
    vm.expectRevert("Must be owner or admin of creator contract");
    example.mintToken(address(creatorCore), other2, "");
    vm.stopPrank();
  }

  function testBlankURI() public {
    vm.startPrank(owner);
    vm.expectRevert("Cannot mint blank string");
    example.mintToken(address(creatorCore), owner, "");
    vm.stopPrank();
  }

  function testMintToken() public {
    vm.startPrank(owner);
    example.mintToken(address(creatorCore), owner, "{hey:hey}");
    assertEq(creatorCore.balanceOf(owner), 1);
    assertEq(creatorCore.tokenURI(1), "{hey:hey}");
    vm.stopPrank();
  }

  function testCannotUpdateURI() public {
    vm.startPrank(owner);
    example.mintToken(address(creatorCore), owner, "{hey:hey}");
    assertEq(creatorCore.balanceOf(owner), 1);
    assertEq(creatorCore.tokenURI(1), "{hey:hey}");

    vm.expectRevert("Must be registered extension");
    creatorCore.setTokenURIExtension(1, "{hey2:hey2}");
    vm.stopPrank();
  }
}
