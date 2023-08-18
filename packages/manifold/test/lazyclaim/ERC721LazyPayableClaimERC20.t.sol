// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../contracts/lazyclaim/ERC721LazyPayableClaim.sol";
import "../../contracts/lazyclaim/IERC721LazyPayableClaim.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC721Creator.sol";
import "../../contracts/libraries/delegation-registry/DelegationRegistry.sol";
import "../mocks/Mock.sol";
import "../../lib/murky/src/Merkle.sol";

contract ERC721LazyPayableClaimERC20Test is Test {
  ERC721LazyPayableClaim public example;
  ERC721Creator public creatorCore;
  DelegationRegistry public delegationRegistry;
  MockManifoldMembership public manifoldMembership;
  MockERC20 public mockERC20;
  Merkle public merkle;

  address public owner = 0x6140F00e4Ff3936702E68744f2b5978885464cbB;
  address public other = 0xc78Dc443c126af6E4f6Ed540c1e740C1b5be09cd;
  address public other2 = 0x80AAC46bbd3C2FcE33681541a52CacBEd14bF425;
  address public other3 = 0x5174cD462b60c536eb51D4ceC1D561D3Ea31004F;

  address public zeroAddress = address(0);

  function setUp() public {
    vm.startPrank(owner);
    creatorCore = new ERC721Creator("Token", "NFT");
    delegationRegistry = new DelegationRegistry();
    example = new ERC721LazyPayableClaim(owner, address(delegationRegistry));
    manifoldMembership = new MockManifoldMembership();
    example.setMembershipAddress(address(manifoldMembership));

    creatorCore.registerExtension(address(example), "override");

    mockERC20 = new MockERC20("Test", "test");
    merkle = new Merkle();

    vm.deal(owner, 10 ether);
    vm.deal(other, 10 ether);
    vm.deal(other2, 10 ether);
    vm.deal(other3, 10 ether);
    vm.stopPrank();
  }

  function testFunctionality() public {
    vm.startPrank(owner);
    uint48 nowC = uint48(block.timestamp);
    uint48 later = nowC + 1000;
    uint mintFee = example.MINT_FEE_MERKLE();
    uint mintFeeNon = example.MINT_FEE();

    bytes32[] memory allowListTuples = new bytes32[](3);
    allowListTuples[0] = keccak256(abi.encodePacked(other, uint32(0)));
    allowListTuples[1] = keccak256(abi.encodePacked(other, uint32(1)));
    allowListTuples[2] = keccak256(abi.encodePacked(other, uint32(2)));

    IERC721LazyPayableClaim.ClaimParameters memory claimP = IERC721LazyPayableClaim.ClaimParameters({
      merkleRoot: merkle.getRoot(allowListTuples),
      location: "arweaveHash1",
      totalMax: 3,
      walletMax: 0,
      startDate: nowC,
      endDate: later,
      storageProtocol: ILazyPayableClaim.StorageProtocol.ARWEAVE,
      identical: true,
      cost: 100,
      paymentReceiver: payable(owner),
      erc20: address(mockERC20),
      signingAddress: address(0)
    });

    example.initializeClaim(address(creatorCore), 1, claimP);

    // Initialize a second claim - with optional parameters disabled
    claimP.totalMax = 0;
    claimP.walletMax = 0;
    claimP.startDate = 0;
    claimP.endDate = 0;
    claimP.cost = 200;
    claimP.merkleRoot = "";
    example.initializeClaim(address(creatorCore), 2, claimP);

    bytes32[] memory merkleProof1 = merkle.getProof(allowListTuples, uint32(0));
    bytes32[] memory merkleProof2 = merkle.getProof(allowListTuples, uint32(1));
    bytes32[] memory merkleProof3 = merkle.getProof(allowListTuples, uint32(2));

    vm.stopPrank();
    vm.startPrank(other);
    // Cannot mint with no approvals
    vm.expectRevert("ERC20: insufficient allowance");
    example.mint(address(creatorCore), 1, 0, merkleProof1, other);

    uint32[] memory amounts = new uint32[](1);
    amounts[0] = 0;
    bytes32[][] memory merkleProofs = new bytes32[][](1);
    merkleProofs[0] = merkleProof1;

    vm.expectRevert("ERC20: insufficient allowance");
    example.mintBatch(address(creatorCore), 1, 1, amounts, merkleProofs, other);

    mockERC20.approve(address(example), 1000);

    // Cannot mint with no erc20 balance
    vm.expectRevert("ERC20: transfer amount exceeds balance");
    example.mint{ value: mintFee }(address(creatorCore), 1, 0, merkleProof1, other);
    vm.expectRevert("ERC20: transfer amount exceeds balance");
    example.mintBatch(address(creatorCore), 1, 1, amounts, merkleProofs, other);

    // Mint erc20 tokens
    mockERC20.fakeMint(other, 1000);

    // Mint a token (merkle)
    example.mint{ value: mintFee }(address(creatorCore), 1, 0, merkleProof1, other);

    IERC721LazyPayableClaim.Claim memory claim = example.getClaim(address(creatorCore), 1);
    assertEq(claim.total, 1);
    assertEq(900, mockERC20.balanceOf(other));
    assertEq(100, mockERC20.balanceOf(owner));
    assertEq(1, creatorCore.balanceOf(other));

    // Mint batch (merkle)
    amounts = new uint32[](2);
    amounts[0] = 1;
    amounts[1] = 2;
    merkleProofs = new bytes32[][](2);
    merkleProofs[0] = merkleProof2;
    merkleProofs[1] = merkleProof3;
    vm.expectRevert("Invalid amount");
    example.mintBatch{ value: mintFee }(address(creatorCore), 1, 2, amounts, merkleProofs, other);
    vm.expectRevert("Invalid amount");
    example.mintBatch{ value: mintFeeNon * 2 }(address(creatorCore), 1, 2, amounts, merkleProofs, other);
    example.mintBatch{ value: mintFee * 2 }(address(creatorCore), 1, 2, amounts, merkleProofs, other);

    assertEq(700, mockERC20.balanceOf(other));
    assertEq(300, mockERC20.balanceOf(owner));
    assertEq(3, creatorCore.balanceOf(other));

    // Mint a token
    bytes32[] memory blankProof = new bytes32[](0);
    example.mint{ value: mintFee }(address(creatorCore), 2, 0, blankProof, other);
    claim = example.getClaim(address(creatorCore), 2);
    assertEq(claim.total, 1);
    assertEq(500, mockERC20.balanceOf(other));
    assertEq(500, mockERC20.balanceOf(owner));
    assertEq(4, creatorCore.balanceOf(other));

    bytes32[][] memory blankProofs = new bytes32[][](0);
    uint32[] memory blankAmounts = new uint32[](0);

    vm.expectRevert("Invalid amount");
    example.mintBatch{ value: mintFee }(address(creatorCore), 2, 2, blankAmounts, blankProofs, other);
    example.mintBatch{ value: mintFee * 2 }(address(creatorCore), 2, 2, blankAmounts, blankProofs, other);
    assertEq(100, mockERC20.balanceOf(other));
    assertEq(900, mockERC20.balanceOf(owner));
    assertEq(6, creatorCore.balanceOf(other));

    vm.stopPrank();
  }

  function testMembership() public {
    vm.startPrank(owner);
    uint48 nowC = uint48(block.timestamp);
    uint48 later = nowC + 1000;

    bytes32[] memory allowListTuples = new bytes32[](2);
    allowListTuples[0] = keccak256(abi.encodePacked(other, uint32(0)));
    allowListTuples[1] = keccak256(abi.encodePacked(other, uint32(1)));
    IERC721LazyPayableClaim.ClaimParameters memory claimP = IERC721LazyPayableClaim.ClaimParameters({
      merkleRoot: merkle.getRoot(allowListTuples),
      location: "arweaveHash1",
      totalMax: 3,
      walletMax: 0,
      startDate: nowC,
      endDate: later,
      storageProtocol: ILazyPayableClaim.StorageProtocol.ARWEAVE,
      identical: true,
      cost: 100,
      paymentReceiver: payable(owner),
      erc20: address(mockERC20),
      signingAddress: address(0)
    });

    example.initializeClaim(address(creatorCore), 1, claimP);

    // Initialize a second claim - with optional parameters disabled
    claimP.totalMax = 0;
    claimP.walletMax = 0;
    claimP.startDate = 0;
    claimP.endDate = 0;
    claimP.cost = 200;
    claimP.merkleRoot = "";
    example.initializeClaim(address(creatorCore), 2, claimP);

    bytes32[] memory merkleProof1 = merkle.getProof(allowListTuples, uint32(0));

    manifoldMembership.setMember(other, true);
    vm.stopPrank();
    vm.startPrank(other);

    mockERC20.approve(address(example), 1000);
    mockERC20.fakeMint(other, 1000);

    // Mint a token (merkle)
    example.mint(address(creatorCore), 1, 0, merkleProof1, other);

    IERC721LazyPayableClaim.Claim memory claim = example.getClaim(address(creatorCore), 1);
    assertEq(claim.total, 1);
    assertEq(900, mockERC20.balanceOf(other));
    assertEq(100, mockERC20.balanceOf(owner));
    assertEq(1, creatorCore.balanceOf(other));
  }

  function testProxyMint() public {
    vm.startPrank(owner);
    uint48 nowC = uint48(block.timestamp);
    uint48 later = nowC + 1000;
    uint mintFee = example.MINT_FEE_MERKLE();
    uint mintFeeNon = example.MINT_FEE();

    IERC721LazyPayableClaim.ClaimParameters memory claimP = IERC721LazyPayableClaim.ClaimParameters({
      merkleRoot: "",
      location: "arweaveHash1",
      totalMax: 3,
      walletMax: 0,
      startDate: nowC,
      endDate: later,
      storageProtocol: ILazyPayableClaim.StorageProtocol.ARWEAVE,
      identical: true,
      cost: 100,
      paymentReceiver: payable(owner),
      erc20: address(mockERC20),
      signingAddress: address(0)
    });

    example.initializeClaim(address(creatorCore), 1, claimP);

    bytes32[] memory allowListTuples = new bytes32[](2);
    allowListTuples[0] = keccak256(abi.encodePacked(other2, uint32(0)));
    allowListTuples[1] = keccak256(abi.encodePacked(other2, uint32(1)));

    // Initialize a second claim - with optional parameters disabled
    claimP.merkleRoot = merkle.getRoot(allowListTuples);
    example.initializeClaim(address(creatorCore), 3, claimP);

    // The sender is a member, but proxy minting will ignore the fact they are a member
    manifoldMembership.setMember(other, true);
    vm.stopPrank();
    vm.startPrank(other);
    // Mint erc20 tokens
    mockERC20.approve(address(example), 1000);
    mockERC20.fakeMint(other, 1000);

    uint32[] memory amounts = new uint32[](0);
    bytes32[][] memory merkleProofs = new bytes32[][](0);

    // Perform a mint on the claim
    uint startingBalance = other.balance;
    example.mintProxy{ value: mintFee * 3 }(address(creatorCore), 1, 3, amounts, merkleProofs, other2);
    assertEq(3, creatorCore.balanceOf(other2));
    // Ensure funds taken from message sender
    // This fuzzy number is how much gas was used. Cannot figure out how to do it in forge
    assertEq(startingBalance - mintFeeNon * 3 - 570000000000000, other.balance);
    assertEq(700, mockERC20.balanceOf(other));
    assertEq(300, mockERC20.balanceOf(owner));

    // Mint merkle claims
    bytes32[] memory merkleProof1 = merkle.getProof(allowListTuples, uint32(0));
    bytes32[] memory merkleProof2 = merkle.getProof(allowListTuples, uint32(1));
    // Should fail if standard fee is provided
    amounts = new uint32[](2);
    amounts[0] = 0;
    amounts[1] = 1;

    merkleProofs = new bytes32[][](2);
    merkleProofs[0] = merkleProof1;
    merkleProofs[1] = merkleProof2;
    vm.expectRevert("Invalid amount");
    example.mintProxy{ value: mintFeeNon * 2 }(address(creatorCore), 3, 2, amounts, merkleProofs, other2);

    example.mintProxy{ value: mintFee * 2 }(address(creatorCore), 3, 2, amounts, merkleProofs, other2);
    assertEq(5, creatorCore.balanceOf(other2));
    // Ensure funds taken from message sender
    assertEq(500, mockERC20.balanceOf(other));
    assertEq(500, mockERC20.balanceOf(owner));
  }
}
