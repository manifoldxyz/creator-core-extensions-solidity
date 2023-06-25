// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test } from "forge-std/Test.sol";
import { ERC721Creator } from "@manifoldxyz/creator-core-solidity/contracts/ERC721Creator.sol";
import { ERC721SeaDropExtension, PublicDrop, ISeaDrop } from "../../contracts/seadrop/ERC721SeaDropExtension.sol";

contract ERC721SeaDropExtensionTest is Test {
  address public  seadropAddress = 0x00005EA00Ac477B1030CE78506496e8C2dE24bf5;
  address public creator = address(0xC12EA7012);
  address public user = address(0xA11CE);

  ERC721Creator public creatorContract;
  ERC721SeaDropExtension public seadropExtension;

  function setUp() public {
    // Fork goerli since i can't import seadrop repo for some reason
    vm.createSelectFork("https://goerli.infura.io/v3/9aa3d95b3bc440fa88ea12eaa4456161");
    vm.roll(9238501);

    // Deploy contracts and register
    vm.startPrank(creator);
    creatorContract = new ERC721Creator("Token", "NFT");
    seadropExtension = new ERC721SeaDropExtension(address(creatorContract));
    creatorContract.registerExtension(address(seadropExtension), "");
    vm.stopPrank();
  }

  function testSeaDropMint() public {
    PublicDrop memory publicDrop = PublicDrop({
      mintPrice: 0.1 ether,
      startTime: uint48(block.timestamp - 10000),
      endTime: uint48(block.timestamp + 10000),
      maxTotalMintableByWallet: 1,
      feeBps: 0,
      restrictFeeRecipients: false
    });

    // Set public drop
    vm.prank(creator);
    seadropExtension.updatePublicDrop(seadropAddress, publicDrop);

    // Set payout address
    vm.prank(creator);
    seadropExtension.updateCreatorPayoutAddress(seadropAddress, creator);
    
    // Mint
    vm.deal(user, 0.1 ether);
    vm.prank(user);
    ISeaDrop(seadropAddress).mintPublic{ value: 0.1 ether }(address(seadropExtension), creator, user, 1);

    // Check balance
    assertEq(creatorContract.ownerOf(1), user);
    assertEq(creator.balance, 0.1 ether);
  }
}
