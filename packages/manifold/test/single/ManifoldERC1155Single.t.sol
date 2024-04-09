// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../contracts/single/ManifoldERC1155Single.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC1155Creator.sol";

import "../mocks/Mock.sol";

contract ManifoldERC1155SingleTest is Test {
  ManifoldERC1155Single public example;
  ERC1155Creator public creatorCore;

  address public owner = 0x6140F00e4Ff3936702E68744f2b5978885464cbB;
  address public operator = 0xc78Dc443c126af6E4f6Ed540c1e740C1b5be09cd;

  address public zeroAddress = address(0);
  address public deadAddress = 0x000000000000000000000000000000000000dEaD;
  uint256 private constant MAX_UINT_256 = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

  function setUp() public {
    vm.startPrank(owner);
    creatorCore = new ERC1155Creator("Token", "NFT");

    example = new ManifoldERC1155Single();

    creatorCore.registerExtension(address(example), "");
    vm.deal(owner, 10 ether);
    vm.deal(operator, 10 ether);
    vm.stopPrank();
  }

  function testAccess() public {
    address[] memory recipients = new address[](1);
    uint256[] memory amounts = new uint256[](1);
    vm.startPrank(operator);
    vm.expectRevert("Must be owner or admin of creator contract");
    example.mint(address(creatorCore), 1, "", recipients, amounts);
    vm.stopPrank();
  }

  function testMint() public {
    vm.startPrank(owner);
    creatorCore.approveAdmin(address(example));
    address[] memory recipients = new address[](1);
    uint256[] memory amounts = new uint256[](1);
    recipients[0] = operator;
    amounts[0] = 2;
    example.mint(address(creatorCore), 1, "", recipients, amounts);
    assertEq(creatorCore.balanceOf(operator, 1), 2);
    // Can't mint same instance twice
    vm.expectRevert(IManifoldERC1155Single.InvalidInput.selector);
    example.mint(address(creatorCore), 1, "", recipients, amounts);
    vm.stopPrank();
  }

  function testTokenURI() public {
    vm.startPrank(owner);
    creatorCore.approveAdmin(address(example));
    address[] memory recipients = new address[](1);
    uint256[] memory amounts = new uint256[](1);
    recipients[0] = operator;
    amounts[0] = 2;
    example.mint(address(creatorCore), 1, "https://arweave.net/1hRadwN29sN5UDl_BBgH4RhCc2TjknMpuzGsP1t3wEM", recipients, amounts);
    assertEq(creatorCore.uri(1), "https://arweave.net/1hRadwN29sN5UDl_BBgH4RhCc2TjknMpuzGsP1t3wEM");
    vm.stopPrank();
  }

}
