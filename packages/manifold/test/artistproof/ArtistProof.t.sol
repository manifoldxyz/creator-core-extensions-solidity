// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../contracts/artistproof/ArtistProof.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC721Creator.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC1155Creator.sol";
import "../mocks/Mock.sol";

contract ArtistProofTest is Test {
  ArtistProofExtension public example;
  ERC721Creator public creatorCore;
  ERC1155Creator public editionCreatorCore;
  MockManifoldMembership public manifoldMembership;

  address public owner = 0x6140F00e4Ff3936702E68744f2b5978885464cbB;
  address public other = 0xc78Dc443c126af6E4f6Ed540c1e740C1b5be09cd;
  address public other2 = 0x80AAC46bbd3C2FcE33681541a52CacBEd14bF425;
  address public paymentReceiver = 0x5174cD462b60c536eb51D4ceC1D561D3Ea31004F;

  address public zeroAddress = address(0);

  function setUp() public {
    vm.startPrank(owner);
    creatorCore = new ERC721Creator("Token", "NFT");
    editionCreatorCore = new ERC1155Creator("Edition Token", "NFTE");

    example = new ArtistProofExtension(owner);
    manifoldMembership = new MockManifoldMembership();
    example.setMembershipAddress(address(manifoldMembership));

    creatorCore.registerExtension(address(example), "override");
    editionCreatorCore.registerExtension(address(example), "override");

    vm.deal(owner, 10 ether);
    vm.deal(other, 10 ether);
    vm.deal(other2, 10 ether);
    vm.stopPrank();
  }

  function testAccess() public {
    vm.startPrank(other);
    // Must be admin
    vm.expectRevert();
    example.withdraw(payable(other), 20);
    // Must be admin
    vm.expectRevert();
    example.setMembershipAddress(other);

    uint mintFee = example.MINT_FEE();

    uint48 nowC = uint48(block.timestamp);
    uint48 later = nowC + 1000;

    IArtistProofExtension.ArtistProofParameters memory artistProofP = IArtistProofExtension.ArtistProofParameters({
      location: "arweaveHash1",
      storageProtocol: IArtistProofExtension.StorageProtocol.ARWEAVE,
      paymentReceiver: payable(paymentReceiver)
    });
    // Must be admin
    vm.expectRevert("Wallet is not an administrator for contract");
    example.initializeArtistProof(address(creatorCore), address(editionCreatorCore), 1, artistProofP);
    // Succeeds because is admin
    vm.stopPrank();
    vm.startPrank(owner);
    example.initializeArtistProof(address(creatorCore), address(editionCreatorCore), 1, artistProofP);

    // Update, not admin
    vm.stopPrank();
    vm.startPrank(other);
    vm.expectRevert("Wallet is not an administrator for contract");
    example.updateArtistProof(address(creatorCore), 1, artistProofP);

    vm.expectRevert();
    example.extendTokenURI(address(creatorCore), 2, "");

    vm.stopPrank();
    vm.startPrank(owner);
    artistProofP.paymentReceiver = payable(owner);
    artistProofP.location = "arweaveHash2";
    example.updateArtistProof(address(creatorCore), 1, artistProofP);

    ArtistProofExtension.ArtistProofInstance memory artistProof = example.getArtistProof(address(creatorCore), 1);

    assertEq(artistProof.location, "arweaveHash2");
    assertEq(artistProof.paymentReceiver, owner);

    assertEq("https://arweave.net/arweaveHash2", creatorCore.tokenURI(artistProof.proofTokenId));
    assertEq("https://arweave.net/arweaveHash2", editionCreatorCore.uri(artistProof.editionTokenId));

    // Extend uri
    vm.expectRevert();
    example.extendTokenURI(address(creatorCore), 1, "");
    artistProofP.location = "part1";
    artistProofP.storageProtocol = IArtistProofExtension.StorageProtocol.NONE;
    example.updateArtistProof(address(creatorCore), 1, artistProofP);
    example.extendTokenURI(address(creatorCore), 1, "part2");
    assertEq("part1part2", creatorCore.tokenURI(artistProof.proofTokenId));

    vm.stopPrank();
  }

  function testInitializeClaimSanitization() public {
    vm.startPrank(owner);

    IArtistProofExtension.ArtistProofParameters memory artistProofP = IArtistProofExtension.ArtistProofParameters({
      location: "arweaveHash1",
      storageProtocol: IArtistProofExtension.StorageProtocol.INVALID,
      paymentReceiver: payable(paymentReceiver)
    });

    vm.expectRevert(InvalidStorageProtocol.selector);
    example.initializeArtistProof(address(creatorCore), address(editionCreatorCore), 1, artistProofP);

    vm.stopPrank();
  }

  function testUpdateArtistProofSanitization() public {
    vm.startPrank(owner);
    IArtistProofExtension.ArtistProofParameters memory artistProofP = IArtistProofExtension.ArtistProofParameters({
      location: "arweaveHash1",
      storageProtocol: IArtistProofExtension.StorageProtocol.ARWEAVE,
      paymentReceiver: payable(paymentReceiver)
    });

    vm.expectRevert(ArtistProofNotInitialized.selector);
    example.updateArtistProof(address(creatorCore), 1, artistProofP);

    example.initializeArtistProof(address(creatorCore), address(editionCreatorCore), 1, artistProofP);

    artistProofP.storageProtocol = IArtistProofExtension.StorageProtocol.INVALID;
    vm.expectRevert(InvalidStorageProtocol.selector);
    example.updateArtistProof(address(creatorCore), 1, artistProofP);

    vm.stopPrank();
  }

  function testFunctionality() public {
    uint mintFee = example.MINT_FEE();
    uint artistProofFee = example.SUPERLIKE_FEE();

    vm.startPrank(owner);

    IArtistProofExtension.ArtistProofParameters memory artistProofP = IArtistProofExtension.ArtistProofParameters({
      location: "arweaveHash1",
      storageProtocol: IArtistProofExtension.StorageProtocol.ARWEAVE,
      paymentReceiver: payable(paymentReceiver)
    });
  
    // Cannot claim before initialization
    vm.expectRevert(ArtistProofNotInitialized.selector);
    example.mint(address(creatorCore), 1, 0);

    example.initializeArtistProof(address(creatorCore), address(editionCreatorCore), 1, artistProofP);
    ArtistProofExtension.ArtistProofInstance memory artistProof = example.getArtistProof(address(creatorCore), 1);
    assertEq(address(owner), creatorCore.ownerOf(artistProof.proofTokenId));

    // Test minting
    // Mint two tokens to random wallet
    vm.stopPrank();
    vm.startPrank(other2);
    vm.expectRevert("Invalid amount");
    example.mint{ value: mintFee + artistProofFee }(address(creatorCore), 1, 2);
    example.mint{ value: (mintFee + artistProofFee)*2 }(address(creatorCore), 1, 2);

    // Now ensure that the creator contract state is what we expect after mints
    assertEq(editionCreatorCore.balanceOf(other2, artistProof.editionTokenId), 2);

    // Make sure these are soulbound
    vm.expectRevert("Extension approval failure");
    editionCreatorCore.safeTransferFrom(other2, other, artistProof.editionTokenId, 1, "");

    // Passes with valid withdrawal amount from owner
    vm.stopPrank();
    vm.startPrank(owner);
    uint balanceBefore = owner.balance;
    example.withdraw(payable(owner), mintFee*2);
    uint balanceAfter = owner.balance;
    assertEq(balanceAfter, balanceBefore + mintFee*2);
    assertEq(paymentReceiver.balance, artistProofFee*2);

    // Check count
    artistProof = example.getArtistProof(address(creatorCore), 1);
    assertEq(artistProof.editionCount, 2);

    // Mint again and check count
    example.mint{ value: mintFee + artistProofFee }(address(creatorCore), 1, 1);
    artistProof = example.getArtistProof(address(creatorCore), 1);
    assertEq(artistProof.editionCount, 3);

    vm.stopPrank();
  }

  function testMembershipMint() public {
    uint mintFee = example.MINT_FEE();
    uint artistProofFee = example.SUPERLIKE_FEE();

    vm.startPrank(owner);

    IArtistProofExtension.ArtistProofParameters memory artistProofP = IArtistProofExtension.ArtistProofParameters({
      location: "arweaveHash1",
      storageProtocol: IArtistProofExtension.StorageProtocol.ARWEAVE,
      paymentReceiver: payable(paymentReceiver)
    });
  

    example.initializeArtistProof(address(creatorCore), address(editionCreatorCore), 1, artistProofP);

    manifoldMembership.setMember(owner, true);


    vm.expectRevert("Invalid amount");
    example.mint{ value: mintFee }(address(creatorCore), 1, 1);
    example.mint{ value: artistProofFee }(address(creatorCore), 1, 1);

    vm.stopPrank();
  }

  function testProxyMint() public {

    uint mintFee = example.MINT_FEE();
    uint artistProofFee = example.SUPERLIKE_FEE();

    vm.startPrank(owner);

    IArtistProofExtension.ArtistProofParameters memory artistProofP = IArtistProofExtension.ArtistProofParameters({
      location: "arweaveHash1",
      storageProtocol: IArtistProofExtension.StorageProtocol.ARWEAVE,
      paymentReceiver: payable(owner)
    });
  
    example.initializeArtistProof(address(creatorCore), address(editionCreatorCore), 1, artistProofP);
    ArtistProofExtension.ArtistProofInstance memory artistProof = example.getArtistProof(address(creatorCore), 1);

    manifoldMembership.setMember(other, true);

    // The sender is a member, but proxy minting will ignore the fact they are a member
    manifoldMembership.setMember(other, true);
    // Perform a mint on the claim
    uint balance = other.balance;
    uint ownerBalance = owner.balance;

    vm.stopPrank();
    vm.startPrank(other);
    vm.expectRevert("Invalid amount");
    example.mintProxy{ value: artistProofFee * 3 }(address(creatorCore), 1, 3, owner);
    example.mintProxy{ value: (mintFee + artistProofFee) * 3 }(address(creatorCore), 1, 3, owner);

    assertEq(3, editionCreatorCore.balanceOf(owner, artistProof.editionTokenId));

    // Ensure funds taken from message sender
    assertEq(other.balance, balance - (mintFee + artistProofFee) * 3);

    // Ensure seller got funds
    assertEq(owner.balance, ownerBalance + 3 * artistProofFee);
    vm.stopPrank();

    // Check count
    artistProof = example.getArtistProof(address(creatorCore), 1);
    assertEq(artistProof.editionCount, 3);
  }
}
