// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../contracts/single/ManifoldERC721Single.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC721Creator.sol";

import "../mocks/Mock.sol";

contract ManifoldERC721SingleTest is Test {
  ManifoldERC721Single public example;
  ERC721Creator public creatorCore;

  address public owner = 0x6140F00e4Ff3936702E68744f2b5978885464cbB;
  address public operator = 0xc78Dc443c126af6E4f6Ed540c1e740C1b5be09cd;

  address public zeroAddress = address(0);
  address public deadAddress = 0x000000000000000000000000000000000000dEaD;
  uint256 private constant MAX_UINT_256 = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;


  function setUp() public {
    vm.startPrank(owner);
    creatorCore = new ERC721Creator("Token", "NFT");

    example = new ManifoldERC721Single();

    creatorCore.registerExtension(address(example), "");
    vm.deal(owner, 10 ether);
    vm.deal(operator, 10 ether);
    vm.stopPrank();
  }

  function testAccess() public {
    vm.startPrank(operator);
    vm.expectRevert("Must be owner or admin of creator contract");
    example.mint(address(creatorCore), 1, "", address(0));
    vm.stopPrank();
  }

  function testMint() public {
    vm.startPrank(owner);
    creatorCore.approveAdmin(address(example));
    example.mint(address(creatorCore), 1, "", operator);
    assertEq(creatorCore.balanceOf(operator), 1);
    // Can't mint same instance twice
    vm.expectRevert(IManifoldERC721Single.InvalidInput.selector);
    example.mint(address(creatorCore), 1, "", operator);
    vm.stopPrank();
  }

  function testTokenURI() public {
    vm.startPrank(owner);
    creatorCore.approveAdmin(address(example));  
    example.mint(address(creatorCore), 1, "https://arweave.net/1hRadwN29sN5UDl_BBgH4RhCc2TjknMpuzGsP1t3wEM", operator);
    assertEq(creatorCore.balanceOf(operator), 1);
    assertEq(creatorCore.tokenURI(1), "https://arweave.net/1hRadwN29sN5UDl_BBgH4RhCc2TjknMpuzGsP1t3wEM");
    vm.stopPrank();
  }

}
