// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../contracts/frameclaims/ERC1155FrameLazyClaim.sol";
import "../../contracts/frameclaims/IERC1155FrameLazyClaim.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC1155Creator.sol";
import "../mocks/Mock.sol";

contract ERC1155FrameLazyClaimTest is Test {
  ERC1155FrameLazyClaim public example;
  ERC1155Creator public creatorCore;

  address public owner = 0x6140F00e4Ff3936702E68744f2b5978885464cbB;
  address public creator = 0xc78Dc443c126af6E4f6Ed540c1e740C1b5be09cd;
  address public signer = 0x80AAC46bbd3C2FcE33681541a52CacBEd14bF425;
  address public other = 0x5174cD462b60c536eb51D4ceC1D561D3Ea31004F;

  function setUp() public {
    vm.startPrank(creator);
    creatorCore = new ERC1155Creator("Token", "NFT");
    vm.stopPrank();
    vm.startPrank(owner);
    example = new ERC1155FrameLazyClaim(owner);
    example.setSigner(signer);
    vm.stopPrank();

    vm.startPrank(creator);
    creatorCore.registerExtension(address(example), "override");
    vm.stopPrank();

    vm.deal(owner, 10 ether);
    vm.deal(creator, 10 ether);
    vm.deal(other, 10 ether);
    vm.deal(signer, 10 ether);
  }

  function testAccess() public {
    vm.startPrank(other);
    // Must be admin
    vm.expectRevert();
    example.setSigner(other);

    IERC1155FrameLazyClaim.ClaimParameters memory claimP = IERC1155FrameLazyClaim.ClaimParameters({
      location: "arweaveHash1",
      storageProtocol: IFrameLazyClaim.StorageProtocol.ARWEAVE
    });
    // Must be admin
    vm.expectRevert();
    example.initializeClaim(address(creatorCore), 1, claimP);
    // Succeeds because is admin
    vm.stopPrank();
    vm.startPrank(creator);
    example.initializeClaim(address(creatorCore), 1, claimP);

    // Update, not admin
    vm.stopPrank();
    vm.startPrank(other);
    vm.expectRevert();
    example.updateTokenURIParams(address(creatorCore), 1, IFrameLazyClaim.StorageProtocol.IPFS, "");

    vm.expectRevert();
    example.extendTokenURI(address(creatorCore), 2, "");

    vm.stopPrank();
    vm.startPrank(creator);
    example.updateTokenURIParams(address(creatorCore), 1, IFrameLazyClaim.StorageProtocol.ARWEAVE, "arweaveHash3");
    assertEq("https://arweave.net/arweaveHash3", creatorCore.uri(1));
    // Extend uri
    vm.expectRevert();
    example.extendTokenURI(address(creatorCore), 1, "");
    example.updateTokenURIParams(address(creatorCore), 1, IFrameLazyClaim.StorageProtocol.NONE, "part1");
    example.extendTokenURI(address(creatorCore), 1, "part2");
    assertEq("part1part2", creatorCore.uri(1));

    vm.stopPrank();
  }

  function testinitializeClaimSanitization() public {
    vm.startPrank(creator);

    IERC1155FrameLazyClaim.ClaimParameters memory claimP = IERC1155FrameLazyClaim.ClaimParameters({
      location: "arweaveHash1",
      storageProtocol: IFrameLazyClaim.StorageProtocol.INVALID
    });

    vm.expectRevert("Cannot initialize with invalid storage protocol");
    example.initializeClaim(address(creatorCore), 1, claimP);

    vm.expectRevert("Claim not initialized");
    example.updateTokenURIParams(address(creatorCore), 1, IFrameLazyClaim.StorageProtocol.NONE, "");
    vm.expectRevert("Invalid storage protocol");
    example.extendTokenURI(address(creatorCore), 1, "");

    vm.stopPrank();
  }

  function testUpdateClaimSanitization() public {
    vm.startPrank(creator);

    IERC1155FrameLazyClaim.ClaimParameters memory claimP = IERC1155FrameLazyClaim.ClaimParameters({
      location: "arweaveHash1",
      storageProtocol: IFrameLazyClaim.StorageProtocol.ARWEAVE
    });

    example.initializeClaim(address(creatorCore), 1, claimP);

    claimP.storageProtocol = IFrameLazyClaim.StorageProtocol.INVALID;
    vm.expectRevert("Cannot set invalid storage protocol");
    example.updateTokenURIParams(address(creatorCore), 1, IFrameLazyClaim.StorageProtocol.INVALID, "");

    vm.stopPrank();
  }

  function testInvalidSigner() public {
    vm.startPrank(creator);
    IERC1155FrameLazyClaim.ClaimParameters memory claimP = IERC1155FrameLazyClaim.ClaimParameters({
      location: "arweaveHash1",
      storageProtocol: IFrameLazyClaim.StorageProtocol.ARWEAVE
    });

    example.initializeClaim(address(creatorCore), 1, claimP);

    vm.stopPrank();
  
    vm.startPrank(other);
    IFrameLazyClaim.Recipient[] memory recipients = new IFrameLazyClaim.Recipient[](1);
    recipients[0] = IFrameLazyClaim.Recipient({
      receiver: other,
      amount: 1
    });
    IFrameLazyClaim.Mint[] memory mints = new IFrameLazyClaim.Mint[](1);
    mints[0] = IFrameLazyClaim.Mint({
      creatorContractAddress: address(creatorCore),
      instanceId: 1,
      recipients: recipients
    });
    vm.expectRevert(IFrameLazyClaim.InvalidSignature.selector);
    example.mint(mints);
    vm.stopPrank();
  }

  function testMint() public {
    vm.startPrank(creator);
    IERC1155FrameLazyClaim.ClaimParameters memory claimP = IERC1155FrameLazyClaim.ClaimParameters({
      location: "arweaveHash1",
      storageProtocol: IFrameLazyClaim.StorageProtocol.ARWEAVE
    });

    example.initializeClaim(address(creatorCore), 1, claimP);

    vm.stopPrank();
  
    vm.startPrank(signer);
    IFrameLazyClaim.Recipient[] memory recipients = new IFrameLazyClaim.Recipient[](2);
    recipients[0] = IFrameLazyClaim.Recipient({
      receiver: other,
      amount: 2
    });
    recipients[1] = IFrameLazyClaim.Recipient({
      receiver: owner,
      amount: 1
    });
    IFrameLazyClaim.Mint[] memory mints = new IFrameLazyClaim.Mint[](1);
    mints[0] = IFrameLazyClaim.Mint({
      creatorContractAddress: address(creatorCore),
      instanceId: 1,
      recipients: recipients
    });
    example.mint(mints);
    vm.stopPrank();

    assertEq(2, creatorCore.balanceOf(other, 1));
    assertEq(1, creatorCore.balanceOf(owner, 1));
  }

  function testMultipleMint() public {
    vm.startPrank(creator);
    IERC1155FrameLazyClaim.ClaimParameters memory claimP1 = IERC1155FrameLazyClaim.ClaimParameters({
      location: "arweaveHash1",
      storageProtocol: IFrameLazyClaim.StorageProtocol.ARWEAVE
    });

    example.initializeClaim(address(creatorCore), 1, claimP1);
    IERC1155FrameLazyClaim.ClaimParameters memory claimP2 = IERC1155FrameLazyClaim.ClaimParameters({
      location: "arweaveHash2",
      storageProtocol: IFrameLazyClaim.StorageProtocol.ARWEAVE
    });

    example.initializeClaim(address(creatorCore), 2, claimP2);

    vm.stopPrank();
  
    vm.startPrank(signer);
    IFrameLazyClaim.Recipient[] memory recipients1 = new IFrameLazyClaim.Recipient[](2);
    recipients1[0] = IFrameLazyClaim.Recipient({
      receiver: other,
      amount: 2
    });
    recipients1[1] = IFrameLazyClaim.Recipient({
      receiver: owner,
      amount: 1
    });
    IFrameLazyClaim.Recipient[] memory recipients2 = new IFrameLazyClaim.Recipient[](1);
    recipients2[0] = IFrameLazyClaim.Recipient({
      receiver: other,
      amount: 3
    });
    IFrameLazyClaim.Mint[] memory mints = new IFrameLazyClaim.Mint[](2);
    mints[0] = IFrameLazyClaim.Mint({
      creatorContractAddress: address(creatorCore),
      instanceId: 1,
      recipients: recipients1
    });
    mints[1] = IFrameLazyClaim.Mint({
      creatorContractAddress: address(creatorCore),
      instanceId: 2,
      recipients: recipients2
    });
    example.mint(mints);
    vm.stopPrank();

    assertEq(2, creatorCore.balanceOf(other, 1));
    assertEq(1, creatorCore.balanceOf(owner, 1));
    assertEq(3, creatorCore.balanceOf(other, 2));
  }
}
