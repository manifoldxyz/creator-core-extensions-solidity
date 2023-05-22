// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../contracts/dynamic/DynamicSVGExample.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC721Creator.sol";

contract DynamicSVGExampleTest is Test {
    DynamicSVGExample public example;
    ERC721Creator public creatorCore;

    address public owner = 0x6140F00e4Ff3936702E68744f2b5978885464cbB;
    address public other = 0xc78Dc443c126af6E4f6Ed540c1e740C1b5be09cd;

    function setUp() public {
        vm.startPrank(owner);
        creatorCore = new ERC721Creator("Token", "NFT");
        example = new DynamicSVGExample(address(creatorCore));
        creatorCore.registerExtension(address(example), "override");
        vm.stopPrank();
    }

    function testAccess() public {
      vm.startPrank(other);
      vm.expectRevert();
      example.mint(other);
      vm.stopPrank();
    }

    function testURI() public {
      vm.startPrank(owner);
      example.setApproveTransfer(address(creatorCore), true);
      example.mint(other);
      vm.warp(block.timestamp + 60*60*24*90);
      assertEq(creatorCore.tokenURI(1), "data:application/json;utf8,{\"name\":\"Dynamic\", \"description\":\"Days passed: 90\", \"image\":\"data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' xmlns:xlink='http://www.w3.org/1999/xlink' id='fade' width='1000' height='1000' viewBox='-0.5 -0.5 1 1'><defs><linearGradient id='g' x1='0%' x2='0%' y1='1%' y2='100%'><stop offset='0%' stop-color='hsl(289.4117,0.0000%,15.0000%)' /><stop offset='50%' stop-color='hsl(205.7647,0.0000%,15.0000%)' /><stop offset='100%' stop-color='hsl(0,0%,15%)' /></linearGradient></defs><g><rect x='-0.5' y='-0.5' width='1' height='1' fill='hsl(0,0%,15%)' /><circle cx='0' cy='0' r='0.0200' fill='url(#g)'><animateTransform attributeName='transform' type='rotate' from='0' to='360' dur='60s' repeatCount='indefinite' /></circle></g></svg>\"}");
      vm.stopPrank();
      vm.startPrank(other);
      creatorCore.transferFrom(other, owner, 1);
      assertEq(creatorCore.tokenURI(1), "data:application/json;utf8,{\"name\":\"Dynamic\", \"description\":\"Days passed: 0\", \"image\":\"data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' xmlns:xlink='http://www.w3.org/1999/xlink' id='fade' width='1000' height='1000' viewBox='-0.5 -0.5 1 1'><defs><linearGradient id='g' x1='0%' x2='0%' y1='1%' y2='100%'><stop offset='0%' stop-color='hsl(323.9999,100.0000%,85.0000%)' /><stop offset='50%' stop-color='hsl(287.6470,50.0000%,50.0000%)' /><stop offset='100%' stop-color='hsl(0,0%,15%)' /></linearGradient></defs><g><rect x='-0.5' y='-0.5' width='1' height='1' fill='hsl(0,0%,15%)' /><circle cx='0' cy='0' r='0.5000' fill='url(#g)'><animateTransform attributeName='transform' type='rotate' from='0' to='360' dur='60s' repeatCount='indefinite' /></circle></g></svg>\"}");
      vm.stopPrank();
    }
            
}
