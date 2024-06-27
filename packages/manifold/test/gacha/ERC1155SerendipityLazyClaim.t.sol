// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../contracts/gachaclaims/IERC1155GachaLazyClaim.sol";
import "../../contracts/gachaclaims/ERC1155GachaLazyClaim.sol";
import "../../contracts/gachaclaims/IGachaLazyClaim.sol";
import "../../contracts/gachaclaims/GachaLazyClaim.sol";

import "@manifoldxyz/creator-core-solidity/contracts/ERC1155Creator.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../mocks/Mock.sol";

contract ERC1155SerendipityLazyClaimTest is Test {
  using SafeMath for uint256;

  ERC1155GachaLazyClaim public example;
  ERC1155 public erc1155;
  ERC1155Creator public creatorCore1;
  ERC1155Creator public creatorCore2;

  address public creator = 0xc78Dc443c126af6E4f6Ed540c1e740C1b5be09cd;
  address public owner = 0x6140F00e4Ff3936702E68744f2b5978885464cbB;
  address public signingAddress = 0xc78dC443c126Af6E4f6eD540C1E740c1B5be09CE;
  address public other = 0x5174cD462b60c536eb51D4ceC1D561D3Ea31004F;
  address public other2 = 0x80AAC46bbd3C2FcE33681541a52CacBEd14bF425;

  address public zeroAddress = address(0);

  uint256 privateKey = 0x1010101010101010101010101010101010101010101010101010101010101010;

  uint32 MAX_UINT_32 = 0xffffffff;
  uint256 public constant MINT_FEE = 500000000000000;

  // Test setup
  function setUp() public {
    vm.startPrank(creator);
    creatorCore1 = new ERC1155Creator("Token1", "NFT1");
    creatorCore2 = new ERC1155Creator("Token2", "NFT2");
    vm.stopPrank();

    vm.startPrank(owner);
    example = new ERC1155GachaLazyClaim(owner);
    example.setSigner(address(signingAddress));
    vm.stopPrank();

    vm.startPrank(creator);
    creatorCore1.registerExtension(address(example), "override");
    creatorCore2.registerExtension(address(example), "override");
    vm.stopPrank();

    vm.deal(creator, 2147483647500004294967295);
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
    // Try as a different non admin
    vm.stopPrank();
    vm.startPrank(other2);
    vm.expectRevert();
    example.initializeClaim(address(creatorCore1), 2, claimP);
    vm.expectRevert();

    vm.stopPrank();
  }

  function testInitializeClaimSanitization() public {
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

    // successful initialization with no end date
    claimP.endDate = 0;
    example.initializeClaim(address(creatorCore1), 1, claimP);
    vm.stopPrank();

    vm.startPrank(owner);
    example.deprecate(true);
    vm.stopPrank();

    vm.startPrank(creator);
    // can't initialize if deprecated
    vm.expectRevert(IGachaLazyClaim.ContractDeprecated.selector);
    example.initializeClaim(address(creatorCore1), 2, claimP);
    vm.stopPrank();

    vm.startPrank(owner);
    example.deprecate(false);
    vm.stopPrank();

    vm.startPrank(creator);
    example.initializeClaim(address(creatorCore1), 2, claimP);
    vm.stopPrank();

    // Cannot deprecate if not an admin
    vm.startPrank(other);
    vm.expectRevert(bytes("AdminControl: Must be owner or admin"));
    example.deprecate(true);
    vm.stopPrank();
  }

  function testUpdateClaimSanitization() public {
    vm.startPrank(creator);

    uint48 nowC = uint48(block.timestamp);
    uint48 later = nowC + 1000;
    IERC1155GachaLazyClaim.ClaimParameters memory claimP = IERC1155GachaLazyClaim.ClaimParameters({
      storageProtocol: IGachaLazyClaim.StorageProtocol.IPFS,
      location: "arweaveHash1",
      totalMax: 100,
      startDate: nowC,
      endDate: later,
      tokenVariations: 5,
      paymentReceiver: payable(other),
      cost: 1,
      erc20: zeroAddress
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);

    IERC1155GachaLazyClaim.UpdateClaimParameters memory claimU = IERC1155GachaLazyClaim.UpdateClaimParameters({
      storageProtocol: IGachaLazyClaim.StorageProtocol.ARWEAVE,
      totalMax: 100,
      startDate: nowC,
      endDate: later,
      location: "arweaveHash1",
      paymentReceiver: payable(creator),
      cost: 1
    });

    example.mintReserve{ value: 1 + MINT_FEE }(address(creatorCore1), 1, 1);

    claimU.storageProtocol = IGachaLazyClaim.StorageProtocol.INVALID;
    vm.expectRevert(IGachaLazyClaim.InvalidStorageProtocol.selector);
    example.updateClaim(address(creatorCore1), 1, claimU);

    claimU.storageProtocol = IGachaLazyClaim.StorageProtocol.ARWEAVE;
    claimU.totalMax = 0;
    vm.expectRevert(IGachaLazyClaim.CannotLowerTotalMaxBeyondTotal.selector);
    example.updateClaim(address(creatorCore1), 1, claimU);

    claimU.totalMax = 100;
    claimU.startDate = nowC + 2000;
    vm.expectRevert(IGachaLazyClaim.InvalidDate.selector);
    example.updateClaim(address(creatorCore1), 1, claimU);

    claimU.endDate = nowC;
    vm.expectRevert(IGachaLazyClaim.InvalidDate.selector);
    example.updateClaim(address(creatorCore1), 1, claimU);
    claimU.endDate = later;

    //successful data and cost update
    claimU.cost = 2;
    claimU.storageProtocol = IGachaLazyClaim.StorageProtocol.IPFS;
    claimU.startDate = nowC + 1000;
    claimU.endDate = later + 3000;
    claimU.totalMax = 1;
    example.updateClaim(address(creatorCore1), 1, claimU);
    IERC1155GachaLazyClaim.Claim memory claim = example.getClaim(address(creatorCore1), 1);
    assertEq(claim.cost, 2);
    // storage protocol for IPFS is 3
    assertEq(uint(claim.storageProtocol), 3);
    assertEq(claim.startDate, nowC + 1000);
    assertEq(claim.endDate, later + 3000);
    assertEq(claim.totalMax, 1);

    // able to update to no end or start date
    claimU.startDate = 0;
    claimU.endDate = 0;
    example.updateClaim(address(creatorCore1), 1, claimU);
    claim = example.getClaim(address(creatorCore1), 1);
    assertEq(claim.startDate, 0);
    assertEq(claim.endDate, 0);

    claimU.startDate = nowC;
    claimU.endDate = 0;
    example.updateClaim(address(creatorCore1), 1, claimU);
    claim = example.getClaim(address(creatorCore1), 1);
    assertEq(claim.startDate, nowC);
    assertEq(claim.endDate, 0);
        vm.stopPrank();

    vm.startPrank(owner);
    example.deprecate(true);
    vm.stopPrank();

    // can't update if deprecated
    vm.startPrank(creator);
    claimU.startDate = nowC + 2000;
    vm.expectRevert(IGachaLazyClaim.ContractDeprecated.selector);
    example.updateClaim(address(creatorCore1), 1, claimU);
    vm.stopPrank();

    vm.startPrank(owner);
    example.deprecate(false);
    vm.stopPrank();

    vm.startPrank(creator);
    example.updateClaim(address(creatorCore1), 1, claimU);
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
    uint48 end = uint48(block.timestamp.sub(1));

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
    example.mintReserve{ value: 1 + MINT_FEE }(address(creatorCore1), 1, 1);
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
    example.mintReserve{ value: 1 + MINT_FEE }(address(creatorCore1), 1, 1);
    vm.stopPrank();

    vm.startPrank(other);
    vm.expectRevert(IGachaLazyClaim.ClaimSoldOut.selector);
    example.mintReserve{ value: 1 + MINT_FEE }(address(creatorCore1), 1, 1);
    vm.stopPrank();
  }

  function testMintReserveNone() public {
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
    vm.expectRevert(IGachaLazyClaim.InvalidMintCount.selector);
    example.mintReserve{ value: 1 + MINT_FEE }(address(creatorCore1), 1, 0);
    vm.stopPrank();
  }

  function testMintReserveTooMany() public {
    vm.startPrank(creator);

    uint48 start = 0;
    uint48 end = uint48(block.timestamp) + 2000;

    IERC1155GachaLazyClaim.ClaimParameters memory claimP = IERC1155GachaLazyClaim.ClaimParameters({
      storageProtocol: IGachaLazyClaim.StorageProtocol.ARWEAVE,
      totalMax: 0,
      startDate: start,
      endDate: end,
      tokenVariations: 2,
      location: "arweaveHash1",
      paymentReceiver: payable(creator),
      cost: 1,
      erc20: zeroAddress
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);
    vm.stopPrank();
    vm.startPrank(other);
    example.mintReserve{ value: 1 + MINT_FEE }(address(creatorCore1), 1, 1);
    vm.stopPrank();

    vm.startPrank(creator);
    vm.expectRevert(IGachaLazyClaim.InvalidMintCount.selector);
    example.mintReserve{ value: (1 + MINT_FEE) * MAX_UINT_32 }(address(creatorCore1), 1, MAX_UINT_32);

    // max out mints
    example.mintReserve{ value: (1 + MINT_FEE) * (MAX_UINT_32 - 1) }(address(creatorCore1), 1, MAX_UINT_32 - 1);

    // try to mint one more
    vm.expectRevert(IGachaLazyClaim.TooManyRequested.selector);
    example.mintReserve{ value: 1 + MINT_FEE }(address(creatorCore1), 1, 1);
    vm.stopPrank();
  }

  function testMintReserveDeliverTotalMax0() public {
    vm.startPrank(creator);

    uint48 start = 0;
    uint48 end = 0;

    IERC1155GachaLazyClaim.ClaimParameters memory claimP = IERC1155GachaLazyClaim.ClaimParameters({
      storageProtocol: IGachaLazyClaim.StorageProtocol.ARWEAVE,
      totalMax: 0,
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

    // should be able to reserve mint even if totalMax is 0
    vm.startPrank(other);
    example.mintReserve{ value: 1 + MINT_FEE }(address(creatorCore1), 1, 1);
    vm.stopPrank();

    vm.startPrank(signingAddress);
    IGachaLazyClaim.ClaimMint[] memory mints = new IGachaLazyClaim.ClaimMint[](1);
    IGachaLazyClaim.VariationMint[] memory variationMints = new IGachaLazyClaim.VariationMint[](1);
    variationMints[0] = IGachaLazyClaim.VariationMint({ variationIndex: 1, amount: 1, recipient: other });
    mints[0] = IGachaLazyClaim.ClaimMint({
      creatorContractAddress: address(creatorCore1),
      instanceId: 1,
      variationMints: variationMints
    });
    example.deliverMints(mints);
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
      totalMax: 4,
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
    uint256 creatorBalanceBefore = address(creator).balance;
    // the manifoled fee is saved to the extension contract
    uint256 extensionBalanceBefore = address(example).balance;
    vm.stopPrank();

    vm.startPrank(other);
    example.mintReserve{ value: (mintPrice + MINT_FEE) * 5 }(address(creatorCore1), 1, 5);
    vm.stopPrank();

    //confirm user
    GachaLazyClaim.UserMintDetails memory userMintDetails = example.getUserMints(other, address(creatorCore1), 1);
    assertEq(userMintDetails.reservedCount, 3);

    //check payment balances: for creator and collector, difference should be for only three mints instead of 5
    uint creatorBalanceAfter = address(creator).balance;
    assertEq(creatorBalanceAfter, creatorBalanceBefore + mintPrice * 3);
    assertEq(address(other).balance, collectorBalanceBefore - ((mintPrice + MINT_FEE) * 3));
    assertEq(address(example).balance, extensionBalanceBefore + MINT_FEE * 3);
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
    vm.stopPrank();

    vm.startPrank(other);
    IGachaLazyClaim.ClaimMint[] memory mints = new IGachaLazyClaim.ClaimMint[](1);
    IGachaLazyClaim.VariationMint[] memory variationMints = new IGachaLazyClaim.VariationMint[](1);
    variationMints[0] = IGachaLazyClaim.VariationMint({ variationIndex: 1, amount: 1, recipient: other });
    mints[0] = IGachaLazyClaim.ClaimMint({
      creatorContractAddress: address(creatorCore1),
      instanceId: 1,
      variationMints: variationMints
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
    example.mintReserve{ value: (1 + MINT_FEE) * 2 }(address(creatorCore1), 1, 2);
    vm.stopPrank();

    vm.startPrank(other2);
    example.mintReserve{ value: (1 + MINT_FEE) * 4 }(address(creatorCore1), 1, 4);
    vm.stopPrank();

    vm.startPrank(signingAddress);
    IGachaLazyClaim.ClaimMint[] memory mints = new IGachaLazyClaim.ClaimMint[](2);
    IGachaLazyClaim.VariationMint[] memory variationMints = new IGachaLazyClaim.VariationMint[](2);
    variationMints[0] = IGachaLazyClaim.VariationMint({ variationIndex: 1, amount: 2, recipient: other2 });
    variationMints[1] = IGachaLazyClaim.VariationMint({ variationIndex: 2, amount: 1, recipient: other });
    mints[0] = IGachaLazyClaim.ClaimMint({
      creatorContractAddress: address(creatorCore1),
      instanceId: 1,
      variationMints: variationMints
    });
    mints[1] = IGachaLazyClaim.ClaimMint({
      creatorContractAddress: address(creatorCore1),
      instanceId: 1,
      variationMints: variationMints
    });
    // revert for receiver with no reserved mints
    vm.expectRevert(IGachaLazyClaim.CannotMintMoreThanReserved.selector);
    example.deliverMints(mints);
    GachaLazyClaim.UserMintDetails memory otherMint = example.getUserMints(other, address(creatorCore1), 1);
    assertEq(otherMint.reservedCount, 0);
    assertEq(otherMint.deliveredCount, 0);
    GachaLazyClaim.UserMintDetails memory other2Mint = example.getUserMints(other2, address(creatorCore1), 1);
    assertEq(other2Mint.reservedCount, 4);
    assertEq(other2Mint.deliveredCount, 0);
    vm.stopPrank();

    // deliver for valid receivers and mintCount
    vm.startPrank(signingAddress);
    variationMints[0] = IGachaLazyClaim.VariationMint({ variationIndex: 1, amount: 1, recipient: creator });
    variationMints[1] = IGachaLazyClaim.VariationMint({ variationIndex: 2, amount: 2, recipient: other2 });
    mints[0] = IGachaLazyClaim.ClaimMint({
      creatorContractAddress: address(creatorCore1),
      instanceId: 1,
      variationMints: variationMints
    });
    mints[1] = IGachaLazyClaim.ClaimMint({
      creatorContractAddress: address(creatorCore1),
      instanceId: 1,
      variationMints: variationMints
    });
    example.deliverMints(mints);
    GachaLazyClaim.UserMintDetails memory creatorMints = example.getUserMints(creator, address(creatorCore1), 1);
    assertEq(creatorMints.deliveredCount, 2);
    assertEq(creatorMints.reservedCount, 2);
    GachaLazyClaim.UserMintDetails memory other2Mints = example.getUserMints(other2, address(creatorCore1), 1);
    assertEq(other2Mints.reservedCount, 4);
    assertEq(other2Mints.deliveredCount, 4);
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

  function testUpdateTokenURI() public {
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

    // tokens with original location
    assertEq("https://arweave.net/arweaveHash1/1", creatorCore1.uri(1));
    assertEq("https://arweave.net/arweaveHash1/2", creatorCore1.uri(2));
    assertEq("https://arweave.net/arweaveHash1/3", creatorCore1.uri(3));
    assertEq("https://arweave.net/arweaveHash1/4", creatorCore1.uri(4));
    assertEq("https://arweave.net/arweaveHash1/5", creatorCore1.uri(5));

    // update tokenURI
    example.updateTokenURIParams(address(creatorCore1), 1, IGachaLazyClaim.StorageProtocol.ARWEAVE, "arweaveHashNEW");
    assertEq("https://arweave.net/arweaveHashNEW/1", creatorCore1.uri(1));
    assertEq("https://arweave.net/arweaveHashNEW/2", creatorCore1.uri(2));
    assertEq("https://arweave.net/arweaveHashNEW/3", creatorCore1.uri(3));
    assertEq("https://arweave.net/arweaveHashNEW/4", creatorCore1.uri(4));
    assertEq("https://arweave.net/arweaveHashNEW/5", creatorCore1.uri(5));
    vm.stopPrank();
  }
}
