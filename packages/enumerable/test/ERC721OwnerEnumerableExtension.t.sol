// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../contracts/mocks/Mock.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC721Creator.sol";

contract ERC721OwnerEnumerableExtensionTest is Test {
    MockERC721OwnerEnumerableExtension public example;
    ERC721Creator public creatorCore;

    address public owner = 0x6140F00e4Ff3936702E68744f2b5978885464cbB;
    address public other = 0xc78Dc443c126af6E4f6Ed540c1e740C1b5be09cd;
    address public other2 = 0x80AAC46bbd3C2FcE33681541a52CacBEd14bF425;
    address public other3 = 0x5174cD462b60c536eb51D4ceC1D561D3Ea31004F;

    function setUp() public {
        vm.startPrank(owner);
        creatorCore = new ERC721Creator("Token", "NFT");
        example = new MockERC721OwnerEnumerableExtension();
        creatorCore.registerExtension(address(example), "https://enumerable");
        example.setApproveTransfer(address(creatorCore), true);
        vm.stopPrank();
    }

    function testEnumeration() public {
      vm.startPrank(owner);

      example.fakeMint(address(creatorCore), other);
      example.fakeMint(address(creatorCore), other2);
      example.fakeMint(address(creatorCore), other2);
      example.fakeMint(address(creatorCore), other3);
      example.fakeMint(address(creatorCore), other3);
      example.fakeMint(address(creatorCore), other3);
      assertEq(example.balanceOf(address(creatorCore), other), 1);
      assertEq(example.balanceOf(address(creatorCore), other2), 2);
      assertEq(example.balanceOf(address(creatorCore), other3), 3);

      uint[] memory tokens = new uint[](1);
      for (uint i = 0; i < 1; i++) {
          tokens[i] = example.tokenOfOwnerByIndex(address(creatorCore), other, i);
      }

      uint[] memory tokens2 = new uint[](2);
      for (uint i = 0; i < 2; i++) {
          tokens2[i] = example.tokenOfOwnerByIndex(address(creatorCore), other2, i);
      }

      uint[] memory tokens3 = new uint[](3);
      for (uint i = 0; i < 3; i++) {
          tokens3[i] = example.tokenOfOwnerByIndex(address(creatorCore), other3, i);
      }
      
      assertEq(tokens[0], 1);
      assertEq(tokens2[0], 2);
      assertEq(tokens2[1], 3);
      assertEq(tokens3[0], 4);
      assertEq(tokens3[1], 5);
      assertEq(tokens3[2], 6);
      vm.stopPrank();
      vm.startPrank(other3);
      creatorCore.transferFrom(other3, other, 5);
      vm.stopPrank();
      vm.startPrank(owner);
      assertEq(example.balanceOf(address(creatorCore), other), 2);
      assertEq(example.balanceOf(address(creatorCore), other2), 2);
      assertEq(example.balanceOf(address(creatorCore), other3), 2);

      tokens = new uint[](2);
      for (uint i = 0; i < 2; i++) {
          tokens[i] = example.tokenOfOwnerByIndex(address(creatorCore), other, i);
      }

      tokens2 = new uint[](2);
      for (uint i = 0; i < 2; i++) {
          tokens2[i] = example.tokenOfOwnerByIndex(address(creatorCore), other2, i);
      }

      tokens3 = new uint[](2);
      for (uint i = 0; i < 2; i++) {
          tokens3[i] = example.tokenOfOwnerByIndex(address(creatorCore), other3, i);
      }

      assertEq(tokens[0], 1);
      assertEq(tokens[1], 5);
      assertEq(tokens2[0], 2);
      assertEq(tokens2[1], 3);
      assertEq(tokens3[0], 4);
      assertEq(tokens3[1], 6);

      vm.stopPrank();
      vm.startPrank(other2);
      creatorCore.burn(2);
      vm.stopPrank();
      vm.startPrank(owner);
      assertEq(example.balanceOf(address(creatorCore), other), 2);
      assertEq(example.balanceOf(address(creatorCore), other2), 1);
      assertEq(example.balanceOf(address(creatorCore), other3), 2);


      tokens = new uint[](2);
      for (uint i = 0; i < 2; i++) {
          tokens[i] = example.tokenOfOwnerByIndex(address(creatorCore), other, i);
      }

      tokens2 = new uint[](1);
      for (uint i = 0; i < 1; i++) {
          tokens2[i] = example.tokenOfOwnerByIndex(address(creatorCore), other2, i);
      }

      tokens3 = new uint[](2);
      for (uint i = 0; i < 2; i++) {
          tokens3[i] = example.tokenOfOwnerByIndex(address(creatorCore), other3, i);
      }

      assertEq(tokens[0], 1);
      assertEq(tokens[1], 5);
      assertEq(tokens2[0], 3);
      assertEq(tokens3[0], 4);
      assertEq(tokens3[1], 6);

      vm.stopPrank();
    }            
}