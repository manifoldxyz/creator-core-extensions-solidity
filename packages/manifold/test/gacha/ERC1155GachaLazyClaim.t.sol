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

  address public creator = 0xc78Dc443c126af6E4f6Ed540c1e740C1b5be09cd;
  address public signingAddress = 0xc78dC443c126Af6E4f6eD540C1E740c1B5be09CE;
  address public other = 0x5174cD462b60c536eb51D4ceC1D561D3Ea31004F;
  address public other2 = 0x6140F00e4Ff3936702E68744f2b5978885464cbB;

  address public zeroAddress = address(0);

  uint256 privateKey = 0x1010101010101010101010101010101010101010101010101010101010101010;
  uint256 MAX_UINT_256 = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
  uint256 public constant MINT_FEE = 500000000000000;

  // Test setup
  function setUp() public {
    vm.startPrank(creator);
    creatorCore1 = new ERC1155Creator("Token1", "NFT1");
    creatorCore2 = new ERC1155Creator("Token2", "NFT2");
    vm.stopPrank();
    vm.startPrank(creator);
    example = new ERC1155GachaLazyClaim(creator);
    example.setSigner(address(signingAddress));
    vm.stopPrank();

    vm.startPrank(creator);
    creatorCore1.registerExtension(address(example), "override");
    creatorCore2.registerExtension(address(example), "override");
    vm.stopPrank();

    vm.deal(creator, 10 ether);
    vm.deal(other, 10 ether);
    vm.deal(other2, 10 ether);
  }

  function testAccess() public {
    vm.startPrank(other);
    // Must be admin
    vm.expectRevert();
    example.withdraw(payable(other), 20);
    vm.expectRevert("AdminControl: Must be owner or admin");
    example.setSigner(other);
    // Must be admin
    vm.expectRevert();

    uint48 nowC = uint48(block.timestamp);
    uint48 later = nowC + 1000;

    IERC1155GachaLazyClaim.ClaimParameters memory claimP = IERC1155GachaLazyClaim.ClaimParameters({
      storageProtocol: IGachaLazyClaim.StorageProtocol.IPFS,
      totalMax: 100,
      startDate: nowC,
      endDate: later,
      tokenVariations: 5,
      location: "arweaveHash1",
      paymentReceiver: payable(creator),
      cost: 0.01 ether,
      erc20: zeroAddress
    });
    // Must be admin
    vm.expectRevert();
    example.initializeClaim(address(creatorCore1), 1, claimP);
    // Succeeds because is admin
    vm.stopPrank();
    vm.startPrank(creator);
    example.initializeClaim(address(creatorCore1), 1, claimP);
    // Now not admin
    vm.stopPrank();
    vm.startPrank(other);
    vm.expectRevert();
    example.updateClaim(address(creatorCore1), 1, claimP);
    vm.expectRevert();

    vm.stopPrank();
  }

  function testinitializeClaimSanitization() public {
    vm.startPrank(creator);

    uint48 nowC = uint48(block.timestamp);
    uint48 later = nowC + 1000;

    IERC1155GachaLazyClaim.ClaimParameters memory claimP = IERC1155GachaLazyClaim.ClaimParameters({
      storageProtocol: IGachaLazyClaim.StorageProtocol.INVALID,
      location: "arweaveHash1",
      totalMax: 100,
      startDate: nowC,
      endDate: later,
      tokenVariations: 5,
      paymentReceiver: payable(other),
      cost: 1,
      erc20: zeroAddress
    });

    vm.expectRevert(IGachaLazyClaim.InvalidStorageProtocol.selector);
    example.initializeClaim(address(creatorCore1), 1, claimP);

    claimP.storageProtocol = IGachaLazyClaim.StorageProtocol.ARWEAVE;
    claimP.startDate = nowC + 2000;
    vm.expectRevert(IGachaLazyClaim.InvalidDate.selector);
    example.initializeClaim(address(creatorCore1), 1, claimP);

    vm.stopPrank();
  }

  function testUpdateClaimSanitization() public {
    vm.startPrank(creator);

    uint48 nowC = uint48(block.timestamp);
    uint48 later = nowC + 1000;

    IERC1155GachaLazyClaim.ClaimParameters memory claimP = IERC1155GachaLazyClaim.ClaimParameters({
      storageProtocol: IGachaLazyClaim.StorageProtocol.ARWEAVE,
      totalMax: 100,
      startDate: nowC,
      endDate: later,
      tokenVariations: 5,
      location: "arweaveHash1",
      paymentReceiver: payable(creator),
      cost: 1,
      erc20: zeroAddress
    });

    example.initializeClaim(address(creatorCore1), 1, claimP);
    example.mintReserve{ value: 1 + MINT_FEE }(address(creatorCore1), 1, 1);

    claimP.storageProtocol = IGachaLazyClaim.StorageProtocol.INVALID;
    vm.expectRevert(IGachaLazyClaim.InvalidStorageProtocol.selector);
    example.updateClaim(address(creatorCore1), 1, claimP);

    claimP.storageProtocol = IGachaLazyClaim.StorageProtocol.ARWEAVE;
    claimP.totalMax = 0;
    vm.expectRevert(IGachaLazyClaim.CannotLowerTotalMaxBeyondTotal.selector);
    example.updateClaim(address(creatorCore1), 1, claimP);

    claimP.totalMax = 100;
    claimP.startDate = nowC + 2000;
    vm.expectRevert(IGachaLazyClaim.InvalidDate.selector);
    example.updateClaim(address(creatorCore1), 1, claimP);

    claimP.startDate = nowC;
    claimP.endDate = nowC;
    vm.expectRevert(IGachaLazyClaim.InvalidDate.selector);
    example.updateClaim(address(creatorCore1), 1, claimP);
    claimP.endDate = later;

    //successful data and cost update
    claimP.erc20 = zeroAddress;
    claimP.cost = 2;
    claimP.startDate = nowC + 1000;
    claimP.endDate = later + 3000;
    example.updateClaim(address(creatorCore1), 1, claimP);

    vm.stopPrank();
  }

  function testMintReserveLowPayment() public {
    vm.startPrank(creator);

    uint48 nowC = 0;
    uint48 later = uint48(block.timestamp) + 2000;

    IERC1155GachaLazyClaim.ClaimParameters memory claimP = IERC1155GachaLazyClaim.ClaimParameters({
      storageProtocol: IGachaLazyClaim.StorageProtocol.ARWEAVE,
      totalMax: 100,
      startDate: nowC,
      endDate: later,
      tokenVariations: 5,
      location: "arweaveHash1",
      paymentReceiver: payable(creator),
      cost: 1,
      erc20: zeroAddress
    });

    example.initializeClaim(address(creatorCore1), 1, claimP);

    // Insufficient payment
    vm.expectRevert(IGachaLazyClaim.InvalidPayment.selector);
    example.mintReserve{ value: 1 }(address(creatorCore1), 1, 2);

    vm.stopPrank();
  }

  function testMintReserveEarly() public {
    // claim hasn't started yet
    vm.startPrank(creator);

    uint48 start = uint48(block.timestamp) + 2000;
    uint48 end = 0;

    IERC1155GachaLazyClaim.ClaimParameters memory claimP = IERC1155GachaLazyClaim.ClaimParameters({
      storageProtocol: IGachaLazyClaim.StorageProtocol.ARWEAVE,
      totalMax: 100,
      startDate: start,
      endDate: end,
      tokenVariations: 5,
      location: "arweaveHash1",
      paymentReceiver: payable(creator),
      cost: 1,
      erc20: zeroAddress
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);
    vm.expectRevert(IGachaLazyClaim.ClaimInactive.selector);
    example.mintReserve{ value: 3 }(address(creatorCore1), 1, 1);
    vm.stopPrank();
  }

  function testMintReserveLate() public {
    vm.startPrank(creator);

    uint48 start = 0;
    uint48 end = uint48(block.timestamp);

    IERC1155GachaLazyClaim.ClaimParameters memory claimP = IERC1155GachaLazyClaim.ClaimParameters({
      storageProtocol: IGachaLazyClaim.StorageProtocol.ARWEAVE,
      totalMax: 100,
      startDate: start,
      endDate: end,
      tokenVariations: 5,
      location: "arweaveHash1",
      paymentReceiver: payable(creator),
      cost: 1,
      erc20: zeroAddress
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);
    vm.stopPrank();

    vm.startPrank(other);
    vm.expectRevert(IGachaLazyClaim.ClaimInactive.selector);
    example.mintReserve{ value: 3 }(address(creatorCore1), 1, 1);
    vm.stopPrank();
  }

  function testMintReserveSoldout() public {
    vm.startPrank(creator);

    uint48 start = 0;
    uint48 end = uint48(block.timestamp) + 2000;

    IERC1155GachaLazyClaim.ClaimParameters memory claimP = IERC1155GachaLazyClaim.ClaimParameters({
      storageProtocol: IGachaLazyClaim.StorageProtocol.ARWEAVE,
      totalMax: 1,
      startDate: start,
      endDate: end,
      tokenVariations: 5,
      location: "arweaveHash1",
      paymentReceiver: payable(creator),
      cost: 1,
      erc20: zeroAddress
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);
    // assumes it's okay to overpay but amount will be refunded
    example.mintReserve{ value: 1 + MINT_FEE }(address(creatorCore1), 1, 1);
    vm.stopPrank();

    vm.startPrank(other);
    vm.expectRevert(IGachaLazyClaim.ClaimSoldOut.selector);
    example.mintReserve{ value: 1 + MINT_FEE }(address(creatorCore1), 1, 1);
    vm.stopPrank();
  }

  function testMintReserveMoreThanAvailable() public {
    vm.startPrank(creator);

    uint48 start = 0;
    uint48 end = uint48(block.timestamp) + 2000;

    uint256 collectorBalanceBefore = address(other).balance;
    uint96 mintPrice = 1 ether;

    IERC1155GachaLazyClaim.ClaimParameters memory claimP = IERC1155GachaLazyClaim.ClaimParameters({
      storageProtocol: IGachaLazyClaim.StorageProtocol.ARWEAVE,
      totalMax: 2,
      startDate: start,
      endDate: end,
      tokenVariations: 5,
      location: "arweaveHash1",
      paymentReceiver: payable(creator),
      cost: mintPrice,
      erc20: zeroAddress
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);
    example.mintReserve{ value: mintPrice + MINT_FEE }(address(creatorCore1), 1, 1);
    vm.stopPrank();

    vm.startPrank(other);
    example.mintReserve{ value: (mintPrice + MINT_FEE) * 2 }(address(creatorCore1), 1, 2);
    vm.stopPrank();

    //confirm user
    GachaLazyClaim.UserMint memory userMint = example.getUserMints(other, address(creatorCore1), 1);
    assertEq(userMint.reservedCount, 1);

    //check payment balances: difference should be for only one mint
    vm.startPrank(creator);
    uint256 balance = address(creator).balance;
    example.withdraw(payable(creator), mintPrice + MINT_FEE);
    uint creatorBalanceAfter = address(creator).balance;
    assertEq(creatorBalanceAfter, balance + mintPrice + MINT_FEE);
    assertEq(address(other).balance, collectorBalanceBefore - mintPrice - MINT_FEE);
    vm.stopPrank();
  }

  function testInvalidSigner() public {
    vm.startPrank(creator);
    uint48 nowC = uint48(block.timestamp);
    uint48 later = nowC + 1000;

    IERC1155GachaLazyClaim.ClaimParameters memory claimP = IERC1155GachaLazyClaim.ClaimParameters({
      storageProtocol: IGachaLazyClaim.StorageProtocol.ARWEAVE,
      totalMax: 100,
      startDate: nowC,
      endDate: later,
      tokenVariations: 5,
      location: "arweaveHash1",
      paymentReceiver: payable(creator),
      cost: 1,
      erc20: zeroAddress
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);
    example.setSigner(signingAddress);
    vm.stopPrank();

    vm.startPrank(other);
    IGachaLazyClaim.Mint[] memory mints = new IGachaLazyClaim.Mint[](1);
    IGachaLazyClaim.Recipient[] memory recipients = new IGachaLazyClaim.Recipient[](1);
    recipients[0] = IGachaLazyClaim.Recipient({ mintCount: 1, receiver: other });
    mints[0] = IGachaLazyClaim.Mint({
      creatorContractAddress: address(creatorCore1),
      instanceId: 1,
      variationIndex: 1,
      recipients: recipients
    });

    vm.expectRevert();
    example.deliverMints(mints);
    vm.stopPrank();
  }

  function testDeliverMints() public {
    vm.startPrank(creator);

    uint48 nowC = uint48(block.timestamp);
    uint48 later = nowC + 1000;

    IERC1155GachaLazyClaim.ClaimParameters memory claimP = IERC1155GachaLazyClaim.ClaimParameters({
      storageProtocol: IGachaLazyClaim.StorageProtocol.ARWEAVE,
      totalMax: 100,
      startDate: nowC,
      endDate: later,
      tokenVariations: 5,
      location: "arweaveHash1",
      paymentReceiver: payable(creator),
      cost: 1,
      erc20: zeroAddress
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);
    example.setSigner(signingAddress);
    example.mintReserve{ value: 1 + MINT_FEE }(address(creatorCore1), 1, 1);
    vm.stopPrank();

    vm.startPrank(signingAddress);
    IGachaLazyClaim.Mint[] memory mints = new IGachaLazyClaim.Mint[](1);
    IGachaLazyClaim.Recipient[] memory recipients = new IGachaLazyClaim.Recipient[](1);
    recipients[0] = IGachaLazyClaim.Recipient({ mintCount: 1, receiver: other });
    mints[0] = IGachaLazyClaim.Mint({
      creatorContractAddress: address(creatorCore1),
      instanceId: 1,
      variationIndex: 1,
      recipients: recipients
    });
    // throw error for receiver
    vm.expectRevert(IGachaLazyClaim.CannotMintMoreThanReserved.selector);
    example.deliverMints(mints);
    GachaLazyClaim.UserMint memory otherMint = example.getUserMints(other, address(creatorCore1), 1);
    assertEq(otherMint.reservedCount, 0);
    assertEq(otherMint.deliveredCount, 0);
    vm.stopPrank();

    // deliver for reserved user
    vm.startPrank(signingAddress);
    recipients = new IGachaLazyClaim.Recipient[](1);
    recipients[0] = IGachaLazyClaim.Recipient({ mintCount: 1, receiver: creator });
    mints[0] = IGachaLazyClaim.Mint({
      creatorContractAddress: address(creatorCore1),
      instanceId: 1,
      variationIndex: 1,
      recipients: recipients
    });
    example.deliverMints(mints);
    GachaLazyClaim.UserMint memory userMint = example.getUserMints(creator, address(creatorCore1), 1);
    assertEq(userMint.deliveredCount, 1);
    vm.stopPrank();
  }

  function testTokenURI() public {
    vm.startPrank(creator);
    uint48 nowC = uint48(block.timestamp);
    uint48 later = nowC + 1000;
    uint totalMintPrice = 1 + MINT_FEE;

    IERC1155GachaLazyClaim.ClaimParameters memory claimP = IERC1155GachaLazyClaim.ClaimParameters({
      storageProtocol: IGachaLazyClaim.StorageProtocol.ARWEAVE,
      totalMax: 100,
      startDate: nowC,
      endDate: later,
      tokenVariations: 5,
      location: "arweaveHash1",
      paymentReceiver: payable(creator),
      cost: 1,
      erc20: zeroAddress
    });

    example.initializeClaim(address(creatorCore1), 1, claimP);
    example.mintReserve{ value: totalMintPrice }(address(creatorCore1), 1, 1);

    // mint in between on another extension
    address[] memory receivers = new address[](1);
    receivers[0] = signingAddress;
    uint[] memory amounts = new uint[](1);
    amounts[0] = 1;
    string[] memory uris = new string[](1);
    uris[0] = "0x0";
    creatorCore1.mintBaseNew(receivers, amounts, uris);
    vm.stopPrank();

    // mintreserving should have no effect
    vm.startPrank(other);
    example.mintReserve{ value: totalMintPrice * 2 }(address(creatorCore1), 1, 2);
    vm.stopPrank();
    vm.startPrank(other2);
    example.mintReserve{ value: totalMintPrice }(address(creatorCore1), 1, 1);
    vm.stopPrank();

    vm.startPrank(creator);
    claimP.tokenVariations = 3;
    claimP.location = "arweaveHash2";
    // create another gacha claim
    example.initializeClaim(address(creatorCore1), 2, claimP);
    vm.stopPrank();

    assertEq("https://arweave.net/arweaveHash1/1", creatorCore1.uri(1));
    assertEq("https://arweave.net/arweaveHash1/2", creatorCore1.uri(2));
    assertEq("https://arweave.net/arweaveHash1/3", creatorCore1.uri(3));
    assertEq("https://arweave.net/arweaveHash1/4", creatorCore1.uri(4));
    assertEq("https://arweave.net/arweaveHash1/5", creatorCore1.uri(5));
    assertTrue(
      keccak256(bytes("https://arweave.net/arweaveHash1/6")) != keccak256(bytes(creatorCore1.uri(6))),
      "URI should not match the specified value."
    );
    assertEq("https://arweave.net/arweaveHash2/1", creatorCore1.uri(7));
    assertEq("https://arweave.net/arweaveHash2/2", creatorCore1.uri(8));
    assertEq("https://arweave.net/arweaveHash2/3", creatorCore1.uri(9));
  }
}
