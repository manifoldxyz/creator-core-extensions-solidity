// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../contracts/lazyclaim/ERC1155LazyPayableClaim.sol";
import "../contracts/lazyclaim/IERC1155LazyPayableClaim.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC1155Creator.sol";
import "../contracts/libraries/delegation-registry/DelegationRegistry.sol";
import "../contracts/mocks/Mock.sol";
import "../lib/murky/src/Merkle.sol";

contract ERC1155LazyPayableClaimTest is Test {

    ERC1155LazyPayableClaim public example;
    ERC1155Creator public creatorCore;
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
        creatorCore = new ERC1155Creator("Token", "NFT");
        delegationRegistry = new DelegationRegistry();
        example = new ERC1155LazyPayableClaim(
          owner, address(delegationRegistry)
        );
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

      uint48 nowC = uint48(block.timestamp);
      uint48 later = nowC + 1000;

      IERC1155LazyPayableClaim.ClaimParameters memory claimP = IERC1155LazyPayableClaim.ClaimParameters({
          merkleRoot: "",
          location: "arweaveHash1",
          totalMax: 10,
          walletMax: 1,
          startDate: nowC,
          endDate: later,
          storageProtocol: ILazyPayableClaim.StorageProtocol.ARWEAVE,
          cost: 1,
          paymentReceiver: payable(other),
          erc20: zeroAddress
      });
      // Must be admin
      vm.expectRevert();
      example.initializeClaim(
        address(creatorCore),
        1,
        claimP
      );
      // Succeeds because is admin
      vm.stopPrank();
      vm.startPrank(owner);
      example.initializeClaim(
        address(creatorCore),
        1,
        claimP
      );

      // Update, not admin
      vm.stopPrank();
      vm.startPrank(other);
      vm.expectRevert();
      example.updateClaim(
        address(creatorCore),
        1,
        claimP
      );

      vm.expectRevert();
      example.updateTokenURIParams(
        address(creatorCore),
        1,
        ILazyPayableClaim.StorageProtocol.IPFS,
        ""
      );

      vm.expectRevert();
      example.extendTokenURI(
        address(creatorCore),
        2,
        ""
      );

      vm.stopPrank();
      vm.startPrank(owner);

      claimP.totalMax = 9;
      claimP.paymentReceiver = payable(owner);
      example.updateClaim(
        address(creatorCore),
        1,
        claimP
      );

      ERC1155LazyPayableClaim.Claim memory claim = example.getClaim(address(creatorCore), 1);

      assertEq(claim.merkleRoot, "");
      assertEq(claim.location, "arweaveHash1");
      assertEq(claim.totalMax, 9);
      assertEq(claim.walletMax, 1);
      assertEq(claim.startDate, nowC);
      assertEq(claim.endDate, later);
      assertEq(claim.cost, 1);
      assertEq(claim.paymentReceiver, owner);

      assertEq("https://arweave.net/arweaveHash1", creatorCore.uri(1));

      example.updateTokenURIParams(address(creatorCore), 1, ILazyPayableClaim.StorageProtocol.ARWEAVE, "arweaveHash3");
      assertEq("https://arweave.net/arweaveHash3", creatorCore.uri(1));
      // Extend uri
      vm.expectRevert();
      example.extendTokenURI(address(creatorCore), 1, "");
      example.updateTokenURIParams(address(creatorCore), 1, ILazyPayableClaim.StorageProtocol.NONE, "part1");
      example.extendTokenURI(address(creatorCore), 1, "part2");
      assertEq("part1part2", creatorCore.uri(1));

      vm.stopPrank();
    }

    function testinitializeClaimSanitization() public {
      vm.startPrank(owner);
      uint48 nowC = uint48(block.timestamp);
      uint48 later = nowC + 1000;


      IERC1155LazyPayableClaim.ClaimParameters memory claimP = IERC1155LazyPayableClaim.ClaimParameters({
          merkleRoot: "",
          location: "arweaveHash1",
          totalMax: 10,
          walletMax: 1,
          startDate: nowC,
          endDate: later,
          storageProtocol: ILazyPayableClaim.StorageProtocol.INVALID,
          cost: 1,
          paymentReceiver: payable(other),
          erc20: zeroAddress
      });

      vm.expectRevert("Cannot initialize with invalid storage protocol");
      example.initializeClaim(
        address(creatorCore),
        1,
        claimP
      );

      claimP.startDate = nowC + 2000;
      claimP.storageProtocol = ILazyPayableClaim.StorageProtocol.ARWEAVE;
      vm.expectRevert("Cannot have startDate greater than or equal to endDate");
      example.initializeClaim(
        address(creatorCore),
        1,
        claimP
      );

      claimP.startDate = nowC;
      claimP.merkleRoot = "0x0";
      vm.expectRevert("Cannot provide both walletMax and merkleRoot");
      example.initializeClaim(
        address(creatorCore),
        1,
        claimP
      );

      claimP.merkleRoot = "";
      vm.expectRevert("Claim not initialized");
      example.updateClaim(
        address(creatorCore),
        1,
        claimP
      );

      vm.stopPrank();
    }

    function testUpdateClaimSanitization() public {
      vm.startPrank(owner);
      uint48 nowC = uint48(block.timestamp);
      uint48 later = nowC + 1000;

      IERC1155LazyPayableClaim.ClaimParameters memory claimP = IERC1155LazyPayableClaim.ClaimParameters({
          merkleRoot: "",
          location: "arweaveHash1",
          totalMax: 10,
          walletMax: 1,
          startDate: nowC,
          endDate: later,
          storageProtocol: ILazyPayableClaim.StorageProtocol.ARWEAVE,
          cost: 1,
          paymentReceiver: payable(other),
          erc20: zeroAddress
      });

      example.initializeClaim(
        address(creatorCore),
        1,
        claimP
      );

      claimP.storageProtocol = ILazyPayableClaim.StorageProtocol.INVALID;
      vm.expectRevert("Cannot set invalid storage protocol");
      example.updateClaim(
        address(creatorCore),
        1,
        claimP
      );

      claimP.startDate = nowC + 2000;
      claimP.storageProtocol = ILazyPayableClaim.StorageProtocol.ARWEAVE;
      vm.expectRevert("Cannot have startDate greater than or equal to endDate");
      example.updateClaim(
        address(creatorCore),
        1,
        claimP
      );

      claimP.startDate = nowC;
      claimP.erc20 = 0x0000000000000000000000000000000000000001;
      vm.expectRevert("Cannot change payment token");
      example.updateClaim(
        address(creatorCore),
        1,
        claimP
      );

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

      IERC1155LazyPayableClaim.ClaimParameters memory claimP = IERC1155LazyPayableClaim.ClaimParameters({
          merkleRoot: merkle.getRoot(allowListTuples),
          location: "arweaveHash1",
          totalMax: 3,
          walletMax: 0,
          startDate: nowC,
          endDate: later,
          storageProtocol: ILazyPayableClaim.StorageProtocol.ARWEAVE,
          cost: 1,
          paymentReceiver: payable(other),
          erc20: zeroAddress
      });

      example.initializeClaim(
        address(creatorCore),
        1,
        claimP
      );

      // Balance of creator should be zero, we defer creating the token until the first mint or airdrop
      assertEq(creatorCore.balanceOf(owner, 1), 0);

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

      example.mint{value: mintFee}(address(creatorCore), 1, 0, merkleProof1, owner);

      vm.roll(block.number + 1);
      vm.expectRevert("Already minted");
      example.mint{value: mintFee}(address(creatorCore), 1, 0, merkleProof1, owner);

      vm.stopPrank();
      vm.startPrank(other2);

      bytes32[] memory merkleProof2 = merkle.getProof(allowListTuples, uint32(1));

      example.mint{value: mintFee}(address(creatorCore), 1, 1, merkleProof2, other2);
      bytes32[] memory merkleProof3 = merkle.getProof(allowListTuples, uint32(2));

      example.mint{value: mintFee}(address(creatorCore), 1, 2, merkleProof3, other2);

      vm.stopPrank();
      vm.startPrank(other3);
      bytes32[] memory merkleProof4 = merkle.getProof(allowListTuples, uint32(3));

      vm.expectRevert("Maximum tokens already minted for this claim");
      example.mint{value: mintFee}(address(creatorCore), 1, 3, merkleProof4, other3);

      claimP.totalMax = 4;
      vm.stopPrank();
      vm.startPrank(owner);
      example.updateClaim(
        address(creatorCore),
        1,
        claimP
      );
      vm.stopPrank();
      vm.startPrank(other3);
      example.mint{value: mintFee}(address(creatorCore), 1, 3, merkleProof4, other3);

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

      IERC1155LazyPayableClaim.ClaimParameters memory claimP = IERC1155LazyPayableClaim.ClaimParameters({
          merkleRoot: merkle.getRoot(allowListTuples),
          location: "arweaveHash1",
          totalMax: 3,
          walletMax: 0,
          startDate: nowC,
          endDate: later,
          storageProtocol: ILazyPayableClaim.StorageProtocol.ARWEAVE,
          cost: 1,
          paymentReceiver: payable(other),
          erc20: zeroAddress
      });

      example.initializeClaim(
        address(creatorCore),
        1,
        claimP
      );

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
      example.mintBatch{value: mintFee}(address(creatorCore), 1, 1, amountsInput, proofsInput, owner);

      vm.expectRevert("Already minted");
      example.mint{value: mintFee}(address(creatorCore), 1, 0, merkleProof1, owner);
      vm.expectRevert("Already minted");
      example.mintBatch{value: mintFee}(address(creatorCore), 1, 1, amountsInput, proofsInput, owner);


      vm.stopPrank();
    }
}