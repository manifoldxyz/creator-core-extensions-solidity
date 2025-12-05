// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../contracts/gachaclaims/IERC1155SerendipityCore.sol";
import "../../contracts/gachaclaims/ERC1155SerendipityUSDC.sol";
import "../../contracts/gachaclaims/ISerendipityCore.sol";
import "../../contracts/gachaclaims/ISerendipityUSDC.sol";
import "../../contracts/gachaclaims/SerendipityUSDC.sol";

import "@manifoldxyz/creator-core-solidity/contracts/ERC1155Creator.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../mocks/Mock.sol";

contract ERC1155SerendipityUSDCTest is Test {
  using SafeMath for uint256;

  ERC1155SerendipityUSDC public example;
  ERC1155Creator public creatorCore1;
  ERC1155Creator public creatorCore2;
  MockERC20 public mockUSDC;

  address public creator = 0xc78Dc443c126af6E4f6Ed540c1e740C1b5be09cd;
  address public owner = 0x6140F00e4Ff3936702E68744f2b5978885464cbB;
  address public other = 0x5174cD462b60c536eb51D4ceC1D561D3Ea31004F;
  address public other2 = 0x80AAC46bbd3C2FcE33681541a52CacBEd14bF425;

  address public zeroAddress = address(0);

  uint256 privateKey = 0x1010101010101010101010101010101010101010101010101010101010101010;
  address public signingAddress;

  uint32 MAX_UINT_32 = 0xffffffff;
  uint256 public MINT_FEE = 500000; // 0.5 USDC (6 decimals)
  uint96 public MINT_COST = 1000000; // 1 USDC (6 decimals)

  // Test setup
  function setUp() public {
    signingAddress = vm.addr(privateKey);

    vm.startPrank(creator);
    creatorCore1 = new ERC1155Creator("Token1", "NFT1");
    creatorCore2 = new ERC1155Creator("Token2", "NFT2");
    vm.stopPrank();

    vm.startPrank(owner);
    mockUSDC = new MockERC20("USD Coin", "USDC");
    example = new ERC1155SerendipityUSDC(owner, address(mockUSDC));
    example.setMintFee(MINT_FEE);
    vm.stopPrank();

    vm.startPrank(creator);
    creatorCore1.registerExtension(address(example), "override");
    creatorCore2.registerExtension(address(example), "override");
    vm.stopPrank();

    // Mint USDC to test accounts
    mockUSDC.fakeMint(creator, 1000000000); // 1000 USDC
    mockUSDC.fakeMint(other, 1000000000);
    mockUSDC.fakeMint(other2, 1000000000);
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

  function testConstructorRevertOnZeroAddress() public {
    vm.startPrank(owner);
    vm.expectRevert(ISerendipityUSDC.InvalidUSDCAddress.selector);
    new ERC1155SerendipityUSDC(owner, address(0));
    vm.stopPrank();
  }

  function testAccess() public {
    vm.startPrank(other);
    // Must be admin
    vm.expectRevert();
    example.withdraw(payable(other), 20);
    vm.expectRevert("AdminControl: Must be owner or admin");
    example.setSigner(other);
    vm.expectRevert("AdminControl: Must be owner or admin");
    example.setMintFee(100);

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
      cost: MINT_COST,
      erc20: address(mockUSDC),
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

  function testSetMintFee() public {
    vm.startPrank(owner);
    assertEq(example.MINT_FEE(), MINT_FEE);
    example.setMintFee(1000000);
    assertEq(example.MINT_FEE(), 1000000);
    example.setMintFee(0);
    assertEq(example.MINT_FEE(), 0);
    vm.stopPrank();
  }

  function testInitializeClaimInvalidUSDCAddress() public {
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
      cost: MINT_COST,
      erc20: address(0), // Invalid - should be USDC address
      signingAddress: signingAddress
    });

    vm.expectRevert(ISerendipityUSDC.InvalidUSDCAddress.selector);
    example.initializeClaim(address(creatorCore1), 1, claimP);

    // Also test with a different ERC20 address
    claimP.erc20 = address(0x1234567890123456789012345678901234567890);
    vm.expectRevert(ISerendipityUSDC.InvalidUSDCAddress.selector);
    example.initializeClaim(address(creatorCore1), 1, claimP);

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
      cost: MINT_COST,
      erc20: address(mockUSDC),
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
      cost: MINT_COST,
      erc20: address(mockUSDC),
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
    assertEq(claim.cost, MINT_COST);
    assertEq(claim.erc20, address(mockUSDC));
    assertEq(claim.startingTokenId, 2);

    vm.stopPrank();
  }

  function testMintReserveNoApproval() public {
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
      cost: MINT_COST,
      erc20: address(mockUSDC),
      signingAddress: signingAddress
    });

    example.initializeClaim(address(creatorCore1), 1, claimP);
    vm.stopPrank();

    vm.startPrank(other);
    // No approval - should fail
    vm.expectRevert("ERC20: insufficient allowance");
    example.mintReserve(address(creatorCore1), 1, 1, other);
    vm.stopPrank();
  }

  function testMintReserveInsufficientBalance() public {
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
      cost: MINT_COST,
      erc20: address(mockUSDC),
      signingAddress: signingAddress
    });

    example.initializeClaim(address(creatorCore1), 1, claimP);
    vm.stopPrank();

    // Create a new address with no USDC
    address poorUser = address(0x999);
    vm.startPrank(poorUser);
    mockUSDC.approve(address(example), type(uint256).max);
    vm.expectRevert("ERC20: transfer amount exceeds balance");
    example.mintReserve(address(creatorCore1), 1, 1, poorUser);
    vm.stopPrank();
  }

  function testMintReserveSuccess() public {
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
      cost: MINT_COST,
      erc20: address(mockUSDC),
      signingAddress: signingAddress
    });

    example.initializeClaim(address(creatorCore1), 1, claimP);
    vm.stopPrank();

    uint256 creatorBalanceBefore = mockUSDC.balanceOf(creator);
    uint256 otherBalanceBefore = mockUSDC.balanceOf(other);
    uint256 extensionBalanceBefore = mockUSDC.balanceOf(address(example));

    vm.startPrank(other);
    mockUSDC.approve(address(example), (MINT_COST + MINT_FEE) * 2);
    example.mintReserve(address(creatorCore1), 1, 2, other);
    vm.stopPrank();

    // Check balances
    assertEq(mockUSDC.balanceOf(creator), creatorBalanceBefore + MINT_COST * 2);
    assertEq(mockUSDC.balanceOf(other), otherBalanceBefore - (MINT_COST + MINT_FEE) * 2);
    assertEq(mockUSDC.balanceOf(address(example)), extensionBalanceBefore + MINT_FEE * 2);

    // Check user mint details
    SerendipityUSDC.UserMintDetails memory userMintDetails = example.getUserMints(other, address(creatorCore1), 1);
    assertEq(userMintDetails.reservedCount, 2);
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
      cost: MINT_COST,
      erc20: address(mockUSDC),
      signingAddress: signingAddress
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);
    vm.stopPrank();

    vm.startPrank(other);
    mockUSDC.approve(address(example), (MINT_COST + MINT_FEE));
    vm.expectRevert(ISerendipityCore.ClaimInactive.selector);
    example.mintReserve(address(creatorCore1), 1, 1, other);
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
      cost: MINT_COST,
      erc20: address(mockUSDC),
      signingAddress: signingAddress
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);
    vm.stopPrank();

    vm.startPrank(other);
    mockUSDC.approve(address(example), (MINT_COST + MINT_FEE));
    example.mintReserve(address(creatorCore1), 1, 1, other);
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
      cost: MINT_COST,
      erc20: address(mockUSDC),
      signingAddress: signingAddress
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);
    mockUSDC.approve(address(example), (MINT_COST + MINT_FEE));
    example.mintReserve(address(creatorCore1), 1, 1, creator);
    vm.stopPrank();

    vm.startPrank(other);
    mockUSDC.approve(address(example), (MINT_COST + MINT_FEE));
    vm.expectRevert(ISerendipityCore.ClaimSoldOut.selector);
    example.mintReserve(address(creatorCore1), 1, 1, other);
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
      cost: MINT_COST,
      erc20: address(mockUSDC),
      signingAddress: signingAddress
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);
    mockUSDC.approve(address(example), (MINT_COST + MINT_FEE));
    vm.expectRevert(ISerendipityCore.InvalidMintCount.selector);
    example.mintReserve(address(creatorCore1), 1, 0, creator);
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
      cost: MINT_COST,
      erc20: address(mockUSDC),
      signingAddress: signingAddress
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);
    vm.stopPrank();

    // should be able to reserve mint even if totalMax is 0
    vm.startPrank(other);
    mockUSDC.approve(address(example), (MINT_COST + MINT_FEE));
    example.mintReserve(address(creatorCore1), 1, 1, other);
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

    uint256 collectorBalanceBefore = mockUSDC.balanceOf(other);

    IERC1155SerendipityCore.ClaimParameters memory claimP = IERC1155SerendipityCore.ClaimParameters({
      storageProtocol: ISerendipityCore.StorageProtocol.ARWEAVE,
      totalMax: 4,
      startDate: start,
      endDate: end,
      tokenVariations: 5,
      location: "arweaveHash1",
      paymentReceiver: payable(creator),
      cost: MINT_COST,
      erc20: address(mockUSDC),
      signingAddress: signingAddress
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);
    mockUSDC.approve(address(example), (MINT_COST + MINT_FEE));
    example.mintReserve(address(creatorCore1), 1, 1, creator);
    uint256 creatorBalanceBefore = mockUSDC.balanceOf(creator);
    uint256 extensionBalanceBefore = mockUSDC.balanceOf(address(example));
    vm.stopPrank();

    vm.startPrank(other);
    // Approve for 5 mints but only 3 available
    mockUSDC.approve(address(example), (MINT_COST + MINT_FEE) * 5);
    example.mintReserve(address(creatorCore1), 1, 5, other);
    vm.stopPrank();

    // Confirm user - should only have reserved 3 (since 1 was already minted)
    SerendipityUSDC.UserMintDetails memory userMintDetails = example.getUserMints(other, address(creatorCore1), 1);
    assertEq(userMintDetails.reservedCount, 3);

    // Check payment balances: should only have charged for 3 mints
    assertEq(mockUSDC.balanceOf(creator), creatorBalanceBefore + MINT_COST * 3);
    assertEq(mockUSDC.balanceOf(other), collectorBalanceBefore - ((MINT_COST + MINT_FEE) * 3));
    assertEq(mockUSDC.balanceOf(address(example)), extensionBalanceBefore + MINT_FEE * 3);
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
      cost: MINT_COST,
      erc20: address(mockUSDC),
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
      cost: MINT_COST,
      erc20: address(mockUSDC),
      signingAddress: signingAddress
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);
    mockUSDC.approve(address(example), (MINT_COST + MINT_FEE) * 2);
    example.mintReserve(address(creatorCore1), 1, 2, creator);
    vm.stopPrank();

    vm.startPrank(other2);
    mockUSDC.approve(address(example), (MINT_COST + MINT_FEE) * 4);
    example.mintReserve(address(creatorCore1), 1, 4, other2);
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
    SerendipityUSDC.UserMintDetails memory otherMint = example.getUserMints(other, address(creatorCore1), 1);
    assertEq(otherMint.reservedCount, 0);
    assertEq(otherMint.deliveredCount, 0);
    SerendipityUSDC.UserMintDetails memory other2Mint = example.getUserMints(other2, address(creatorCore1), 1);
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
    SerendipityUSDC.UserMintDetails memory creatorMints = example.getUserMints(creator, address(creatorCore1), 1);
    assertEq(creatorMints.deliveredCount, 2);
    assertEq(creatorMints.reservedCount, 2);
    SerendipityUSDC.UserMintDetails memory other2Mints = example.getUserMints(other2, address(creatorCore1), 1);
    assertEq(other2Mints.reservedCount, 4);
    assertEq(other2Mints.deliveredCount, 4);
  }

  function testWithdraw() public {
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
      cost: MINT_COST,
      erc20: address(mockUSDC),
      signingAddress: signingAddress
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);
    mockUSDC.approve(address(example), (MINT_COST + MINT_FEE) * 5);
    example.mintReserve(address(creatorCore1), 1, 5, creator);
    vm.stopPrank();

    // Extension should have collected MINT_FEE * 5
    uint256 extensionBalance = mockUSDC.balanceOf(address(example));
    assertEq(extensionBalance, MINT_FEE * 5);

    // Withdraw to owner
    uint256 ownerBalanceBefore = mockUSDC.balanceOf(owner);
    vm.startPrank(owner);
    example.withdraw(payable(owner), MINT_FEE * 5);
    vm.stopPrank();

    assertEq(mockUSDC.balanceOf(owner), ownerBalanceBefore + MINT_FEE * 5);
    assertEq(mockUSDC.balanceOf(address(example)), 0);
  }

  function testTokenURI() public {
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
      cost: MINT_COST,
      erc20: address(mockUSDC),
      signingAddress: signingAddress
    });

    example.initializeClaim(address(creatorCore1), 1, claimP);
    mockUSDC.approve(address(example), (MINT_COST + MINT_FEE));
    example.mintReserve(address(creatorCore1), 1, 1, creator);

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
    mockUSDC.approve(address(example), (MINT_COST + MINT_FEE) * 2);
    example.mintReserve(address(creatorCore1), 1, 2, other);
    vm.stopPrank();
    vm.startPrank(other2);
    mockUSDC.approve(address(example), (MINT_COST + MINT_FEE));
    example.mintReserve(address(creatorCore1), 1, 1, other2);
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
      cost: MINT_COST,
      erc20: address(mockUSDC),
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
      cost: MINT_COST,
      erc20: address(mockUSDC),
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

  function testSupportsInterface() public {
    // Check that the contract supports ISerendipityUSDC interface
    bytes4 iSerendipityUSDCInterfaceId = type(ISerendipityUSDC).interfaceId;
    assertTrue(example.supportsInterface(iSerendipityUSDCInterfaceId));

    // Check that it also supports ISerendipityCore
    bytes4 iSerendipityCoreInterfaceId = type(ISerendipityCore).interfaceId;
    assertTrue(example.supportsInterface(iSerendipityCoreInterfaceId));

    // Check IERC1155SerendipityCore
    bytes4 iERC1155SerenditpyCoreInterfaceId = type(IERC1155SerendipityCore).interfaceId;
    assertTrue(example.supportsInterface(iERC1155SerenditpyCoreInterfaceId));
  }

  function testMintReserveNotPayable() public {
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
      cost: MINT_COST,
      erc20: address(mockUSDC),
      signingAddress: signingAddress
    });

    example.initializeClaim(address(creatorCore1), 1, claimP);
    vm.stopPrank();

    vm.startPrank(other);
    mockUSDC.approve(address(example), (MINT_COST + MINT_FEE));

    // This should work - mintReserve is not payable for USDC version
    example.mintReserve(address(creatorCore1), 1, 1, other);

    // Verify the mint happened
    SerendipityUSDC.UserMintDetails memory userMintDetails = example.getUserMints(other, address(creatorCore1), 1);
    assertEq(userMintDetails.reservedCount, 1);
    vm.stopPrank();
  }
}
