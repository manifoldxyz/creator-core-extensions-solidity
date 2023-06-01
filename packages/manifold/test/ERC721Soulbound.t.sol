// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../contracts/soulbound/ERC721Soulbound.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC721Creator.sol";
import "../contracts/mocks/Mock.sol";

contract ERC721SoulboundTest is Test {

    ERC721Soulbound public example;
    ERC721Creator public creatorCore;

    address public owner = 0x6140F00e4Ff3936702E68744f2b5978885464cbB;
    address public other = 0xc78Dc443c126af6E4f6Ed540c1e740C1b5be09cd;
    address public other2 = 0x80AAC46bbd3C2FcE33681541a52CacBEd14bF425;
    address public other3 = 0x5174cD462b60c536eb51D4ceC1D561D3Ea31004F;

    address public zeroAddress = address(0);

    function setUp() public {
        vm.startPrank(owner);
        creatorCore = new ERC721Creator("Token", "NFT");
        example = new ERC721Soulbound();

        creatorCore.registerExtension(address(example), "");

        vm.deal(owner, 10 ether);
        vm.deal(other, 10 ether);
        vm.deal(other2, 10 ether);
        vm.deal(other3, 10 ether);
        vm.stopPrank();
    }

    function testAccess() public {
      vm.startPrank(other2);

      vm.expectRevert("Must be owner or admin");
      example.setApproveTransfer(address(creatorCore), true);

      vm.expectRevert("Must be owner or admin");
      example.configureContract(address(creatorCore), true, true, "");
      
      vm.expectRevert("Must be owner or admin");
      example.configureToken(address(creatorCore), 1, true, true);
      uint[] memory tokens = new uint[](1);
      tokens[0] = 1;
      vm.expectRevert("Must be owner or admin");
      example.configureToken(address(creatorCore), tokens, true, true);
      address[] memory receivers = new address[](1);
      receivers[0] = address(other2);
      string[] memory uris = new string[](1);
      uris[0] = "";
      vm.expectRevert("Must be owner or admin");
      example.mintToken(address(creatorCore), owner, "");
      vm.expectRevert("Must be owner or admin");
      example.setTokenURI(address(creatorCore), 1, "");
      vm.expectRevert("Must be owner or admin");
      example.setTokenURI(address(creatorCore), tokens, uris);

      vm.stopPrank();
    }

    function testFunctionality() public {
      vm.startPrank(owner);

      example.mintToken(address(creatorCore), owner, "token1");
      example.mintToken(address(creatorCore), owner, "token2");
      example.mintToken(address(creatorCore), owner, "token3");
      example.mintToken(address(creatorCore), owner, "token4");

      // Default soulbound but burnable
      vm.expectRevert("Extension approval failure");
      creatorCore.safeTransferFrom(owner, other2, 1);
      creatorCore.burn(1);

      // Make non-burnable at token level
      example.configureToken(address(creatorCore), 2, true, false);
      vm.expectRevert("Extension approval failure");
      creatorCore.burn(2);
      creatorCore.burn(3);

      // Make non-burnable at contract level
      example.configureContract(address(creatorCore), true, false, "");
      vm.expectRevert("Extension approval failure");
      creatorCore.burn(4);

      uint[] memory tokens = new uint[](1);
      tokens[0] = 2;

      // Make specific token burnable at token level, still cannot burn because restrction exists at the contract level
      example.configureToken(address(creatorCore), tokens, true, true);
      vm.expectRevert("Extension approval failure");
      creatorCore.burn(2);

      // Make non-soulbound at token level
      example.configureToken(address(creatorCore), tokens, false, false);

      creatorCore.transferFrom(owner, other2, 2);
      vm.expectRevert("Extension approval failure");
      creatorCore.transferFrom(owner, other2, 4);

      // Make non-soulbound at contract level
      example.configureContract(address(creatorCore), false, false, "");
      creatorCore.transferFrom(owner, other2, 4);

      // Make soulbound at token level, transfers allowed because it's still not soulbound at contract level
      example.configureToken(address(creatorCore), tokens, true, false);
      vm.stopPrank();
      vm.startPrank(other2);
      
      creatorCore.transferFrom(other2, owner, 2);
      creatorCore.transferFrom(other2, owner, 4);
      
      vm.stopPrank();
      vm.startPrank(owner);
      // Make soulbound at contract level
      example.configureContract(address(creatorCore), true, true, "");
      vm.expectRevert("Extension approval failure");
      creatorCore.transferFrom(owner, other2, 2);
      vm.expectRevert("Extension approval failure");
      creatorCore.transferFrom(owner, other2, 4);
      
      // Disable extension
      example.setApproveTransfer(address(creatorCore), false);
      // No longer enforcing soulbound
      creatorCore.transferFrom(owner, other2, 2);
      creatorCore.transferFrom(owner, other2, 4);

      // Check URIs
      assertEq(creatorCore.tokenURI(2), "token2");
      assertEq(creatorCore.tokenURI(4), "token4");

      vm.stopPrank();
      vm.startPrank(owner);
      example.configureContract(address(creatorCore), true, true, "prefix://");
      assertEq(creatorCore.tokenURI(2), "prefix://token2");
      assertEq(creatorCore.tokenURI(4), "prefix://token4");

      vm.stopPrank();
    }
}