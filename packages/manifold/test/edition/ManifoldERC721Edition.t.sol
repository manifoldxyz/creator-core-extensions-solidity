// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../contracts/edition/ManifoldERC721Edition.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC721Creator.sol";

import "../mocks/Mock.sol";

contract ManifoldERC721EditionTest is Test {
  ManifoldERC721Edition public example;
  ERC721Creator public creatorCore1;
  ERC721Creator public creatorCore2;
  ERC721Creator public creatorCore3;

  address public owner = 0x6140F00e4Ff3936702E68744f2b5978885464cbB;
  address public operator = 0xc78Dc443c126af6E4f6Ed540c1e740C1b5be09cd;
  address public operator2 = 0x80AAC46bbd3C2FcE33681541a52CacBEd14bF425;
  address public operator3 = 0x5174cD462b60c536eb51D4ceC1D561D3Ea31004F;

  address public zeroAddress = address(0);
  address public deadAddress = 0x000000000000000000000000000000000000dEaD;

  function setUp() public {
    vm.startPrank(owner);
    creatorCore1 = new ERC721Creator("Token", "NFT");
    creatorCore2 = new ERC721Creator("Token", "NFT");
    creatorCore3 = new ERC721Creator("Token", "NFT");

    example = new ManifoldERC721Edition();

    creatorCore1.registerExtension(address(example), "");
    creatorCore2.registerExtension(address(example), "");
    creatorCore3.registerExtension(address(example), "");
    vm.deal(owner, 10 ether);
    vm.deal(operator, 10 ether);
    vm.deal(operator2, 10 ether);
    vm.deal(operator3, 10 ether);
    vm.stopPrank();
  }

  function testAccess() public {
    vm.startPrank(operator);
    IManifoldERC721Edition.Recipient[] memory _emptyRecipients = new IManifoldERC721Edition.Recipient[](0);


    vm.expectRevert("Must be owner or admin of creator contract");
    example.createSeries(address(creatorCore1), 1, "", 1, _emptyRecipients);
    vm.expectRevert("Must be owner or admin of creator contract");
    example.setTokenURIPrefix(address(creatorCore1), 1, "");
    vm.stopPrank();
    vm.startPrank(owner);
    vm.expectRevert("Invalid instanceId");
    example.setTokenURIPrefix(address(creatorCore1), 0, "");
    vm.stopPrank();
    IManifoldERC721Edition.Recipient[] memory recipients = new IManifoldERC721Edition.Recipient[](1);
    recipients[0].recipient = operator;
    recipients[0].count = 1;
    vm.startPrank(operator);
    vm.expectRevert("Must be owner or admin of creator contract");
    example.mint(address(creatorCore1), 1, 0, recipients);
    vm.expectRevert("Must be owner or admin of creator contract");
    example.mint(address(creatorCore1), 1, 0, recipients);
    vm.stopPrank();
  }

  function testEdition() public {
    IManifoldERC721Edition.Recipient[] memory _emptyRecipients = new IManifoldERC721Edition.Recipient[](0);

    vm.startPrank(owner);

    vm.expectRevert("Too many requested");
    example.mint(address(creatorCore1), 1, 0, new IManifoldERC721Edition.Recipient[](0));

    example.createSeries(address(creatorCore1), 10, "http://creator1series1/", 1, _emptyRecipients);

    IManifoldERC721Edition.Recipient[] memory recipients = new IManifoldERC721Edition.Recipient[](1);
    recipients[0].recipient = operator;
    recipients[0].count = 2;

    example.mint(address(creatorCore1), 1, 0, recipients);

    recipients = new IManifoldERC721Edition.Recipient[](2);

    recipients[0].recipient = operator2;
    recipients[0].count = 1;
    recipients[1].recipient = operator3;
    recipients[1].count = 1;

    example.mint(address(creatorCore1), 1, 2, recipients);

    assertEq(creatorCore1.balanceOf(operator), 2);
    assertEq(creatorCore1.balanceOf(operator2), 1);
    assertEq(creatorCore1.balanceOf(operator3), 1);

    recipients = new IManifoldERC721Edition.Recipient[](1);
    recipients[0].recipient = operator;
    recipients[0].count = 7;

    vm.expectRevert("Too many requested");
    example.mint(address(creatorCore1), 1, 4, recipients);
    vm.stopPrank();
  }

  function testEditionIndex() public {
    IManifoldERC721Edition.Recipient[] memory _emptyRecipients = new IManifoldERC721Edition.Recipient[](0);

    vm.startPrank(owner);
    example.createSeries(address(creatorCore1), 10, "http://creator1series1/", 1, _emptyRecipients);
    example.createSeries(address(creatorCore1), 20, "http://creator1series2/", 2, _emptyRecipients);
    example.createSeries(address(creatorCore2), 200, "http://creator1series2/", 3, _emptyRecipients);
    example.createSeries(address(creatorCore3), 300, "http://creator1series2/", 4, _emptyRecipients);

    assertEq(10, example.maxSupply(address(creatorCore1), 1));
    assertEq(20, example.maxSupply(address(creatorCore1), 2));
    assertEq(200, example.maxSupply(address(creatorCore2), 3));
    assertEq(300, example.maxSupply(address(creatorCore3), 4));

    // Total supply should still be 0
    assertEq(0, example.totalSupply(address(creatorCore1), 1));
    assertEq(0, example.totalSupply(address(creatorCore1), 2));
    assertEq(0, example.totalSupply(address(creatorCore2), 3));
    assertEq(0, example.totalSupply(address(creatorCore3), 4));

    IManifoldERC721Edition.Recipient[] memory recipients = new IManifoldERC721Edition.Recipient[](1);
    recipients[0].recipient = operator;
    recipients[0].count = 2;

    example.mint(address(creatorCore1), 1, 0, recipients);

    // Total supply should now be 2
    assertEq(2, example.totalSupply(address(creatorCore1), 1));
    assertEq(0, example.totalSupply(address(creatorCore1), 2));
    assertEq(0, example.totalSupply(address(creatorCore2), 3));
    assertEq(0, example.totalSupply(address(creatorCore3), 4));

    // Mint some tokens in between
    creatorCore1.mintBaseBatch(owner, 10);

    recipients[0].count = 3;
    example.mint(address(creatorCore1), 1, 2, recipients);
    assertEq("http://creator1series1/3", creatorCore1.tokenURI(13));
    assertEq("http://creator1series1/5", creatorCore1.tokenURI(15));

    // Mint series in between
    recipients[0].count = 2;
    example.mint(address(creatorCore1), 2, 0, recipients);
    recipients[0].count = 1;
    example.mint(address(creatorCore1), 1, 5, recipients);

    // Mint items from other creators in between
    recipients[0].count = 2;
    example.mint(address(creatorCore2), 3, 0, recipients);
    example.mint(address(creatorCore3), 4, 0, recipients);

    assertEq("http://creator1series2/1", creatorCore1.tokenURI(16));
    assertEq("http://creator1series2/2", creatorCore1.tokenURI(17));
    assertEq("http://creator1series1/6", creatorCore1.tokenURI(18));

    vm.expectRevert("Invalid token");
    example.tokenURI(address(creatorCore1), 6);
    vm.expectRevert("Invalid token");
    example.tokenURI(address(creatorCore1), 19);

    // Prefix change test
    example.setTokenURIPrefix(address(creatorCore1), 1, "http://creator1series1new/");
    assertEq("http://creator1series1new/3", creatorCore1.tokenURI(13));
    assertEq("http://creator1series1new/5", creatorCore1.tokenURI(15));

    vm.stopPrank();
  }

  function testMintingNone() public {
    IManifoldERC721Edition.Recipient[] memory _emptyRecipients = new IManifoldERC721Edition.Recipient[](0);

    vm.startPrank(owner);
    example.createSeries(address(creatorCore1), 10, "http://creator1series1/", 1, _emptyRecipients);

    vm.expectRevert("No recipients");
    example.mint(address(creatorCore1), 1, 0, new IManifoldERC721Edition.Recipient[](0));

    vm.stopPrank();
  }


  function testMintingTooMany() public {
    IManifoldERC721Edition.Recipient[] memory _emptyRecipients = new IManifoldERC721Edition.Recipient[](0);

    vm.startPrank(owner);
    example.createSeries(address(creatorCore1), 10, "http://creator1series1/", 1, _emptyRecipients);

    IManifoldERC721Edition.Recipient[] memory recipients = new IManifoldERC721Edition.Recipient[](1);
    recipients[0].recipient = operator;
    recipients[0].count = 11;


    vm.expectRevert("Too many requested");
    example.mint(address(creatorCore1), 1, 0, recipients);

    vm.stopPrank();
  }

  function testIncorrectSupply() public {
    IManifoldERC721Edition.Recipient[] memory _emptyRecipients = new IManifoldERC721Edition.Recipient[](0);

    vm.startPrank(owner);
    example.createSeries(address(creatorCore1), 10, "http://creator1series1/", 1, _emptyRecipients);

    IManifoldERC721Edition.Recipient[] memory recipients = new IManifoldERC721Edition.Recipient[](1);
    recipients[0].recipient = operator;
    recipients[0].count = 1;


    vm.expectRevert("Incorrect supply");
    example.mint(address(creatorCore1), 1, 10, recipients);

    vm.stopPrank();
  }

  function testCreatingInvalidSeries() public {
    IManifoldERC721Edition.Recipient[] memory _emptyRecipients = new IManifoldERC721Edition.Recipient[](0);

    vm.startPrank(owner);

    vm.expectRevert("Invalid instance");
    example.createSeries(address(creatorCore1), 10, "http://creator1series1/", 0, _emptyRecipients);

    vm.expectRevert("Invalid instance");
    example.createSeries(address(creatorCore1), 0, "hi", 1, _emptyRecipients);

    example.createSeries(address(creatorCore1), 10, "hi", 1, _emptyRecipients);

    vm.expectRevert("Invalid instance");
    example.createSeries(address(creatorCore1), 10, "hi", 1, _emptyRecipients);

    vm.stopPrank();
  }

  function testCreateAndMintSameTime() public {
    vm.startPrank(owner);

    IManifoldERC721Edition.Recipient[] memory recipients = new IManifoldERC721Edition.Recipient[](1);
    recipients[0].recipient = operator;
    recipients[0].count = 0;

    vm.expectRevert();
    example.createSeries(address(creatorCore1), 10, "http://creator1series1/", 1, recipients);

    recipients[0].count = 1;
    example.createSeries(address(creatorCore1), 10, "http://creator1series1/", 1, recipients);

    // Too many recipients...
    recipients = new IManifoldERC721Edition.Recipient[](11);
    for (uint i = 0; i < 11; i++) {
      recipients[i].recipient = operator;
      recipients[i].count = 1;
    }

    vm.expectRevert("Too many requested");
    example.createSeries(address(creatorCore1), 10, "http://creator1series1/", 2, recipients);
    vm.stopPrank();
  }

  function testMaxSupplyNonInitializedMint() public {
    vm.startPrank(owner);

    vm.expectRevert("Invalid instanceId");
    example.maxSupply(address(creatorCore1), 69);

    vm.stopPrank();
  }
}
