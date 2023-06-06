// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../contracts/soulbound/ERC1155Soulbound.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC1155Creator.sol";
import "../mocks/Mock.sol";

contract ERC1155SoulboundTest is Test {
  ERC1155Soulbound public example;
  ERC1155Creator public creatorCore;

  address public owner = 0x6140F00e4Ff3936702E68744f2b5978885464cbB;
  address public other = 0xc78Dc443c126af6E4f6Ed540c1e740C1b5be09cd;
  address public other2 = 0x80AAC46bbd3C2FcE33681541a52CacBEd14bF425;
  address public other3 = 0x5174cD462b60c536eb51D4ceC1D561D3Ea31004F;

  address public zeroAddress = address(0);

  function setUp() public {
    vm.startPrank(owner);
    creatorCore = new ERC1155Creator("Token", "NFT");
    example = new ERC1155Soulbound();

    creatorCore.registerExtension(address(example), "override");

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
    example.mintNewToken(address(creatorCore), receivers, tokens, uris);
    vm.expectRevert("Must be owner or admin");
    example.mintExistingToken(address(creatorCore), receivers, tokens, tokens);
    vm.expectRevert("Must be owner or admin");
    example.setTokenURI(address(creatorCore), 1, "");
    vm.expectRevert("Must be owner or admin");
    example.setTokenURI(address(creatorCore), tokens, uris);

    vm.stopPrank();
  }

  function testFunctionality() public {
    vm.startPrank(owner);

    uint[] memory tokens = new uint[](1);
    tokens[0] = 1;
    address[] memory receivers = new address[](1);
    receivers[0] = address(owner);
    string[] memory uris = new string[](1);
    uris[0] = "token1";
    example.mintNewToken(address(creatorCore), receivers, tokens, uris);
    uris[0] = "token2";
    example.mintNewToken(address(creatorCore), receivers, tokens, uris);
    uris[0] = "token3";
    example.mintNewToken(address(creatorCore), receivers, tokens, uris);
    uris[0] = "token4";
    example.mintNewToken(address(creatorCore), receivers, tokens, uris);

    // Default soulbound but burnable
    vm.expectRevert("Extension approval failure");
    creatorCore.safeTransferFrom(owner, other2, 1, 1, "0x0");

    vm.expectRevert("Extension approval failure");
    creatorCore.safeBatchTransferFrom(owner, other2, tokens, tokens, "0x0");

    creatorCore.burn(owner, tokens, tokens);

    // Make non-burnable at token level
    example.configureToken(address(creatorCore), 2, true, false);
    uint[] memory burnTokens = new uint[](1);
    burnTokens[0] = 2;
    vm.expectRevert("Extension approval failure");
    creatorCore.burn(owner, burnTokens, tokens);
    burnTokens[0] = 3;
    creatorCore.burn(owner, burnTokens, tokens);

    // Make non-burnable at contract level
    example.configureContract(address(creatorCore), true, false, "");
    burnTokens[0] = 4;
    vm.expectRevert("Extension approval failure");
    creatorCore.burn(owner, burnTokens, tokens);

    // Make specific token burnable at token level, still cannot burn because restrction exists at the contract level
    burnTokens[0] = 2;
    example.configureToken(address(creatorCore), burnTokens, true, true);
    vm.expectRevert("Extension approval failure");
    creatorCore.burn(owner, burnTokens, tokens);

    // Make non-soulbound at token level
    example.configureToken(address(creatorCore), burnTokens, false, false);

    uint[] memory batchTokens = new uint[](2);
    batchTokens[0] = 2;
    batchTokens[1] = 4;

    uint[] memory amounts = new uint[](2);
    amounts[0] = 1;
    amounts[1] = 1;

    vm.expectRevert("Extension approval failure");
    creatorCore.safeBatchTransferFrom(owner, other2, batchTokens, amounts, "0x0");

    creatorCore.safeTransferFrom(owner, other2, 2, 1, "0x0");
    vm.stopPrank();
    vm.startPrank(other2);
    creatorCore.safeBatchTransferFrom(other2, owner, burnTokens, tokens, "0x0");
    vm.stopPrank();
    vm.startPrank(owner);
    vm.expectRevert("Extension approval failure");
    creatorCore.safeTransferFrom(owner, other2, 4, 1, "0x0");
    burnTokens[0] = 4;
    vm.expectRevert("Extension approval failure");
    creatorCore.safeBatchTransferFrom(owner, other2, burnTokens, tokens, "0x0");

    // Make non-soulbound at contract level
    example.configureContract(address(creatorCore), false, false, "");
    creatorCore.safeTransferFrom(owner, other2, 4, 1, "0x0");
    vm.stopPrank();
    vm.startPrank(other2);
    creatorCore.safeBatchTransferFrom(other2, owner, burnTokens, tokens, "0x0");

    vm.stopPrank();
    vm.startPrank(owner);
    // Make soulbound at token level, transfers allowed because it's still not soulbound at contract level
    example.configureToken(address(creatorCore), batchTokens, true, false);
    creatorCore.safeTransferFrom(owner, other2, 2, 1, "0x0");
    creatorCore.safeBatchTransferFrom(owner, other2, burnTokens, tokens, "0x0");

    // Make soulbound at contract level
    example.configureContract(address(creatorCore), true, true, "");
    vm.expectRevert("Extension approval failure");
    creatorCore.safeTransferFrom(owner, other2, 4, 1, "0x0");
    vm.expectRevert("Extension approval failure");
    creatorCore.safeBatchTransferFrom(owner, other2, burnTokens, tokens, "0x0");

    // Disable extension
    example.setApproveTransfer(address(creatorCore), false);
    // No longer enforcing soulbound
    vm.stopPrank();
    vm.startPrank(other2);
    creatorCore.safeTransferFrom(other2, owner, 2, 1, "0x0");
    creatorCore.safeBatchTransferFrom(other2, owner, burnTokens, tokens, "0x0");

    // Check URIs
    assertEq(creatorCore.uri(2), "token2");
    assertEq(creatorCore.uri(4), "token4");

    vm.stopPrank();
    vm.startPrank(owner);
    example.configureContract(address(creatorCore), true, true, "prefix://");
    assertEq(creatorCore.uri(2), "prefix://token2");
    assertEq(creatorCore.uri(4), "prefix://token4");

    vm.stopPrank();
  }
}
