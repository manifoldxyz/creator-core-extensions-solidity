// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../contracts/lazyclaim/ERC721LazyPayableClaim.sol";
import "../../contracts/lazyclaim/IERC721LazyPayableClaim.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC721Creator.sol";
import "../../contracts/libraries/delegation-registry/DelegationRegistry.sol";
import "../mocks/Mock.sol";
import "../../lib/murky/src/Merkle.sol";

contract ERC721LazyPayableClaimTest is Test {
  ERC721LazyPayableClaim public example;
  ERC721Creator public creatorCore;
  DelegationRegistry public delegationRegistry;
  MockManifoldMembership public manifoldMembership;
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
    merkle = new Merkle();

    vm.deal(owner, 10 ether);
    vm.deal(other, 10 ether);
    vm.deal(other2, 10 ether);
    vm.deal(other3, 10 ether);
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

    IERC721LazyPayableClaim.ClaimParameters memory claimP = IERC721LazyPayableClaim.ClaimParameters({
      merkleRoot: "",
      location: "arweaveHash1",
      totalMax: 10,
      walletMax: 1,
      startDate: nowC,
      endDate: later,
      storageProtocol: ILazyPayableClaim.StorageProtocol.ARWEAVE,
      identical: true,
      cost: 1,
      paymentReceiver: payable(other),
      erc20: zeroAddress,
      signingAddress: zeroAddress
    });
    // Must be admin
    vm.expectRevert();
    example.initializeClaim(address(creatorCore), 1, claimP);
    // Succeeds because is admin
    vm.stopPrank();
    vm.startPrank(owner);
    example.initializeClaim(address(creatorCore), 1, claimP);

    // Update, not admin
    vm.stopPrank();
    vm.startPrank(other);
    vm.expectRevert();
    example.updateClaim(address(creatorCore), 1, claimP);

    vm.expectRevert();
    example.updateTokenURIParams(address(creatorCore), 1, ILazyPayableClaim.StorageProtocol.IPFS, true, "");

    vm.expectRevert();
    example.extendTokenURI(address(creatorCore), 2, "");

    vm.stopPrank();
    vm.startPrank(owner);

    claimP.totalMax = 9;
    claimP.paymentReceiver = payable(owner);
    example.updateClaim(address(creatorCore), 1, claimP);

    ERC721LazyPayableClaim.Claim memory claim = example.getClaim(address(creatorCore), 1);

    assertEq(claim.merkleRoot, "");
    assertEq(claim.location, "arweaveHash1");
    assertEq(claim.totalMax, 9);
    assertEq(claim.walletMax, 1);
    assertEq(claim.startDate, nowC);
    assertEq(claim.endDate, later);
    assertEq(claim.cost, 1);
    assertEq(claim.paymentReceiver, owner);

    // Mint one so token exists...
    example.mint{ value: mintFee + 1 }(address(creatorCore), 1, 0, new bytes32[](0), owner);

    assertEq("https://arweave.net/arweaveHash1", creatorCore.tokenURI(1));

    example.updateTokenURIParams(address(creatorCore), 1, ILazyPayableClaim.StorageProtocol.ARWEAVE, true, "arweaveHash3");
    assertEq("https://arweave.net/arweaveHash3", creatorCore.tokenURI(1));
    // Extend uri
    vm.expectRevert();
    example.extendTokenURI(address(creatorCore), 1, "");
    example.updateTokenURIParams(address(creatorCore), 1, ILazyPayableClaim.StorageProtocol.NONE, true, "part1");
    example.extendTokenURI(address(creatorCore), 1, "part2");
    assertEq("part1part2", creatorCore.tokenURI(1));

    vm.stopPrank();
  }

  function testinitializeClaimSanitization() public {
    vm.startPrank(owner);
    uint48 nowC = uint48(block.timestamp);
    uint48 later = nowC + 1000;

    IERC721LazyPayableClaim.ClaimParameters memory claimP = IERC721LazyPayableClaim.ClaimParameters({
      merkleRoot: "",
      location: "arweaveHash1",
      totalMax: 10,
      walletMax: 1,
      startDate: nowC,
      endDate: later,
      storageProtocol: ILazyPayableClaim.StorageProtocol.INVALID,
      identical: true,
      cost: 1,
      paymentReceiver: payable(other),
      erc20: zeroAddress,
      signingAddress: zeroAddress
    });

    vm.expectRevert("Cannot initialize with invalid storage protocol");
    example.initializeClaim(address(creatorCore), 1, claimP);

    claimP.startDate = nowC + 2000;
    claimP.storageProtocol = ILazyPayableClaim.StorageProtocol.ARWEAVE;
    vm.expectRevert("Cannot have startDate greater than or equal to endDate");
    example.initializeClaim(address(creatorCore), 1, claimP);

    claimP.startDate = nowC;
    claimP.merkleRoot = "0x0";
    vm.expectRevert("Cannot provide both walletMax and merkleRoot");
    example.initializeClaim(address(creatorCore), 1, claimP);

    claimP.merkleRoot = "";
    vm.expectRevert("Claim not initialized");
    example.updateClaim(address(creatorCore), 1, claimP);

    vm.stopPrank();
  }

  function testUpdateClaimSanitization() public {
    vm.startPrank(owner);
    uint48 nowC = uint48(block.timestamp);
    uint48 later = nowC + 1000;

    IERC721LazyPayableClaim.ClaimParameters memory claimP = IERC721LazyPayableClaim.ClaimParameters({
      merkleRoot: "",
      location: "arweaveHash1",
      totalMax: 10,
      walletMax: 1,
      startDate: nowC,
      endDate: later,
      storageProtocol: ILazyPayableClaim.StorageProtocol.ARWEAVE,
      identical: true,
      cost: 1,
      paymentReceiver: payable(other),
      erc20: zeroAddress,
      signingAddress: zeroAddress,
    });

    example.initializeClaim(address(creatorCore), 1, claimP);

    claimP.storageProtocol = ILazyPayableClaim.StorageProtocol.INVALID;
    vm.expectRevert("Cannot set invalid storage protocol");
    example.updateClaim(address(creatorCore), 1, claimP);

    claimP.startDate = nowC + 2000;
    claimP.storageProtocol = ILazyPayableClaim.StorageProtocol.ARWEAVE;
    vm.expectRevert("Cannot have startDate greater than or equal to endDate");
    example.updateClaim(address(creatorCore), 1, claimP);

    claimP.startDate = nowC;
    claimP.erc20 = 0x0000000000000000000000000000000000000001;
    vm.expectRevert("Cannot change payment token");
    example.updateClaim(address(creatorCore), 1, claimP);

    vm.stopPrank();
  }

  function testMerkleMint() public {
    vm.startPrank(owner);
    uint48 nowC = uint48(block.timestamp);
    uint48 later = nowC + 1000;

    bytes32[] memory allowListTuples = new bytes32[](4);
    allowListTuples[0] = keccak256(abi.encodePacked(owner, uint32(0)));
    allowListTuples[1] = keccak256(abi.encodePacked(other2, uint32(1)));
    allowListTuples[2] = keccak256(abi.encodePacked(other2, uint32(2)));
    allowListTuples[3] = keccak256(abi.encodePacked(other3, uint32(3)));

    IERC721LazyPayableClaim.ClaimParameters memory claimP = IERC721LazyPayableClaim.ClaimParameters({
      merkleRoot: merkle.getRoot(allowListTuples),
      location: "arweaveHash1",
      totalMax: 3,
      walletMax: 0,
      startDate: nowC,
      endDate: later,
      storageProtocol: ILazyPayableClaim.StorageProtocol.ARWEAVE,
      identical: true,
      cost: 1,
      paymentReceiver: payable(other),
      erc20: zeroAddress,
      signingAddress: zeroAddress
    });

    example.initializeClaim(address(creatorCore), 1, claimP);

    // Balance of creator should be zero, we defer creating the token until the first mint or airdrop
    assertEq(creatorCore.balanceOf(owner), 0);

    bytes32[] memory merkleProof1 = merkle.getProof(allowListTuples, uint32(0));

    vm.stopPrank();
    vm.startPrank(other);

    vm.expectRevert("Could not verify merkle proof");
    example.mint(address(creatorCore), 1, 1, merkleProof1, other);

    vm.stopPrank();
    vm.startPrank(other2);
    vm.expectRevert("Could not verify merkle proof");
    example.mint(address(creatorCore), 1, 0, merkleProof1, other2);

    vm.stopPrank();
    vm.startPrank(owner);

    uint mintFee = example.MINT_FEE_MERKLE() + 1;

    example.mint{ value: mintFee }(address(creatorCore), 1, 0, merkleProof1, owner);

    vm.roll(block.number + 1);
    vm.expectRevert("Already minted");
    example.mint{ value: mintFee }(address(creatorCore), 1, 0, merkleProof1, owner);

    vm.stopPrank();
    vm.startPrank(other2);

    bytes32[] memory merkleProof2 = merkle.getProof(allowListTuples, uint32(1));

    example.mint{ value: mintFee }(address(creatorCore), 1, 1, merkleProof2, other2);
    bytes32[] memory merkleProof3 = merkle.getProof(allowListTuples, uint32(2));

    example.mint{ value: mintFee }(address(creatorCore), 1, 2, merkleProof3, other2);

    vm.stopPrank();
    vm.startPrank(other3);
    bytes32[] memory merkleProof4 = merkle.getProof(allowListTuples, uint32(3));

    vm.expectRevert("Maximum tokens already minted for this claim");
    example.mint{ value: mintFee }(address(creatorCore), 1, 3, merkleProof4, other3);

    claimP.totalMax = 4;
    vm.stopPrank();
    vm.startPrank(owner);
    example.updateClaim(address(creatorCore), 1, claimP);
    vm.stopPrank();
    vm.startPrank(other3);
    example.mint{ value: mintFee }(address(creatorCore), 1, 3, merkleProof4, other3);

    vm.stopPrank();
  }

  function testMerkleMintBatch() public {
    vm.startPrank(owner);
    uint48 nowC = uint48(block.timestamp);
    uint48 later = nowC + 1000;
    uint mintFee = example.MINT_FEE_MERKLE() + 1;

    bytes32[] memory allowListTuples = new bytes32[](5);
    allowListTuples[0] = keccak256(abi.encodePacked(owner, uint32(0)));
    allowListTuples[1] = keccak256(abi.encodePacked(other2, uint32(1)));
    allowListTuples[2] = keccak256(abi.encodePacked(other2, uint32(2)));
    allowListTuples[3] = keccak256(abi.encodePacked(other3, uint32(3)));
    allowListTuples[4] = keccak256(abi.encodePacked(other3, uint32(4)));

    IERC721LazyPayableClaim.ClaimParameters memory claimP = IERC721LazyPayableClaim.ClaimParameters({
      merkleRoot: merkle.getRoot(allowListTuples),
      location: "arweaveHash1",
      totalMax: 3,
      walletMax: 0,
      startDate: nowC,
      endDate: later,
      storageProtocol: ILazyPayableClaim.StorageProtocol.ARWEAVE,
      identical: true,
      cost: 1,
      paymentReceiver: payable(other),
      erc20: zeroAddress,
      signingAddress: zeroAddress
    });

    example.initializeClaim(address(creatorCore), 1, claimP);

    bytes32[] memory merkleProof1 = merkle.getProof(allowListTuples, uint32(0));

    vm.stopPrank();
    vm.startPrank(owner);

    uint32[] memory amountsInput = new uint32[](1);
    amountsInput[0] = 0;

    bytes32[][] memory proofsInput = new bytes32[][](1);
    proofsInput[0] = merkleProof1;

    vm.expectRevert("Invalid input");
    example.mintBatch(address(creatorCore), 1, 2, amountsInput, proofsInput, owner);

    amountsInput = new uint32[](2);
    amountsInput[0] = 0;
    amountsInput[1] = 0;

    vm.expectRevert("Invalid input");
    example.mintBatch(address(creatorCore), 1, 1, amountsInput, proofsInput, owner);

    amountsInput = new uint32[](1);
    amountsInput[0] = 0;
    proofsInput = new bytes32[][](2);
    proofsInput[0] = merkleProof1;
    proofsInput[1] = merkleProof1;
    vm.expectRevert("Invalid input");
    example.mintBatch(address(creatorCore), 1, 1, amountsInput, proofsInput, owner);

    proofsInput = new bytes32[][](1);
    proofsInput[0] = merkleProof1;
    example.mintBatch{ value: mintFee }(address(creatorCore), 1, 1, amountsInput, proofsInput, owner);

    vm.expectRevert("Already minted");
    example.mint{ value: mintFee }(address(creatorCore), 1, 0, merkleProof1, owner);
    vm.expectRevert("Already minted");
    example.mintBatch{ value: mintFee }(address(creatorCore), 1, 1, amountsInput, proofsInput, owner);

    bytes32[] memory merkleProof2 = merkle.getProof(allowListTuples, uint32(1));
    bytes32[] memory merkleProof3 = merkle.getProof(allowListTuples, uint32(2));
    bytes32[] memory merkleProof4 = merkle.getProof(allowListTuples, uint32(3));
    bytes32[] memory merkleProof5 = merkle.getProof(allowListTuples, uint32(4));

    amountsInput = new uint32[](2);
    amountsInput[0] = 1;
    amountsInput[1] = 3;

    proofsInput = new bytes32[][](2);
    proofsInput[0] = merkleProof2;
    proofsInput[1] = merkleProof4;

    vm.stopPrank();
    vm.startPrank(other2);
    vm.expectRevert("Could not verify merkle proof");
    example.mintBatch(address(creatorCore), 1, 2, amountsInput, proofsInput, other2);

    proofsInput[1] = merkleProof3;
    amountsInput[1] = 2;
    example.mintBatch{ value: mintFee * 2 }(address(creatorCore), 1, 2, amountsInput, proofsInput, other2);

    vm.stopPrank();
    vm.startPrank(owner);

    address[] memory recipientsInput = new address[](1);
    recipientsInput[0] = other3;

    uint[] memory mintsInput = new uint[](1);
    mintsInput[0] = 1;

    string[] memory urisInput = new string[](1);
    urisInput[0] = "";
    // base mint something in between
    creatorCore.mintBase(other3);

    vm.stopPrank();
    vm.startPrank(other3);

    amountsInput = new uint32[](1);
    amountsInput[0] = 3;

    proofsInput = new bytes32[][](1);
    proofsInput[0] = merkleProof4;
    vm.expectRevert("Too many requested for this claim");
    example.mintBatch(address(creatorCore), 1, 1, amountsInput, proofsInput, other3);

    vm.stopPrank();
    vm.startPrank(owner);
    claimP.totalMax = 4;
    example.updateClaim(address(creatorCore), 1, claimP);

    vm.stopPrank();
    vm.startPrank(other3);
    amountsInput = new uint32[](2);
    amountsInput[0] = 3;
    amountsInput[1] = 4;

    proofsInput = new bytes32[][](2);
    proofsInput[0] = merkleProof4;
    proofsInput[1] = merkleProof5;
    vm.expectRevert("Too many requested for this claim");
    example.mintBatch(address(creatorCore), 1, 2, amountsInput, proofsInput, other3);

    vm.stopPrank();
    vm.startPrank(owner);
    claimP.totalMax = 5;
    example.updateClaim(address(creatorCore), 1, claimP);

    // Cannot mint with same mintIndex again
    vm.stopPrank();
    vm.startPrank(other2);
    vm.expectRevert("Already minted");
    example.mint(address(creatorCore), 1, 1, merkleProof2, other2);
    vm.expectRevert("Already minted");
    example.mint(address(creatorCore), 1, 2, merkleProof3, other2);

    amountsInput[0] = 1;
    amountsInput[1] = 2;
    proofsInput[0] = merkleProof2;
    proofsInput[1] = merkleProof3;
    vm.expectRevert("Already minted");
    example.mintBatch(address(creatorCore), 1, 2, amountsInput, proofsInput, other2);

    vm.stopPrank();
    vm.startPrank(other3);

    amountsInput[0] = 3;
    amountsInput[1] = 4;
    proofsInput[0] = merkleProof4;
    proofsInput[1] = merkleProof5;
    example.mintBatch{ value: mintFee * 2 }(address(creatorCore), 1, 2, amountsInput, proofsInput, other3);

    assertEq(creatorCore.balanceOf(owner), 1);
    assertEq(creatorCore.balanceOf(other2), 2);
    assertEq(creatorCore.balanceOf(other3), 3);
    assertEq(creatorCore.tokenURI(1), "https://arweave.net/arweaveHash1");

    vm.stopPrank();
  }

  function testNonMerkleMintBatch() public {
    vm.startPrank(owner);
    uint48 nowC = uint48(block.timestamp);
    uint48 later = nowC + 1000;
    uint mintFee = example.MINT_FEE_MERKLE() + 1;

    IERC721LazyPayableClaim.ClaimParameters memory claimP = IERC721LazyPayableClaim.ClaimParameters({
      merkleRoot: "",
      location: "arweaveHash1",
      totalMax: 5,
      walletMax: 3,
      startDate: nowC,
      endDate: later,
      storageProtocol: ILazyPayableClaim.StorageProtocol.ARWEAVE,
      identical: true,
      cost: 1,
      paymentReceiver: payable(other),
      erc20: zeroAddress,
      signingAddress: zeroAddress
    });

    example.initializeClaim(address(creatorCore), 1, claimP);

    vm.stopPrank();
    vm.startPrank(owner);
    vm.expectRevert("Too many requested for this wallet");
    example.mintBatch{ value: mintFee * 4 }(address(creatorCore), 1, 4, new uint32[](0), new bytes32[][](0), owner);

    example.mintBatch{ value: mintFee * 3 }(address(creatorCore), 1, 3, new uint32[](0), new bytes32[][](0), owner);

    vm.expectRevert("Too many requested for this wallet");
    example.mintBatch{ value: mintFee }(address(creatorCore), 1, 1, new uint32[](0), new bytes32[][](0), owner);

    vm.stopPrank();
    vm.startPrank(other2);
    vm.expectRevert("Too many requested for this claim");
    example.mintBatch{ value: mintFee * 3 }(address(creatorCore), 1, 3, new uint32[](0), new bytes32[][](0), other2);

    example.mintBatch{ value: mintFee * 2 }(address(creatorCore), 1, 2, new uint32[](0), new bytes32[][](0), other2);

    vm.stopPrank();
  }

  function testNonMerkleMintNotEnoughMoney() public {
    vm.startPrank(owner);
    uint48 nowC = uint48(block.timestamp);
    uint48 later = nowC + 1000;
    uint mintFee = example.MINT_FEE_MERKLE() + 1;

    IERC721LazyPayableClaim.ClaimParameters memory claimP = IERC721LazyPayableClaim.ClaimParameters({
      merkleRoot: "",
      location: "arweaveHash1",
      totalMax: 5,
      walletMax: 3,
      startDate: nowC,
      endDate: later,
      storageProtocol: ILazyPayableClaim.StorageProtocol.ARWEAVE,
      identical: true,
      cost: 1,
      paymentReceiver: payable(other),
      erc20: zeroAddress,
      signingAddress: zeroAddress
    });

    example.initializeClaim(address(creatorCore), 1, claimP);

    vm.stopPrank();
    vm.startPrank(owner);
    vm.expectRevert("Invalid amount");
    example.mintBatch{ value: mintFee * 2 }(address(creatorCore), 1, 3, new uint32[](0), new bytes32[][](0), owner);

    vm.expectRevert("Invalid amount");
    example.mintBatch{ value: 2 }(address(creatorCore), 1, 2, new uint32[](0), new bytes32[][](0), owner);

    vm.expectRevert("Invalid amount");
    example.mint(address(creatorCore), 1, 0, new bytes32[](0), owner);

    vm.stopPrank();
  }

  function testNonMerkleMintCheckBalance() public {
    vm.startPrank(owner);
    uint48 nowC = uint48(block.timestamp);
    uint48 later = nowC + 1000;
    uint mintFee = example.MINT_FEE_MERKLE() + 1;

    IERC721LazyPayableClaim.ClaimParameters memory claimP = IERC721LazyPayableClaim.ClaimParameters({
      merkleRoot: "",
      location: "arweaveHash1",
      totalMax: 5,
      walletMax: 3,
      startDate: nowC,
      endDate: later,
      storageProtocol: ILazyPayableClaim.StorageProtocol.ARWEAVE,
      identical: true,
      cost: 1,
      paymentReceiver: payable(owner),
      erc20: zeroAddress,
      signingAddress: zeroAddress
    });

    example.initializeClaim(address(creatorCore), 1, claimP);

    uint beforeBalance = owner.balance;
    vm.stopPrank();
    vm.startPrank(other2);
    example.mintBatch{ value: mintFee }(address(creatorCore), 1, 1, new uint32[](0), new bytes32[][](0), other2);
    example.mint{ value: mintFee }(address(creatorCore), 1, 0, new bytes32[](0), other2);
    uint afterBalance = owner.balance;
    assertEq(2, afterBalance - beforeBalance);
    vm.stopPrank();
  }

  function testTokenURI() public {
    vm.startPrank(owner);
    uint48 nowC = uint48(block.timestamp);
    uint48 later = nowC + 1000;
    uint mintFee = example.MINT_FEE() + 1;

    IERC721LazyPayableClaim.ClaimParameters memory claimP = IERC721LazyPayableClaim.ClaimParameters({
      merkleRoot: "",
      location: "XXX",
      totalMax: 11,
      walletMax: 3,
      startDate: nowC,
      endDate: later,
      storageProtocol: ILazyPayableClaim.StorageProtocol.ARWEAVE,
      identical: true,
      cost: 1,
      paymentReceiver: payable(owner),
      erc20: zeroAddress,
      signingAddress: zeroAddress
    });

    example.initializeClaim(address(creatorCore), 1, claimP);

    address[] memory recipientsInput = new address[](1);
    recipientsInput[0] = other;
    uint16[] memory amountsInput = new uint16[](1);
    amountsInput[0] = 1;
    string[] memory urisInput = new string[](1);
    urisInput[0] = "";
    // Mint a token using creator contract, to test breaking up extension's indexRange
    creatorCore.mintBase(other);

    vm.stopPrank();
    vm.startPrank(other);
    // Mint 2 tokens using the extension
    example.mint{ value: mintFee }(address(creatorCore), 1, 0, new bytes32[](0), other);
    vm.stopPrank();
    vm.startPrank(other2);
    example.mint{ value: mintFee }(address(creatorCore), 1, 0, new bytes32[](0), other2);
    // Mint a token using creator contract, to test breaking up extension's indexRange
    vm.stopPrank();
    vm.startPrank(owner);
    creatorCore.mintBase(other);
    // Mint 1 token using the extension
    vm.stopPrank();
    vm.startPrank(other3);
    example.mint{ value: mintFee }(address(creatorCore), 1, 0, new bytes32[](0), other3);
    assertEq("1", creatorCore.tokenURI(1));

    vm.stopPrank();
  }

  function testFunctionality() public {
    vm.startPrank(owner);
    uint48 nowC = uint48(block.timestamp);
    uint48 later = nowC + 1000;
    uint mintFee = example.MINT_FEE_MERKLE();

    bytes32[] memory allowListTuples = new bytes32[](3);
    allowListTuples[0] = keccak256(abi.encodePacked(owner, uint32(0)));
    allowListTuples[1] = keccak256(abi.encodePacked(other2, uint32(1)));
    allowListTuples[2] = keccak256(abi.encodePacked(other2, uint32(2)));

    IERC721LazyPayableClaim.ClaimParameters memory claimP = IERC721LazyPayableClaim.ClaimParameters({
      merkleRoot: merkle.getRoot(allowListTuples),
      location: "arweaveHash",
      totalMax: 3,
      walletMax: 0,
      startDate: nowC + 500,
      endDate: later,
      storageProtocol: ILazyPayableClaim.StorageProtocol.ARWEAVE,
      identical: true,
      cost: 1,
      paymentReceiver: payable(other),
      erc20: zeroAddress,
      signingAddress: zeroAddress
    });

    // Should fail to initialize if non-admin wallet is used
    vm.stopPrank();
    vm.startPrank(other);
    vm.expectRevert("Wallet is not an administrator for contract");
    example.initializeClaim(address(creatorCore), 1, claimP);

    // Cannot claim before initialization
    vm.stopPrank();
    vm.startPrank(owner);
    bytes32[] memory merkleProof1 = merkle.getProof(allowListTuples, uint32(0));
    vm.expectRevert("Claim not initialized");
    example.mint(address(creatorCore), 1, 0, merkleProof1, owner);

    example.initializeClaim(address(creatorCore), 1, claimP);

    // Overwrite the claim with parameters changed
    claimP.location = "arweaveHash1";
    claimP.walletMax = 0;
    example.updateClaim(address(creatorCore), 1, claimP);

    // Initialize a second claim - with optional parameters disabled
    claimP.location = "arweaveHash2";
    claimP.totalMax = 0;
    claimP.startDate = 0;
    claimP.endDate = 0;
    claimP.walletMax = 0;
    claimP.merkleRoot = "";
    example.initializeClaim(address(creatorCore), 2, claimP);

    // Claim should have expected info
    IERC721LazyPayableClaim.Claim memory claim = example.getClaim(address(creatorCore), 1);
    assertEq(claim.merkleRoot, merkle.getRoot(allowListTuples));
    assertEq(claim.location, "arweaveHash1");
    assertEq(claim.totalMax, 3);
    assertEq(claim.walletMax, 0);
    assertEq(claim.startDate, nowC + 500);
    assertEq(claim.endDate, later);

    // Test minting
    // Mint a token to random wallet
    vm.stopPrank();
    vm.startPrank(owner);
    vm.expectRevert("Claim inactive");
    example.mint{ value: mintFee + 1 }(address(creatorCore), 1, 0, merkleProof1, owner);

    vm.warp(nowC + 501);
    example.mint{ value: mintFee + 1 }(address(creatorCore), 1, 0, merkleProof1, owner);

    claim = example.getClaim(address(creatorCore), 1);
    assertEq(claim.total, 1);

    // ClaimByToken should have expected info
    (uint instanceId, IERC721LazyPayableClaim.Claim memory claimInfo) = example.getClaimForToken(address(creatorCore), 1);
    assertEq(instanceId, 1);
    assertEq(claimInfo.merkleRoot, merkle.getRoot(allowListTuples));
    assertEq(claimInfo.location, "arweaveHash1");
    assertEq(claimInfo.totalMax, 3);
    assertEq(claimInfo.walletMax, 0);
    assertEq(claimInfo.startDate, nowC + 500);
    assertEq(claimInfo.endDate, later);

    bytes32[] memory merkleProof2 = merkle.getProof(allowListTuples, uint32(1));
    vm.stopPrank();
    vm.startPrank(other2);
    example.mint{ value: mintFee + 1 }(address(creatorCore), 1, 1, merkleProof2, other2);

    // Now ensure that the creator contract state is what we expect after mints
    assertEq(creatorCore.balanceOf(owner), 1);
    assertEq(creatorCore.balanceOf(other2), 1);
    assertEq("https://arweave.net/arweaveHash1", creatorCore.tokenURI(1));

    // Additionally test that tokenURIs are dynamic
    vm.stopPrank();
    vm.startPrank(owner);

    claimP.location = "test.com";
    claimP.endDate = later;
    example.updateClaim(address(creatorCore), 1, claimP);

    assertEq("https://arweave.net/test.com", creatorCore.tokenURI(1));

    // Optional parameters - using claim 2
    // Cannot mint for someone else
    vm.expectRevert("Invalid input");
    example.mint{ value: mintFee }(address(creatorCore), 2, 0, new bytes32[](0), other);

    example.mint{ value: mintFee + 1 }(address(creatorCore), 2, 0, new bytes32[](0), owner);
    example.mint{ value: mintFee + 1 }(address(creatorCore), 2, 0, new bytes32[](0), owner);
    vm.stopPrank();
    vm.startPrank(other);
    example.mint{ value: mintFee + 1 }(address(creatorCore), 2, 0, new bytes32[](0), other);

    // end claim period
    vm.warp(later * 2);
    // Reverts due to end of mint period
    bytes32[] memory merkleProof3 = merkle.getProof(allowListTuples, uint32(2));

    vm.stopPrank();
    vm.startPrank(other2);
    vm.expectRevert("Claim inactive");
    example.mint{ value: mintFee + 1 }(address(creatorCore), 1, 2, merkleProof3, other2);

    // Passes with valid withdrawal amount from owner
    vm.stopPrank();
    vm.startPrank(owner);
    uint balanceBefore = owner.balance;
    example.withdraw(payable(owner), mintFee);
    uint balanceAfter = owner.balance;
    assertEq(balanceAfter, balanceBefore + mintFee);

    vm.stopPrank();
  }

  function testAirdrop() public {
    vm.startPrank(owner);
    uint48 nowC = uint48(block.timestamp);
    uint48 later = nowC + 1000;
    uint mintFee = example.MINT_FEE_MERKLE();

    bytes32[] memory allowListTuples = new bytes32[](2);
    allowListTuples[0] = keccak256(abi.encodePacked(owner, uint32(0)));
    allowListTuples[1] = keccak256(abi.encodePacked(other2, uint32(1)));

    IERC721LazyPayableClaim.ClaimParameters memory claimP = IERC721LazyPayableClaim.ClaimParameters({
      merkleRoot: merkle.getRoot(allowListTuples),
      location: "XXX",
      totalMax: 0,
      walletMax: 0,
      startDate: nowC,
      endDate: later,
      storageProtocol: ILazyPayableClaim.StorageProtocol.ARWEAVE,
      identical: true,
      cost: 1,
      paymentReceiver: payable(other),
      erc20: zeroAddress,
      signingAddress: zeroAddress
    });

    example.initializeClaim(address(creatorCore), 1, claimP);

    address[] memory receivers = new address[](1);
    receivers[0] = other;
    uint16[] memory amounts = new uint16[](1);
    amounts[0] = 1;
    // Perform an airdrop
    example.airdrop(address(creatorCore), 1, receivers, amounts);

    IERC721LazyPayableClaim.Claim memory claim = example.getClaim(address(creatorCore), 1);
    assertEq(claim.total, 1);
    assertEq(claim.totalMax, 0);

    // Mint
    bytes32[] memory merkleProof1 = merkle.getProof(allowListTuples, uint32(0));

    example.mint{ value: mintFee + 1 }(address(creatorCore), 1, 0, merkleProof1, owner);

    // Update totalMax to 1, will actually set to 2 because there are two
    claimP.totalMax = 1;
    example.updateClaim(address(creatorCore), 1, claimP);
    claim = example.getClaim(address(creatorCore), 1);
    assertEq(claim.totalMax, 2);

    // Perform another airdrop after minting
    receivers = new address[](2);
    receivers[0] = other2;
    receivers[1] = other3;
    amounts = new uint16[](2);
    amounts[0] = 1;
    amounts[1] = 5;
    example.airdrop(address(creatorCore), 1, receivers, amounts);
    claim = example.getClaim(address(creatorCore), 1);
    assertEq(claim.total, 8);
    assertEq(claim.totalMax, 8);

    // Update totalMax back to 0
    claimP.totalMax = 0;
    example.updateClaim(address(creatorCore), 1, claimP);
    claim = example.getClaim(address(creatorCore), 1);
    assertEq(claim.totalMax, 0);

    // Mint again after second airdrop
    bytes32[] memory merkleProof2 = merkle.getProof(allowListTuples, uint32(1));
    vm.stopPrank();
    vm.startPrank(other2);
    example.mint{ value: mintFee + 1 }(address(creatorCore), 1, 1, merkleProof2, other2);

    assertEq(1, creatorCore.balanceOf(owner));
    assertEq(1, creatorCore.balanceOf(other));
    assertEq(2, creatorCore.balanceOf(other2));
    assertEq(5, creatorCore.balanceOf(other3));

    vm.stopPrank();
  }

  function testDelegateMinting() public {
    vm.startPrank(owner);
    uint48 nowC = uint48(block.timestamp);
    uint48 later = nowC + 1000;
    uint mintFee = example.MINT_FEE_MERKLE();

    bytes32[] memory allowListTuples = new bytes32[](3);
    allowListTuples[0] = keccak256(abi.encodePacked(owner, uint32(0)));
    allowListTuples[1] = keccak256(abi.encodePacked(other2, uint32(1)));
    allowListTuples[2] = keccak256(abi.encodePacked(other3, uint32(2)));

    IERC721LazyPayableClaim.ClaimParameters memory claimP = IERC721LazyPayableClaim.ClaimParameters({
      merkleRoot: merkle.getRoot(allowListTuples),
      location: "XXX",
      totalMax: 0,
      walletMax: 0,
      startDate: nowC,
      endDate: later,
      storageProtocol: ILazyPayableClaim.StorageProtocol.ARWEAVE,
      identical: true,
      cost: 1,
      paymentReceiver: payable(other),
      erc20: zeroAddress,
      signingAddress: zeroAddress
    });

    example.initializeClaim(address(creatorCore), 1, claimP);

    // Set delegations
    delegationRegistry.delegateForAll(other, true);

    vm.stopPrank();
    vm.startPrank(other2);
    delegationRegistry.delegateForContract(other, address(example), true);

    // Mint with wallet-level delegate
    bytes32[] memory merkleProof1 = merkle.getProof(allowListTuples, uint32(0));
    vm.stopPrank();
    vm.startPrank(other);
    example.mint{ value: mintFee + 1 }(address(creatorCore), 1, 0, merkleProof1, owner);
    assertEq(creatorCore.balanceOf(owner), 0);
    assertEq(creatorCore.balanceOf(other), 1);

    // Mint with contract-level delegate
    bytes32[] memory merkleProof2 = merkle.getProof(allowListTuples, uint32(1));
    example.mint{ value: mintFee + 1 }(address(creatorCore), 1, 1, merkleProof2, other2);

    // Fail to mint when no delegate is set
    bytes32[] memory merkleProof3 = merkle.getProof(allowListTuples, uint32(2));
    vm.expectRevert("Invalid delegate");
    example.mint{ value: mintFee + 1 }(address(creatorCore), 1, 2, merkleProof3, other3);

    vm.stopPrank();
  }

  function testDelegateRegistryAddress() public {
    vm.startPrank(owner);

    ERC721LazyPayableClaim claim = new ERC721LazyPayableClaim(
      address(creatorCore),
      address(0x00000000b1BBFe1BF5C5934c4bb9c30FEF15E57A)
    );
    address onChainAddress = claim.DELEGATION_REGISTRY();
    assertEq(0x00000000b1BBFe1BF5C5934c4bb9c30FEF15E57A, onChainAddress);

    vm.stopPrank();
  }

  function testAllowReceipientContract() public {
    vm.startPrank(owner);
    uint48 nowC = uint48(block.timestamp);
    uint48 later = nowC + 1000;
    uint mintFee = example.MINT_FEE_MERKLE();

    // Construct a contract receiver
    MockETHReceiver mockETHReceiver = new MockETHReceiver();

    IERC721LazyPayableClaim.ClaimParameters memory claimP = IERC721LazyPayableClaim.ClaimParameters({
      merkleRoot: "",
      location: "XXX",
      totalMax: 5,
      walletMax: 3,
      startDate: nowC,
      endDate: later,
      storageProtocol: ILazyPayableClaim.StorageProtocol.ARWEAVE,
      identical: true,
      cost: 1,
      paymentReceiver: payable(address(mockETHReceiver)),
      erc20: zeroAddress,
      signingAddress: zeroAddress
    });

    example.initializeClaim(address(creatorCore), 1, claimP);
    // Perform a mint on the claim
    example.mint{ value: mintFee + 1 }(address(creatorCore), 1, 0, new bytes32[](0), owner);

    vm.stopPrank();
  }

  function testMembershipMint() public {
    vm.startPrank(owner);
    uint48 nowC = uint48(block.timestamp);
    uint48 later = nowC + 1000;

    bytes32[] memory allowListTuples = new bytes32[](2);
    allowListTuples[0] = keccak256(abi.encodePacked(owner, uint32(0)));
    allowListTuples[1] = keccak256(abi.encodePacked(owner, uint32(1)));

    IERC721LazyPayableClaim.ClaimParameters memory claimP = IERC721LazyPayableClaim.ClaimParameters({
      merkleRoot: "",
      location: "XXX",
      totalMax: 10,
      walletMax: 10,
      startDate: nowC,
      endDate: later,
      storageProtocol: ILazyPayableClaim.StorageProtocol.ARWEAVE,
      identical: true,
      cost: 1,
      paymentReceiver: payable(other),
      erc20: zeroAddress,
      signingAddress: zeroAddress
    });

    example.initializeClaim(address(creatorCore), 1, claimP);

    claimP.merkleRoot = merkle.getRoot(allowListTuples);
    claimP.totalMax = 5;
    claimP.walletMax = 0;
    example.initializeClaim(address(creatorCore), 2, claimP);

    manifoldMembership.setMember(owner, true);
    // Perform a mint on the claim
    example.mintBatch{ value: 3 }(address(creatorCore), 1, 3, new uint32[](0), new bytes32[][](0), owner);

    bytes32[] memory merkleProof1 = merkle.getProof(allowListTuples, uint32(0));
    bytes32[] memory merkleProof2 = merkle.getProof(allowListTuples, uint32(1));

    uint32[] memory amountsInput = new uint32[](2);
    amountsInput[0] = 0;
    amountsInput[1] = 1;

    bytes32[][] memory proofsInput = new bytes32[][](2);
    proofsInput[0] = merkleProof1;
    proofsInput[1] = merkleProof2;

    example.mintBatch{ value: 2 }(address(creatorCore), 2, 2, amountsInput, proofsInput, owner);

    vm.stopPrank();
  }

  function testProxyMint() public {
    vm.startPrank(owner);
    uint48 nowC = uint48(block.timestamp);
    uint48 later = nowC + 1000;
    uint mintFee = example.MINT_FEE_MERKLE();
    uint mintFeeNon = example.MINT_FEE();

    bytes32[] memory allowListTuples = new bytes32[](2);
    allowListTuples[0] = keccak256(abi.encodePacked(owner, uint32(0)));
    allowListTuples[1] = keccak256(abi.encodePacked(owner, uint32(1)));

    IERC721LazyPayableClaim.ClaimParameters memory claimP = IERC721LazyPayableClaim.ClaimParameters({
      merkleRoot: "",
      location: "XXX",
      totalMax: 10,
      walletMax: 10,
      startDate: nowC,
      endDate: later,
      storageProtocol: ILazyPayableClaim.StorageProtocol.ARWEAVE,
      identical: true,
      cost: 1,
      paymentReceiver: payable(owner),
      erc20: zeroAddress,
      signingAddress: zeroAddress
    });

    example.initializeClaim(address(creatorCore), 1, claimP);

    claimP.merkleRoot = merkle.getRoot(allowListTuples);
    claimP.totalMax = 5;
    claimP.walletMax = 0;
    example.initializeClaim(address(creatorCore), 3, claimP);

    // The sender is a member, but proxy minting will ignore the fact they are a member
    manifoldMembership.setMember(other, true);
    // Perform a mint on the claim
    uint balance = other.balance;
    uint ownerBalance = owner.balance;

    vm.stopPrank();
    vm.startPrank(other);
    example.mintProxy{ value: mintFee * 3 + 3 }(address(creatorCore), 1, 3, new uint32[](0), new bytes32[][](0), owner);

    assertEq(3, creatorCore.balanceOf(owner));

    // Ensure funds taken from message sender
    assertEq(other.balance, balance - mintFee * 3 - 3);

    // Ensure seller got funds
    assertEq(owner.balance, ownerBalance + 3);

    // Mint merkle claims
    bytes32[] memory merkleProof1 = merkle.getProof(allowListTuples, uint32(0));
    bytes32[] memory merkleProof2 = merkle.getProof(allowListTuples, uint32(1));

    uint32[] memory amountsInput = new uint32[](2);
    amountsInput[0] = 0;
    amountsInput[1] = 1;

    bytes32[][] memory proofsInput = new bytes32[][](2);
    proofsInput[0] = merkleProof1;
    proofsInput[1] = merkleProof2;

    vm.expectRevert("Invalid amount");
    example.mintProxy{ value: mintFeeNon * 2 + 2 }(address(creatorCore), 3, 2, amountsInput, proofsInput, owner);
    example.mintProxy{ value: mintFee * 2 + 2 }(address(creatorCore), 3, 2, amountsInput, proofsInput, owner);
    assertEq(5, creatorCore.balanceOf(owner));
    vm.stopPrank();
  }
}
