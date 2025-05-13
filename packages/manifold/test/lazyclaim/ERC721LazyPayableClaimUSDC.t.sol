// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../contracts/lazyclaim/ERC721LazyPayableClaimUSDC.sol";
import "../../contracts/lazyclaim/IERC721LazyPayableClaim.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC721Creator.sol";
import "../mocks/delegation-registry/DelegationRegistry.sol";
import "../mocks/delegation-registry/DelegationRegistryV2.sol";
import "../mocks/Mock.sol";
import "../../lib/murky/src/Merkle.sol";

contract ERC721LazyPayableClaimUSDCTest is Test {
    ERC721LazyPayableClaimUSDC public example;
    ERC721Creator public creatorCore;
    DelegationRegistry public delegationRegistry;
    DelegationRegistryV2 public delegationRegistryV2;
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
        delegationRegistryV2 = new DelegationRegistryV2();
        mockERC20 = new MockERC20("Test", "test");

        example = new ERC721LazyPayableClaimUSDC(
            owner, address(mockERC20), address(delegationRegistry), address(delegationRegistryV2)
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

    function testFunctionality() public {
        vm.startPrank(owner);
        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;
        uint256 mintFee = example.MINT_FEE();
        uint256 mintFeeMerkle = example.MINT_FEE_MERKLE();

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
            storageProtocol: ILazyPayableClaimCore.StorageProtocol.ARWEAVE,
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

        claimP.erc20 = address(0);
        vm.expectRevert(ILazyPayableClaimUSDC.InvalidUSDCAddress.selector);
        example.initializeClaim(address(creatorCore), 3, claimP);

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

        mockERC20.approve(address(example), 1000 + mintFeeMerkle);

        // Cannot mint with no erc20 balance
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        example.mint(address(creatorCore), 1, 0, merkleProof1, other);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        example.mintBatch(address(creatorCore), 1, 1, amounts, merkleProofs, other);

        // Mint erc20 tokens
        mockERC20.fakeMint(other, 1000 + mintFeeMerkle);

        // Mint a token (merkle)
        example.mint(address(creatorCore), 1, 0, merkleProof1, other);

        IERC721LazyPayableClaim.Claim memory claim = example.getClaim(address(creatorCore), 1);
        assertEq(claim.total, 1);
        assertEq(900, mockERC20.balanceOf(other));
        assertEq(100, mockERC20.balanceOf(owner));
        assertEq(mintFeeMerkle, mockERC20.balanceOf(address(example)));
        assertEq(1, creatorCore.balanceOf(other));

        // Mint batch (merkle)
        amounts = new uint32[](2);
        amounts[0] = 1;
        amounts[1] = 2;
        merkleProofs = new bytes32[][](2);
        merkleProofs[0] = merkleProof2;
        merkleProofs[1] = merkleProof3;

        mockERC20.approve(address(example), 1000 + mintFeeMerkle * 2);
        mockERC20.fakeMint(other, mintFeeMerkle * 2);
        example.mintBatch(address(creatorCore), 1, 2, amounts, merkleProofs, other);

        assertEq(700, mockERC20.balanceOf(other));
        assertEq(300, mockERC20.balanceOf(owner));
        assertEq(mintFeeMerkle * 3, mockERC20.balanceOf(address(example)));
        assertEq(3, creatorCore.balanceOf(other));

        // Mint a token
        bytes32[] memory blankProof = new bytes32[](0);
        mockERC20.approve(address(example), 1000 + mintFee);
        mockERC20.fakeMint(other, mintFee);
        example.mint(address(creatorCore), 2, 0, blankProof, other);
        claim = example.getClaim(address(creatorCore), 2);
        assertEq(claim.total, 1);
        assertEq(500, mockERC20.balanceOf(other));
        assertEq(500, mockERC20.balanceOf(owner));
        assertEq(mintFee + mintFeeMerkle * 3, mockERC20.balanceOf(address(example)));
        assertEq(4, creatorCore.balanceOf(other));

        bytes32[][] memory blankProofs = new bytes32[][](0);
        uint32[] memory blankAmounts = new uint32[](0);

        mockERC20.approve(address(example), 1000 + example.MINT_FEE() * 2);
        mockERC20.fakeMint(other, example.MINT_FEE() * 2);
        example.mintBatch(address(creatorCore), 2, 2, blankAmounts, blankProofs, other);
        assertEq(100, mockERC20.balanceOf(other));
        assertEq(900, mockERC20.balanceOf(owner));
        assertEq(mintFee * 3 + mintFeeMerkle * 3, mockERC20.balanceOf(address(example)));
        assertEq(6, creatorCore.balanceOf(other));

        vm.stopPrank();
    }

    function testWithdraw() public {
        vm.startPrank(owner);
        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;
        uint256 mintFee = example.MINT_FEE();

        IERC721LazyPayableClaim.ClaimParameters memory claimP = IERC721LazyPayableClaim.ClaimParameters({
            merkleRoot: "",
            location: "arweaveHash1",
            totalMax: 3,
            walletMax: 0,
            startDate: nowC,
            endDate: later,
            storageProtocol: ILazyPayableClaimCore.StorageProtocol.ARWEAVE,
            identical: true,
            cost: 100,
            paymentReceiver: payable(owner),
            erc20: address(mockERC20),
            signingAddress: address(0)
        });

        example.initializeClaim(address(creatorCore), 1, claimP);

        vm.stopPrank();
        vm.startPrank(other);

        mockERC20.approve(address(example), 1000 + mintFee);
        // Mint erc20 tokens
        mockERC20.fakeMint(other, 1000 + mintFee);

        // Mint a token
        example.mint(address(creatorCore), 1, 0, new bytes32[](0), other);

        IERC721LazyPayableClaim.Claim memory claim = example.getClaim(address(creatorCore), 1);
        assertEq(claim.total, 1);
        assertEq(900, mockERC20.balanceOf(other));
        assertEq(100, mockERC20.balanceOf(owner));
        assertEq(mintFee, mockERC20.balanceOf(address(example)));
        assertEq(1, creatorCore.balanceOf(other));

        vm.expectRevert();
        example.withdraw(payable(other), mintFee);

        vm.stopPrank();
        vm.startPrank(owner);
        example.withdraw(payable(other2), mintFee);
        assertEq(0, mockERC20.balanceOf(address(example)));
        assertEq(mintFee, mockERC20.balanceOf(other2));
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
            storageProtocol: ILazyPayableClaimCore.StorageProtocol.ARWEAVE,
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
        uint256 mintFeeMerkle = example.MINT_FEE_MERKLE();
        uint256 mintFee = example.MINT_FEE();

        IERC721LazyPayableClaim.ClaimParameters memory claimP = IERC721LazyPayableClaim.ClaimParameters({
            merkleRoot: "",
            location: "arweaveHash1",
            totalMax: 3,
            walletMax: 0,
            startDate: nowC,
            endDate: later,
            storageProtocol: ILazyPayableClaimCore.StorageProtocol.ARWEAVE,
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
        mockERC20.approve(address(example), 1000 + mintFee * 3);
        mockERC20.fakeMint(other, 1000 + mintFee * 3);

        uint32[] memory amounts = new uint32[](0);
        bytes32[][] memory merkleProofs = new bytes32[][](0);

        // Perform a mint on the claim
        uint256 startingBalance = other.balance;
        example.mintProxy(address(creatorCore), 1, 3, amounts, merkleProofs, other2);
        assertEq(3, creatorCore.balanceOf(other2));
        // Ensure funds taken from message sender
        // This fuzzy number is how much gas was used. Cannot figure out how to do it in forge
        assertEq(700, mockERC20.balanceOf(other));
        assertEq(300, mockERC20.balanceOf(owner));
        assertEq(mintFee * 3, mockERC20.balanceOf(address(example)));

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

        mockERC20.approve(address(example), 1000 + mintFeeMerkle * 2);
        mockERC20.fakeMint(other, mintFeeMerkle * 2);
        example.mintProxy(address(creatorCore), 3, 2, amounts, merkleProofs, other2);
        assertEq(5, creatorCore.balanceOf(other2));
        // Ensure funds taken from message sender
        assertEq(500, mockERC20.balanceOf(other));
        assertEq(500, mockERC20.balanceOf(owner));
        assertEq(mintFee * 3 + mintFeeMerkle * 2, mockERC20.balanceOf(address(example)));
    }
}
