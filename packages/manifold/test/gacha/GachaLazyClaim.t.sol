// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../contracts/gachaclaims/IERC1155GachaLazyClaim.sol";
import "../../contracts/gachaclaims/ERC1155GachaLazyClaim.sol";
import "../../contracts/gachaclaims/IGachaLazyClaim.sol";
import "../../contracts/gachaclaims/GachaLazyClaim.sol";

import "@manifoldxyz/creator-core-solidity/contracts/ERC1155Creator.sol";
import "../mocks/Mock.sol";

contract ERC1155GachaLazyClaimTest is Test {
  ERC1155GachaLazyClaim public example;
  ERC1155 public erc1155;
  ERC1155Creator public creatorCore1;
  ERC1155Creator public creatorCore2;

  address public owner = 0x6140F00e4Ff3936702E68744f2b5978885464cbB;
  address public creator = 0xc78Dc443c126af6E4f6Ed540c1e740C1b5be09cd;
  address public signingAddress = 0xc78dC443c126Af6E4f6eD540C1E740c1B5be09CE;
  address public other = 0x5174cD462b60c536eb51D4ceC1D561D3Ea31004F;

  address public zeroAddress = address(0);

  uint256 privateKey = 0x1010101010101010101010101010101010101010101010101010101010101010;
  uint256 MAX_UINT_256 = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

  // Test setup
  function setUp() public {
    signingAddress = vm.addr(privateKey);
    creatorCore1 = new ERC1155Creator("Token1", "NFT1");
    creatorCore2 = new ERC1155Creator("Token2", "NFT2");
    vm.stopPrank();
    vm.startPrank(owner);
    example = new ERC1155GachaLazyClaim(owner);
    example.setSigner(address(signingAddress));
    vm.stopPrank();

    vm.deal(owner, 10 ether);
    vm.deal(creator, 10 ether);
    vm.deal(other, 10 ether);
  }

  function testAccess() public {
    vm.startPrank(other);
    // Must be admin
    vm.expectRevert();
    example.withdraw(payable(other), 20);
    // Must be admin
    vm.expectRevert();

    uint48 nowC = uint48(block.timestamp);
    uint48 later = nowC + 1000;

    IERC1155GachaLazyClaim.ClaimParameters memory claimP = IERC1155GachaLazyClaim.ClaimParameters({
      storageProtocol: IGachaLazyClaim.StorageProtocol.IPFS,
      totalMax: 100,
      startDate: nowC,
      endDate: later,
      startingTokenId: 1,
      itemVariations: 5,
      location: "arweaveHash1",
      paymentReceiver: payable(other),
      cost: 0.01 ether,
      erc20: zeroAddress
    });
    // Must be admin
    vm.expectRevert();
    example.initializeClaim(address(creatorCore1), 1, claimP);
    // Succeeds because is admin
    vm.stopPrank();
    vm.startPrank(owner);
    example.initializeClaim(address(creatorCore1), 1, claimP);
    vm.stopPrank();
    vm.startPrank(other);
    vm.expectRevert();
    example.updateClaim(address(creatorCore1), 1, claimP);
    vm.expectRevert();

    vm.stopPrank();
  }

  function testinitializeClaimSanitization() public {
    vm.startPrank(owner);

    uint48 nowC = uint48(block.timestamp);
    uint48 later = nowC + 1000;

    IERC1155GachaLazyClaim.ClaimParameters memory claimP = IERC1155GachaLazyClaim.ClaimParameters({
      storageProtocol: IGachaLazyClaim.StorageProtocol.INVALID,
      location: "arweaveHash1",
      totalMax: 100,
      startDate: nowC,
      endDate: later,
      startingTokenId: 1,
      itemVariations: 5,
      paymentReceiver: payable(other),
      cost: 1,
      erc20: zeroAddress
    });

    vm.expectRevert(IGachaLazyClaim.InvalidStorageProtocol.selector);
    example.initializeClaim(address(creatorCore1), 1, claimP);

    claimP.storageProtocol = IGachaLazyClaim.StorageProtocol.ARWEAVE;
    claimP.startDate = nowC + 2000;
    vm.expectRevert(IGachaLazyClaim.InvalidStartDate.selector);
    example.initializeClaim(address(creatorCore1), 1, claimP);

    vm.stopPrank();
  }

  function testUpdateClaimSanitization() public {}

  function testInvalidSigner() public {}

  function testTokenURI() public {}
}
