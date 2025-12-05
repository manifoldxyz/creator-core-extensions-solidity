// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../contracts/gachaclaims/IERC1155SerendipityCore.sol";
import "../../contracts/gachaclaims/ERC1155Serendipity.sol";
import "../../contracts/gachaclaims/ISerendipityCore.sol";
import "../../contracts/gachaclaims/Serendipity.sol";

import "@manifoldxyz/creator-core-solidity/contracts/ERC1155Creator.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../mocks/Mock.sol";

contract ERC1155SerendipityTest is Test {
  using SafeMath for uint256;

  ERC1155Serendipity public example;
  ERC1155 public erc1155;
  ERC1155Creator public creatorCore1;
  ERC1155Creator public creatorCore2;

  address public creator = 0xc78Dc443c126af6E4f6Ed540c1e740C1b5be09cd;
  address public owner = 0x6140F00e4Ff3936702E68744f2b5978885464cbB;
  address public other = 0x5174cD462b60c536eb51D4ceC1D561D3Ea31004F;
  address public other2 = 0x80AAC46bbd3C2FcE33681541a52CacBEd14bF425;

  address public zeroAddress = address(0);

  uint256 privateKey = 0x1010101010101010101010101010101010101010101010101010101010101010;
  address public signingAddress;

  uint32 MAX_UINT_32 = 0xffffffff;
  uint256 public constant MINT_FEE = 500000000000000;

  // Test setup
  function setUp() public {
    signingAddress = vm.addr(privateKey);

    vm.startPrank(creator);
    creatorCore1 = new ERC1155Creator("Token1", "NFT1");
    creatorCore2 = new ERC1155Creator("Token2", "NFT2");
    vm.stopPrank();

    vm.startPrank(owner);
    example = new ERC1155Serendipity(owner);
    vm.stopPrank();

    vm.startPrank(creator);
    creatorCore1.registerExtension(address(example), "override");
    creatorCore2.registerExtension(address(example), "override");
    vm.stopPrank();

    vm.deal(creator, 2147483647500004294967295);
    vm.deal(other, 10 ether);
    vm.deal(other2, 10 ether);
  }

  // Helper function to create signature for deliverMints
  function _createDeliverMintsSignature(
    ISerendipityCore.ClaimMint[] memory mints,
    bytes32 nonce,
    uint256 expiration
  ) internal view returns (bytes memory signature, bytes32 message) {
    message = keccak256(abi.encode(mints, nonce, expiration));
    bytes32 digest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", message));
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
    signature = abi.encodePacked(r, s, v);
  }

  function testAccess() public {
    vm.startPrank(other);
    // Must be admin
    vm.expectRevert();
    example.withdraw(payable(other), 20);
    vm.expectRevert("AdminControl: Must be owner or admin");
    example.setSigner(other);

    uint48 nowC = uint48(block.timestamp);
    uint48 later = nowC + 1000;

    IERC1155SerendipityCore.ClaimParameters memory claimP = IERC1155SerendipityCore.ClaimParameters({
      storageProtocol: ISerendipityCore.StorageProtocol.IPFS,
      totalMax: 100,
      startDate: nowC,
      endDate: later,
      tokenVariations: 5,
      location: "arweaveHash1",
      paymentReceiver: payable(creator),
      cost: 0.01 ether,
      erc20: zeroAddress,
      signingAddress: signingAddress
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

    vm.stopPrank();
  }

  function testInitializeClaimSanitization() public {
    vm.startPrank(creator);

    uint48 nowC = uint48(block.timestamp);
    uint48 later = nowC + 1000;

    IERC1155SerendipityCore.ClaimParameters memory claimP = IERC1155SerendipityCore.ClaimParameters({
      storageProtocol: ISerendipityCore.StorageProtocol.INVALID,
      location: "arweaveHash1",
      totalMax: 100,
      startDate: nowC,
      endDate: later,
      tokenVariations: 5,
      paymentReceiver: payable(other),
      cost: 1,
      erc20: zeroAddress,
      signingAddress: signingAddress
    });

    vm.expectRevert(ISerendipityCore.InvalidStorageProtocol.selector);
    example.initializeClaim(address(creatorCore1), 1, claimP);

    claimP.storageProtocol = ISerendipityCore.StorageProtocol.ARWEAVE;
    claimP.startDate = nowC + 2000;
    vm.expectRevert(ISerendipityCore.InvalidDate.selector);
    example.initializeClaim(address(creatorCore1), 1, claimP);

    // successful initialization with no end date
    claimP.endDate = 0;
    example.initializeClaim(address(creatorCore1), 1, claimP);

    // successful initialization with no start date
    claimP.startDate = 0;
    claimP.endDate = later;
    example.initializeClaim(address(creatorCore1), 2, claimP);

    // successful initialization with no start or end date
    claimP.endDate = 0;
    example.initializeClaim(address(creatorCore1), 3, claimP);
    vm.stopPrank();
  }

  function test_InitializeClaimWithUnlimitedSupply() public {
    vm.startPrank(creator);
    // init some arguments for mint base new
    address[] memory receivers = new address[](1);
    receivers[0] = other2;
    uint[] memory amounts = new uint[](1);
    amounts[0] = 5;
    string[] memory uris = new string[](1);
    uris[0] = "some hash";
    // premint some tokens
    creatorCore1.mintBaseNew(receivers, amounts, uris);

    uint48 nowC = uint48(block.timestamp);
    uint48 later = nowC + 1000;

    IERC1155SerendipityCore.ClaimParameters memory claimP = IERC1155SerendipityCore.ClaimParameters({
      storageProtocol: ISerendipityCore.StorageProtocol.ARWEAVE,
      location: "arweaveHash1",
      totalMax: 0,
      startDate: nowC,
      endDate: later,
      tokenVariations: 5,
      paymentReceiver: payable(other),
      cost: 1,
      erc20: zeroAddress,
      signingAddress: signingAddress
    });

    example.initializeClaim(address(creatorCore1), 1, claimP);
    vm.stopPrank();

    vm.startPrank(other);
    IERC1155SerendipityCore.Claim memory claim = example.getClaim(address(creatorCore1), 1);
    // check equality of claim parameters
    assertEq(uint(claim.storageProtocol), 2);
    assertEq(claim.location, "arweaveHash1");
    assertEq(claim.total, 0);
    assertEq(claim.totalMax, 0);
    assertEq(claim.startDate, nowC);
    assertEq(claim.endDate, later);
    assertEq(claim.tokenVariations, 5);
    assertEq(claim.paymentReceiver, payable(other));
    assertEq(claim.cost, 1);
    assertEq(claim.erc20, zeroAddress);
    assertEq(claim.startingTokenId, 2);

    vm.stopPrank();
  }

  function test_UpdateClaim_LimitedSupplySanitization() public {
    vm.startPrank(creator);

    uint48 nowC = uint48(block.timestamp);
    uint48 later = nowC + 1000;
    IERC1155SerendipityCore.ClaimParameters memory claimP = IERC1155SerendipityCore.ClaimParameters({
      storageProtocol: ISerendipityCore.StorageProtocol.IPFS,
      location: "arweaveHash1",
      totalMax: 100,
      startDate: nowC,
      endDate: later,
      tokenVariations: 5,
      paymentReceiver: payable(other),
      cost: 1,
      erc20: zeroAddress,
      signingAddress: signingAddress
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);

    IERC1155SerendipityCore.UpdateClaimParameters memory claimU = IERC1155SerendipityCore.UpdateClaimParameters({
      storageProtocol: ISerendipityCore.StorageProtocol.ARWEAVE,
      totalMax: 100,
      startDate: nowC,
      endDate: later,
      location: "arweaveHash1",
      paymentReceiver: payable(creator),
      cost: 1
    });

    example.mintReserve{ value: 1 + MINT_FEE }(address(creatorCore1), 1, 1);

    claimU.storageProtocol = ISerendipityCore.StorageProtocol.INVALID;
    vm.expectRevert(ISerendipityCore.InvalidStorageProtocol.selector);
    example.updateClaim(address(creatorCore1), 1, claimU);

    // reset to valid storage protocol
    claimU.storageProtocol = ISerendipityCore.StorageProtocol.ARWEAVE;
    claimU.startDate = nowC + 2000;
    vm.expectRevert(ISerendipityCore.InvalidDate.selector);
    example.updateClaim(address(creatorCore1), 1, claimU);

    claimU.endDate = nowC;
    vm.expectRevert(ISerendipityCore.InvalidDate.selector);
    example.updateClaim(address(creatorCore1), 1, claimU);
    claimU.endDate = later;

    //successful data and cost update
    claimU.cost = 2;
    claimU.storageProtocol = ISerendipityCore.StorageProtocol.IPFS;
    claimU.startDate = nowC + 1000;
    claimU.endDate = later + 3000;
    example.updateClaim(address(creatorCore1), 1, claimU);
    IERC1155SerendipityCore.Claim memory claim = example.getClaim(address(creatorCore1), 1);
    assertEq(claim.cost, 2);
    // storage protocol for IPFS is 3
    assertEq(uint(claim.storageProtocol), 3);
    assertEq(claim.startDate, nowC + 1000);
    assertEq(claim.endDate, later + 3000);

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

    // update location
    claimU.location = "newArweaveHash";
    example.updateClaim(address(creatorCore1), 1, claimU);
    claim = example.getClaim(address(creatorCore1), 1);
    assertEq(claim.location, "newArweaveHash");
    vm.stopPrank();
  }

  function test_UpdateClaim_UnlimitedSupplySanitization() public {
    vm.startPrank(creator);

    uint48 nowC = uint48(block.timestamp);
    uint48 later = nowC + 1000;
    IERC1155SerendipityCore.ClaimParameters memory claimP = IERC1155SerendipityCore.ClaimParameters({
      storageProtocol: ISerendipityCore.StorageProtocol.IPFS,
      location: "arweaveHash1",
      totalMax: 0,
      startDate: nowC,
      endDate: later,
      tokenVariations: 5,
      paymentReceiver: payable(other),
      cost: 1,
      erc20: zeroAddress,
      signingAddress: signingAddress
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);

    IERC1155SerendipityCore.UpdateClaimParameters memory claimU = IERC1155SerendipityCore.UpdateClaimParameters({
      totalMax: 0,
      storageProtocol: ISerendipityCore.StorageProtocol.ARWEAVE,
      startDate: nowC,
      endDate: later,
      location: "arweaveHash1",
      paymentReceiver: payable(creator),
      cost: 1
    });

    example.mintReserve{ value: 1 + MINT_FEE }(address(creatorCore1), 1, 1);

    claimU.storageProtocol = ISerendipityCore.StorageProtocol.INVALID;
    vm.expectRevert(ISerendipityCore.InvalidStorageProtocol.selector);
    example.updateClaim(address(creatorCore1), 1, claimU);

    // reset to valid storage protocol
    claimU.storageProtocol = ISerendipityCore.StorageProtocol.ARWEAVE;
    claimU.startDate = nowC + 2000;
    vm.expectRevert(ISerendipityCore.InvalidDate.selector);
    example.updateClaim(address(creatorCore1), 1, claimU);

    claimU.endDate = nowC;
    vm.expectRevert(ISerendipityCore.InvalidDate.selector);
    example.updateClaim(address(creatorCore1), 1, claimU);
    claimU.endDate = later;

    //successful data and cost update
    claimU.cost = 2;
    claimU.storageProtocol = ISerendipityCore.StorageProtocol.IPFS;
    claimU.startDate = nowC + 1000;
    claimU.endDate = later + 3000;
    example.updateClaim(address(creatorCore1), 1, claimU);
    IERC1155SerendipityCore.Claim memory claim = example.getClaim(address(creatorCore1), 1);
    assertEq(claim.cost, 2);
    // storage protocol for IPFS is 3
    assertEq(uint(claim.storageProtocol), 3);
    assertEq(claim.startDate, nowC + 1000);
    assertEq(claim.endDate, later + 3000);

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

    // update location
    claimU.location = "newArweaveHash";
    example.updateClaim(address(creatorCore1), 1, claimU);
    claim = example.getClaim(address(creatorCore1), 1);
    assertEq(claim.location, "newArweaveHash");
    vm.stopPrank();
  }

  function test_UpdateClaim_SwitchTokenSupplyWhenNoMints() public {
    vm.startPrank(creator);

    uint48 nowC = uint48(block.timestamp);
    uint48 later = nowC + 1000;
    IERC1155SerendipityCore.ClaimParameters memory claimP = IERC1155SerendipityCore.ClaimParameters({
      storageProtocol: ISerendipityCore.StorageProtocol.ARWEAVE,
      location: "arweaveHash1",
      totalMax: 100,
      startDate: nowC,
      endDate: later,
      tokenVariations: 5,
      paymentReceiver: payable(other),
      cost: 1,
      erc20: zeroAddress,
      signingAddress: signingAddress
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);

    IERC1155SerendipityCore.UpdateClaimParameters memory claimU = IERC1155SerendipityCore.UpdateClaimParameters({
      storageProtocol: ISerendipityCore.StorageProtocol.ARWEAVE,
      totalMax: 0,
      startDate: nowC,
      endDate: later,
      location: "arweaveHash1",
      paymentReceiver: payable(other),
      cost: 1
    });

    // when mint count is 0, change from limited (100) -> unlimited (0) supply
    example.updateClaim(address(creatorCore1), 1, claimU);
    IERC1155SerendipityCore.Claim memory claim = example.getClaim(address(creatorCore1), 1);
    assertEq(claim.total, 0, "total should be 0");
    assertEq(claim.totalMax, 0, "totalMax should be updated to 0");

    // update from unlimited (0) -> limited (5) supply
    claimU.totalMax = 5;
    example.updateClaim(address(creatorCore1), 1, claimU);
    claim = example.getClaim(address(creatorCore1), 1);
    assertEq(claim.total, 0, "total should be 0");
    assertEq(claim.totalMax, 5, "totalMax should be updated to 5");

    // update from limited (5) -> limited (1000) supply
    claimU.totalMax = 1000;
    example.updateClaim(address(creatorCore1), 1, claimU);
    claim = example.getClaim(address(creatorCore1), 1);
    assertEq(claim.total, 0, "total should be 0");
    assertEq(claim.totalMax, 1000, "totalMax should be updated to 5");

    vm.stopPrank();
  }

  function test_UpdateClaim_ChangeSupplyForLimitedInitialSupply() public {
    vm.startPrank(creator);

    uint48 nowC = uint48(block.timestamp);
    uint48 later = nowC + 1000;
    IERC1155SerendipityCore.ClaimParameters memory claimP = IERC1155SerendipityCore.ClaimParameters({
      storageProtocol: ISerendipityCore.StorageProtocol.ARWEAVE,
      location: "arweaveHash1",
      totalMax: 100,
      startDate: nowC,
      endDate: later,
      tokenVariations: 5,
      paymentReceiver: payable(other),
      cost: 1,
      erc20: zeroAddress,
      signingAddress: signingAddress
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);
    example.mintReserve{ value: 5 + 5*MINT_FEE }(address(creatorCore1), 1, 5);

    IERC1155SerendipityCore.Claim memory claim = example.getClaim(address(creatorCore1), 1);
    // sanity setup
    assertEq(claim.totalMax, 100, "totalMax should be 100");
    assertEq(claim.total, 5, "total should be 5");

    IERC1155SerendipityCore.UpdateClaimParameters memory claimU = IERC1155SerendipityCore.UpdateClaimParameters({
      storageProtocol: ISerendipityCore.StorageProtocol.ARWEAVE,
      totalMax: 5,
      startDate: nowC,
      endDate: later,
      location: "arweaveHash1",
      paymentReceiver: payable(other),
      cost: 1
    });


    // update when minted count is 5
    claimU.totalMax = 4;
    vm.expectRevert(ISerendipityCore.CannotLowerTotalMaxBeyondTotal.selector);
    example.updateClaim(address(creatorCore1), 1, claimU);

    // confirm can set total max to minted count
    claimU.totalMax = 5;
    example.updateClaim(address(creatorCore1), 1, claimU);
    claim = example.getClaim(address(creatorCore1), 1);
    assertEq(claim.totalMax, 5, "totalMax should be updated to 5");
    assertEq(claim.total, 5, "total should be 5");
    // confirm nothing else changed
    assertEq(uint(claim.storageProtocol), uint(ISerendipityCore.StorageProtocol.ARWEAVE));
    assertEq(claim.location, "arweaveHash1");
    assertEq(claim.startDate, nowC);
    assertEq(claim.endDate, later);
    assertEq(claim.tokenVariations, 5);
    assertEq(claim.paymentReceiver, payable(other));
    assertEq(claim.cost, 1);
    assertEq(claim.erc20, zeroAddress);

    // confirm can set total max to > minted count
    claimU.totalMax = 10;
    example.updateClaim(address(creatorCore1), 1, claimU);
    claim = example.getClaim(address(creatorCore1), 1);
    assertEq(claim.totalMax, 10, "totalMax should be updated to 10");
    assertEq(claim.total, 5, "total should be 5");

    // confirm can set supply to unlimited (0)
    claimU.totalMax = 0;
    example.updateClaim(address(creatorCore1), 1, claimU);
    claim = example.getClaim(address(creatorCore1), 1);
    assertEq(claim.totalMax, 0, "totalMax should be updated to 0");
    assertEq(claim.total, 5, "total should be 5");

    vm.stopPrank();
  }

  function test_UpdateClaim_ChangeSupplyForUnlimitedInitialSupply() public {
    vm.startPrank(creator);

    uint48 nowC = uint48(block.timestamp);
    uint48 later = nowC + 1000;
    IERC1155SerendipityCore.ClaimParameters memory claimP = IERC1155SerendipityCore.ClaimParameters({
      storageProtocol: ISerendipityCore.StorageProtocol.ARWEAVE,
      location: "arweaveHash1",
      totalMax: 0,
      startDate: nowC,
      endDate: later,
      tokenVariations: 5,
      paymentReceiver: payable(other),
      cost: 1,
      erc20: zeroAddress,
      signingAddress: signingAddress
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);
    example.mintReserve{ value: 5 + 5*MINT_FEE }(address(creatorCore1), 1, 5);

    IERC1155SerendipityCore.Claim memory claim = example.getClaim(address(creatorCore1), 1);
    // sanity setup
    assertEq(claim.totalMax, 0, "totalMax should be 0 (unlimited)");
    assertEq(claim.total, 5, "total should be 5");

    IERC1155SerendipityCore.UpdateClaimParameters memory claimU = IERC1155SerendipityCore.UpdateClaimParameters({
      storageProtocol: ISerendipityCore.StorageProtocol.ARWEAVE,
      totalMax: 5,
      startDate: nowC,
      endDate: later,
      location: "arweaveHash1",
      paymentReceiver: payable(other),
      cost: 1
    });


    // update when minted count is 5
    claimU.totalMax = 4;
    vm.expectRevert(ISerendipityCore.CannotLowerTotalMaxBeyondTotal.selector);
    example.updateClaim(address(creatorCore1), 1, claimU);

    // confirm can set total max to minted count
    claimU.totalMax = 5;
    example.updateClaim(address(creatorCore1), 1, claimU);
    claim = example.getClaim(address(creatorCore1), 1);
    assertEq(claim.totalMax, 5, "totalMax should be updated to 5");
    assertEq(claim.total, 5, "total should be 5");
    // confirm nothing else changed
    assertEq(uint(claim.storageProtocol), uint(ISerendipityCore.StorageProtocol.ARWEAVE));
    assertEq(claim.location, "arweaveHash1");
    assertEq(claim.startDate, nowC);
    assertEq(claim.endDate, later);
    assertEq(claim.tokenVariations, 5);
    assertEq(claim.paymentReceiver, payable(other));
    assertEq(claim.cost, 1);
    assertEq(claim.erc20, zeroAddress);

    // confirm can set total max to > minted count
    claimU.totalMax = 10;
    example.updateClaim(address(creatorCore1), 1, claimU);
    claim = example.getClaim(address(creatorCore1), 1);
    assertEq(claim.totalMax, 10, "totalMax should be updated to 10");
    assertEq(claim.total, 5, "total should be 5");

    // other cases covered by change supply for limited initial supply
    vm.stopPrank();
  }

  function test_RevertWhen_UpdateClaimNotClaimOwner() public {
    vm.startPrank(creator);

    uint48 nowC = uint48(block.timestamp);
    uint48 later = nowC + 1000;
    IERC1155SerendipityCore.ClaimParameters memory claimP = IERC1155SerendipityCore.ClaimParameters({
      storageProtocol: ISerendipityCore.StorageProtocol.IPFS,
      location: "arweaveHash1",
      totalMax: 5,
      startDate: nowC,
      endDate: later,
      tokenVariations: 5,
      paymentReceiver: payable(creator),
      cost: 1,
      erc20: zeroAddress,
      signingAddress: signingAddress
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);
    vm.stopPrank();

    vm.startPrank(other);
    IERC1155SerendipityCore.UpdateClaimParameters memory claimU = IERC1155SerendipityCore.UpdateClaimParameters({
      storageProtocol: ISerendipityCore.StorageProtocol.ARWEAVE,
      totalMax: 10,
      startDate: nowC,
      endDate: later,
      location: "arweaveHash1",
      paymentReceiver: payable(other),
      cost: 1
    });
    vm.expectRevert();
    example.updateClaim(address(creatorCore1), 1, claimU);
    vm.stopPrank();
  }

  function testMintReserveLowPayment() public {
    vm.startPrank(creator);

    uint48 nowC = 0;
    uint48 later = uint48(block.timestamp) + 2000;

    IERC1155SerendipityCore.ClaimParameters memory claimP = IERC1155SerendipityCore.ClaimParameters({
      storageProtocol: ISerendipityCore.StorageProtocol.ARWEAVE,
      totalMax: 100,
      startDate: nowC,
      endDate: later,
      tokenVariations: 5,
      location: "arweaveHash1",
      paymentReceiver: payable(creator),
      cost: 1,
      erc20: zeroAddress,
      signingAddress: signingAddress
    });

    example.initializeClaim(address(creatorCore1), 1, claimP);

    // Insufficient payment
    vm.expectRevert(ISerendipityCore.InvalidPayment.selector);
    example.mintReserve{ value: 1 }(address(creatorCore1), 1, 2);

    vm.stopPrank();
  }

  function testMintReserveEarly() public {
    // claim hasn't started yet
    vm.startPrank(creator);

    uint48 start = uint48(block.timestamp) + 2000;
    uint48 end = 0;

    IERC1155SerendipityCore.ClaimParameters memory claimP = IERC1155SerendipityCore.ClaimParameters({
      storageProtocol: ISerendipityCore.StorageProtocol.ARWEAVE,
      totalMax: 100,
      startDate: start,
      endDate: end,
      tokenVariations: 5,
      location: "arweaveHash1",
      paymentReceiver: payable(creator),
      cost: 1,
      erc20: zeroAddress,
      signingAddress: signingAddress
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);
    vm.expectRevert(ISerendipityCore.ClaimInactive.selector);
    example.mintReserve{ value: 3 }(address(creatorCore1), 1, 1);
    vm.stopPrank();
  }

  function testMintReserveLate() public {
    vm.startPrank(creator);

    uint48 start = 0;
    uint48 end = uint48(block.timestamp.sub(1));

    IERC1155SerendipityCore.ClaimParameters memory claimP = IERC1155SerendipityCore.ClaimParameters({
      storageProtocol: ISerendipityCore.StorageProtocol.ARWEAVE,
      totalMax: 100,
      startDate: start,
      endDate: end,
      tokenVariations: 5,
      location: "arweaveHash1",
      paymentReceiver: payable(creator),
      cost: 1,
      erc20: zeroAddress,
      signingAddress: signingAddress
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

    IERC1155SerendipityCore.ClaimParameters memory claimP = IERC1155SerendipityCore.ClaimParameters({
      storageProtocol: ISerendipityCore.StorageProtocol.ARWEAVE,
      totalMax: 1,
      startDate: start,
      endDate: end,
      tokenVariations: 5,
      location: "arweaveHash1",
      paymentReceiver: payable(creator),
      cost: 1,
      erc20: zeroAddress,
      signingAddress: signingAddress
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);
    example.mintReserve{ value: 1 + MINT_FEE }(address(creatorCore1), 1, 1);
    vm.stopPrank();

    vm.startPrank(other);
    vm.expectRevert(ISerendipityCore.ClaimSoldOut.selector);
    example.mintReserve{ value: 1 + MINT_FEE }(address(creatorCore1), 1, 1);
    vm.stopPrank();
  }

  function testMintReserveNone() public {
    vm.startPrank(creator);

    uint48 start = 0;
    uint48 end = uint48(block.timestamp) + 2000;

    IERC1155SerendipityCore.ClaimParameters memory claimP = IERC1155SerendipityCore.ClaimParameters({
      storageProtocol: ISerendipityCore.StorageProtocol.ARWEAVE,
      totalMax: 1,
      startDate: start,
      endDate: end,
      tokenVariations: 5,
      location: "arweaveHash1",
      paymentReceiver: payable(creator),
      cost: 1,
      erc20: zeroAddress,
      signingAddress: signingAddress
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);
    vm.expectRevert(ISerendipityCore.InvalidMintCount.selector);
    example.mintReserve{ value: 1 + MINT_FEE }(address(creatorCore1), 1, 0);
    vm.stopPrank();
  }

  function testMintReserveTooMany() public {
    vm.startPrank(creator);

    uint48 start = 0;
    uint48 end = uint48(block.timestamp) + 2000;

    IERC1155SerendipityCore.ClaimParameters memory claimP = IERC1155SerendipityCore.ClaimParameters({
      storageProtocol: ISerendipityCore.StorageProtocol.ARWEAVE,
      totalMax: 0,
      startDate: start,
      endDate: end,
      tokenVariations: 2,
      location: "arweaveHash1",
      paymentReceiver: payable(creator),
      cost: 1,
      erc20: zeroAddress,
      signingAddress: signingAddress
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);
    vm.stopPrank();
    vm.startPrank(other);
    example.mintReserve{ value: 1 + MINT_FEE }(address(creatorCore1), 1, 1);
    vm.stopPrank();

    vm.startPrank(creator);
    vm.expectRevert(ISerendipityCore.InvalidMintCount.selector);
    example.mintReserve{ value: (1 + MINT_FEE) * MAX_UINT_32 }(address(creatorCore1), 1, MAX_UINT_32);

    // max out mints
    example.mintReserve{ value: (1 + MINT_FEE) * (MAX_UINT_32 - 1) }(address(creatorCore1), 1, MAX_UINT_32 - 1);

    // try to mint one more
    vm.expectRevert(ISerendipityCore.TooManyRequested.selector);
    example.mintReserve{ value: 1 + MINT_FEE }(address(creatorCore1), 1, 1);
    vm.stopPrank();
  }

  function testMintReserveDeliverTotalMax0() public {
    vm.startPrank(creator);

    uint48 start = 0;
    uint48 end = 0;

    IERC1155SerendipityCore.ClaimParameters memory claimP = IERC1155SerendipityCore.ClaimParameters({
      storageProtocol: ISerendipityCore.StorageProtocol.ARWEAVE,
      totalMax: 0,
      startDate: start,
      endDate: end,
      tokenVariations: 5,
      location: "arweaveHash1",
      paymentReceiver: payable(creator),
      cost: 1,
      erc20: zeroAddress,
      signingAddress: signingAddress
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);
    vm.stopPrank();

    // should be able to reserve mint even if totalMax is 0
    vm.startPrank(other);
    example.mintReserve{ value: 1 + MINT_FEE }(address(creatorCore1), 1, 1);
    vm.stopPrank();

    ISerendipityCore.ClaimMint[] memory mints = new ISerendipityCore.ClaimMint[](1);
    ISerendipityCore.VariationMint[] memory variationMints = new ISerendipityCore.VariationMint[](1);
    variationMints[0] = ISerendipityCore.VariationMint({ variationIndex: 1, amount: 1, recipient: other });
    mints[0] = ISerendipityCore.ClaimMint({
      creatorContractAddress: address(creatorCore1),
      instanceId: 1,
      variationMints: variationMints
    });

    bytes32 nonce = keccak256("nonce1");
    uint256 expiration = block.timestamp + 1000;
    (bytes memory signature, bytes32 message) = _createDeliverMintsSignature(mints, nonce, expiration);
    example.deliverMints(mints, signature, message, nonce, expiration);
  }

  function testMintReserveMoreThanAvailable() public {
    vm.startPrank(creator);

    uint48 start = 0;
    uint48 end = uint48(block.timestamp) + 2000;

    uint256 collectorBalanceBefore = address(other).balance;
    uint96 mintPrice = 1 ether;

    IERC1155SerendipityCore.ClaimParameters memory claimP = IERC1155SerendipityCore.ClaimParameters({
      storageProtocol: ISerendipityCore.StorageProtocol.ARWEAVE,
      totalMax: 4,
      startDate: start,
      endDate: end,
      tokenVariations: 5,
      location: "arweaveHash1",
      paymentReceiver: payable(creator),
      cost: mintPrice,
      erc20: zeroAddress,
      signingAddress: signingAddress
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
    Serendipity.UserMintDetails memory userMintDetails = example.getUserMints(other, address(creatorCore1), 1);
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

    IERC1155SerendipityCore.ClaimParameters memory claimP = IERC1155SerendipityCore.ClaimParameters({
      storageProtocol: ISerendipityCore.StorageProtocol.ARWEAVE,
      totalMax: 100,
      startDate: nowC,
      endDate: later,
      tokenVariations: 5,
      location: "arweaveHash1",
      paymentReceiver: payable(creator),
      cost: 1,
      erc20: zeroAddress,
      signingAddress: signingAddress
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);
    vm.stopPrank();

    ISerendipityCore.ClaimMint[] memory mints = new ISerendipityCore.ClaimMint[](1);
    ISerendipityCore.VariationMint[] memory variationMints = new ISerendipityCore.VariationMint[](1);
    variationMints[0] = ISerendipityCore.VariationMint({ variationIndex: 1, amount: 1, recipient: other });
    mints[0] = ISerendipityCore.ClaimMint({
      creatorContractAddress: address(creatorCore1),
      instanceId: 1,
      variationMints: variationMints
    });

    // Sign with a different private key (not the signing address)
    uint256 wrongPrivateKey = 0x2020202020202020202020202020202020202020202020202020202020202020;
    bytes32 nonce = keccak256("nonce1");
    uint256 expiration = block.timestamp + 1000;
    bytes32 message = keccak256(abi.encode(mints, nonce, expiration));
    bytes32 digest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", message));
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPrivateKey, digest);
    bytes memory signature = abi.encodePacked(r, s, v);

    vm.expectRevert(ISerendipityCore.InvalidSignature.selector);
    example.deliverMints(mints, signature, message, nonce, expiration);
  }

  function testDeliverMints() public {
    vm.startPrank(creator);

    uint48 nowC = uint48(block.timestamp);
    uint48 later = nowC + 1000;

    IERC1155SerendipityCore.ClaimParameters memory claimP = IERC1155SerendipityCore.ClaimParameters({
      storageProtocol: ISerendipityCore.StorageProtocol.ARWEAVE,
      totalMax: 100,
      startDate: nowC,
      endDate: later,
      tokenVariations: 5,
      location: "arweaveHash1",
      paymentReceiver: payable(creator),
      cost: 1,
      erc20: zeroAddress,
      signingAddress: signingAddress
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);
    example.mintReserve{ value: (1 + MINT_FEE) * 2 }(address(creatorCore1), 1, 2);
    vm.stopPrank();

    vm.startPrank(other2);
    example.mintReserve{ value: (1 + MINT_FEE) * 4 }(address(creatorCore1), 1, 4);
    vm.stopPrank();

    ISerendipityCore.ClaimMint[] memory mints = new ISerendipityCore.ClaimMint[](2);
    ISerendipityCore.VariationMint[] memory variationMints = new ISerendipityCore.VariationMint[](2);
    variationMints[0] = ISerendipityCore.VariationMint({ variationIndex: 1, amount: 2, recipient: other2 });
    variationMints[1] = ISerendipityCore.VariationMint({ variationIndex: 2, amount: 1, recipient: other });
    mints[0] = ISerendipityCore.ClaimMint({
      creatorContractAddress: address(creatorCore1),
      instanceId: 1,
      variationMints: variationMints
    });
    mints[1] = ISerendipityCore.ClaimMint({
      creatorContractAddress: address(creatorCore1),
      instanceId: 1,
      variationMints: variationMints
    });

    // revert for receiver with no reserved mints
    bytes32 nonce1 = keccak256("nonce1");
    uint256 expiration = block.timestamp + 1000;
    (bytes memory signature1, bytes32 message1) = _createDeliverMintsSignature(mints, nonce1, expiration);
    vm.expectRevert(ISerendipityCore.CannotMintMoreThanReserved.selector);
    example.deliverMints(mints, signature1, message1, nonce1, expiration);
    Serendipity.UserMintDetails memory otherMint = example.getUserMints(other, address(creatorCore1), 1);
    assertEq(otherMint.reservedCount, 0);
    assertEq(otherMint.deliveredCount, 0);
    Serendipity.UserMintDetails memory other2Mint = example.getUserMints(other2, address(creatorCore1), 1);
    assertEq(other2Mint.reservedCount, 4);
    assertEq(other2Mint.deliveredCount, 0);

    // deliver for valid receivers and mintCount
    ISerendipityCore.VariationMint[] memory variationMints2 = new ISerendipityCore.VariationMint[](2);
    variationMints2[0] = ISerendipityCore.VariationMint({ variationIndex: 1, amount: 1, recipient: creator });
    variationMints2[1] = ISerendipityCore.VariationMint({ variationIndex: 2, amount: 2, recipient: other2 });
    mints[0] = ISerendipityCore.ClaimMint({
      creatorContractAddress: address(creatorCore1),
      instanceId: 1,
      variationMints: variationMints2
    });
    mints[1] = ISerendipityCore.ClaimMint({
      creatorContractAddress: address(creatorCore1),
      instanceId: 1,
      variationMints: variationMints2
    });
    bytes32 nonce2 = keccak256("nonce2");
    (bytes memory signature2, bytes32 message2) = _createDeliverMintsSignature(mints, nonce2, expiration);
    example.deliverMints(mints, signature2, message2, nonce2, expiration);
    Serendipity.UserMintDetails memory creatorMints = example.getUserMints(creator, address(creatorCore1), 1);
    assertEq(creatorMints.deliveredCount, 2);
    assertEq(creatorMints.reservedCount, 2);
    Serendipity.UserMintDetails memory other2Mints = example.getUserMints(other2, address(creatorCore1), 1);
    assertEq(other2Mints.reservedCount, 4);
    assertEq(other2Mints.deliveredCount, 4);
  }

  function testTokenURI() public {
    vm.startPrank(creator);
    uint48 nowC = uint48(block.timestamp);
    uint48 later = nowC + 1000;
    uint totalMintPrice = 1 + MINT_FEE;

    IERC1155SerendipityCore.ClaimParameters memory claimP = IERC1155SerendipityCore.ClaimParameters({
      storageProtocol: ISerendipityCore.StorageProtocol.ARWEAVE,
      totalMax: 100,
      startDate: nowC,
      endDate: later,
      tokenVariations: 5,
      location: "arweaveHash1",
      paymentReceiver: payable(creator),
      cost: 1,
      erc20: zeroAddress,
      signingAddress: signingAddress
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
    // create another claim
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

    IERC1155SerendipityCore.ClaimParameters memory claimP = IERC1155SerendipityCore.ClaimParameters({
      storageProtocol: ISerendipityCore.StorageProtocol.ARWEAVE,
      totalMax: 100,
      startDate: nowC,
      endDate: later,
      tokenVariations: 5,
      location: "arweaveHash1",
      paymentReceiver: payable(creator),
      cost: 1,
      erc20: zeroAddress,
      signingAddress: signingAddress
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);

    // tokens with original location
    assertEq("https://arweave.net/arweaveHash1/1", creatorCore1.uri(1));
    assertEq("https://arweave.net/arweaveHash1/2", creatorCore1.uri(2));
    assertEq("https://arweave.net/arweaveHash1/3", creatorCore1.uri(3));
    assertEq("https://arweave.net/arweaveHash1/4", creatorCore1.uri(4));
    assertEq("https://arweave.net/arweaveHash1/5", creatorCore1.uri(5));

    // update tokenURI
    example.updateTokenURIParams(address(creatorCore1), 1, ISerendipityCore.StorageProtocol.ARWEAVE, "arweaveHashNEW");
    assertEq("https://arweave.net/arweaveHashNEW/1", creatorCore1.uri(1));
    assertEq("https://arweave.net/arweaveHashNEW/2", creatorCore1.uri(2));
    assertEq("https://arweave.net/arweaveHashNEW/3", creatorCore1.uri(3));
    assertEq("https://arweave.net/arweaveHashNEW/4", creatorCore1.uri(4));
    assertEq("https://arweave.net/arweaveHashNEW/5", creatorCore1.uri(5));
    vm.stopPrank();
  }

  function test_RevertWhen_InitializeClaimOnDeprecated() public {
    vm.startPrank(owner);
    example.deprecate(true);
    vm.stopPrank();

    vm.startPrank(creator);
    uint48 nowC = uint48(block.timestamp);
    uint48 later = nowC + 1000;
    IERC1155SerendipityCore.ClaimParameters memory claimP = IERC1155SerendipityCore.ClaimParameters({
      storageProtocol: ISerendipityCore.StorageProtocol.IPFS,
      location: "arweaveHash1",
      totalMax: 0,
      startDate: nowC,
      endDate: later,
      tokenVariations: 5,
      paymentReceiver: payable(other),
      cost: 1,
      erc20: zeroAddress,
      signingAddress: signingAddress
    });
    vm.expectRevert(ISerendipityCore.ContractDeprecated.selector);
    example.initializeClaim(address(creatorCore1), 1, claimP);
    vm.stopPrank();

    vm.startPrank(owner);
    example.deprecate(false);
    vm.stopPrank();

    vm.startPrank(creator);
    // can initialize claim after deprecation removal
    example.initializeClaim(address(creatorCore1), 1, claimP);
    vm.stopPrank();
  }

  function test_RevertWhen_UpdateClaimOnDeprecated() public {
    vm.startPrank(creator);
    uint48 nowC = uint48(block.timestamp);
    uint48 later = nowC + 1000;
    IERC1155SerendipityCore.ClaimParameters memory claimP = IERC1155SerendipityCore.ClaimParameters({
      storageProtocol: ISerendipityCore.StorageProtocol.ARWEAVE,
      location: "arweaveHash1",
      totalMax: 0,
      startDate: nowC,
      endDate: later,
      tokenVariations: 5,
      paymentReceiver: payable(other),
      cost: 1,
      erc20: zeroAddress,
      signingAddress: signingAddress
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);

    claimP.location = "arweaveHash2";
    claimP.totalMax = 10;
    claimP.startDate = 0;
    claimP.tokenVariations = 10;
    example.initializeClaim(address(creatorCore1), 2, claimP);
    vm.stopPrank();

    vm.startPrank(owner);
    example.deprecate(true);
    vm.stopPrank();

    vm.startPrank(creator);
    IERC1155SerendipityCore.UpdateClaimParameters memory claimU = IERC1155SerendipityCore.UpdateClaimParameters({
      totalMax: 0,
      storageProtocol: ISerendipityCore.StorageProtocol.ARWEAVE,
      startDate: 0,
      endDate: 0,
      location: "arweaveHash1",
      paymentReceiver: payable(creator),
      cost: 1
    });
    vm.expectRevert(ISerendipityCore.ContractDeprecated.selector);
    example.updateClaim(address(creatorCore1), 1, claimU);
    vm.expectRevert(ISerendipityCore.ContractDeprecated.selector);
    example.updateClaim(address(creatorCore1), 2, claimU);
    vm.stopPrank();

    vm.startPrank(owner);
    example.deprecate(false);
    vm.stopPrank();

    vm.startPrank(creator);
    // run without reverts
    example.updateClaim(address(creatorCore1), 1, claimU);
    example.updateClaim(address(creatorCore1), 2, claimU);
    vm.stopPrank();
  }

  function test_Deprecate() public {
    assertEq(example.deprecated(), false);

    vm.startPrank(owner);
    example.deprecate(true);
    assertEq(example.deprecated(), true);
    example.deprecate(false);
    assertEq(example.deprecated(), false);
    vm.stopPrank();


    // Cannot call deprecate if not an admin
    vm.startPrank(other);
    vm.expectRevert(bytes("AdminControl: Must be owner or admin"));
    example.deprecate(true);
    vm.stopPrank();

    vm.startPrank(owner);
    example.approveAdmin(other);
    vm.stopPrank();

    vm.startPrank(other);
    example.deprecate(true);
    assertEq(example.deprecated(), true);
    vm.stopPrank();

    vm.startPrank(owner);
    example.revokeAdmin(other);
    vm.stopPrank();

    vm.startPrank(other);
    vm.expectRevert(bytes("AdminControl: Must be owner or admin"));
    example.deprecate(false);
    assertEq(example.deprecated(), true);
    vm.stopPrank();
  }
}
