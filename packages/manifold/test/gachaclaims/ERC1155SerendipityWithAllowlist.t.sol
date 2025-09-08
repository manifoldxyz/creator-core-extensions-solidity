// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../contracts/gachaclaims/IERC1155Serendipity.sol";
import "../../contracts/gachaclaims/ERC1155SerendipityWithAllowlist.sol"; // CONTRACT DOESN'T EXIST YET - WILL CAUSE COMPILE ERROR
import "../../contracts/gachaclaims/ISerendipity.sol";
import "../../contracts/gachaclaims/Serendipity.sol";

import "@manifoldxyz/creator-core-solidity/contracts/ERC1155Creator.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../mocks/Mock.sol";
import "../mocks/delegation-registry/DelegationRegistry.sol";
import "../../lib/murky/src/Merkle.sol";

/**
 * @title ERC1155SerendipityWithAllowlistTest
 * @notice Comprehensive test suite for ERC1155SerendipityWithAllowlist contract
 * @dev This follows TDD red-green methodology - tests will FAIL initially since contract doesn't exist
 */
contract ERC1155SerendipityWithAllowlistTest is Test {
    using SafeMath for uint256;

    // ============ Test Contracts ============
    ERC1155SerendipityWithAllowlist public serendipityWithAllowlist; // WILL FAIL - CONTRACT DOESN'T EXIST
    ERC1155Creator public creatorCore1;
    ERC1155Creator public creatorCore2; 
    MockManifoldMembership public manifoldMembership;
    MockERC20 public erc20Token;
    DelegationRegistry public delegationRegistry;
    Merkle public merkle;

    // ============ Test Addresses ============
    address public creator = 0xc78Dc443c126af6E4f6Ed540c1e740C1b5be09cd;
    address public owner = 0x6140F00e4Ff3936702E68744f2b5978885464cbB;
    address public signingAddress = 0xc78dC443c126Af6E4f6eD540C1E740c1B5be09CE;
    address public alice = 0x5174cD462b60c536eb51D4ceC1D561D3Ea31004F;
    address public bob = 0x80AAC46bbd3C2FcE33681541a52CacBEd14bF425;
    address public charlie = 0x1234567890123456789012345678901234567890;
    address public unauthorized = 0x9876543210987654321098765432109876543210;

    address public zeroAddress = address(0);

    // ============ Test Constants ============
    uint256 private privateKey = 0x1010101010101010101010101010101010101010101010101010101010101010;
    uint32 private constant MAX_UINT_32 = 0xffffffff;
    uint256 public constant MINT_FEE = 500000000000000;
    uint256 public constant DEFAULT_COST = 0.01 ether;

    // ============ Merkle Test Data ============
    bytes32[] public allowlistAddresses;
    bytes32 public merkleRoot;
    bytes32[][] public merkleProofs;

    // ============ Setup ============
    function setUp() public {
        vm.startPrank(creator);
        creatorCore1 = new ERC1155Creator("Token1", "NFT1");
        creatorCore2 = new ERC1155Creator("Token2", "NFT2");
        vm.stopPrank();

        vm.startPrank(owner);
        // THIS WILL FAIL - CONTRACT DOESN'T EXIST YET
        serendipityWithAllowlist = new ERC1155SerendipityWithAllowlist(owner);
        serendipityWithAllowlist.setSigner(signingAddress);
        
        manifoldMembership = new MockManifoldMembership();
        erc20Token = new MockERC20("TestToken", "TEST");
        delegationRegistry = new DelegationRegistry();
        merkle = new Merkle();
        vm.stopPrank();

        vm.startPrank(creator);
        creatorCore1.registerExtension(address(serendipityWithAllowlist), "override");
        creatorCore2.registerExtension(address(serendipityWithAllowlist), "override");
        vm.stopPrank();

        // Setup test balances
        vm.deal(creator, 10 ether);
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        vm.deal(charlie, 10 ether);
        vm.deal(unauthorized, 10 ether);

        // Setup ERC20 balances
        vm.startPrank(owner);
        erc20Token.fakeMint(alice, 1000 ether);
        erc20Token.fakeMint(bob, 1000 ether);
        erc20Token.fakeMint(charlie, 1000 ether);
        vm.stopPrank();

        // Setup membership discounts
        vm.startPrank(address(manifoldMembership));
        manifoldMembership.setMember(alice, true);
        vm.stopPrank();

        _setupMerkleTree();
    }

    function _setupMerkleTree() internal {
        // Setup allowlist with alice, bob, charlie
        allowlistAddresses = new bytes32[](3);
        allowlistAddresses[0] = keccak256(abi.encode(alice));
        allowlistAddresses[1] = keccak256(abi.encode(bob));
        allowlistAddresses[2] = keccak256(abi.encode(charlie));

        merkleRoot = merkle.getRoot(allowlistAddresses);
        
        // Generate proofs for each address
        merkleProofs = new bytes32[][](3);
        merkleProofs[0] = merkle.getProof(allowlistAddresses, 0);
        merkleProofs[1] = merkle.getProof(allowlistAddresses, 1);
        merkleProofs[2] = merkle.getProof(allowlistAddresses, 2);
    }

    function _createBasicClaimParameters() internal view returns (IERC1155Serendipity.ClaimParameters memory) {
        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;

        return IERC1155Serendipity.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 100,
            startDate: nowC,
            endDate: later,
            tokenVariations: 5,
            location: "arweaveHash1",
            paymentReceiver: payable(creator),
            cost: uint96(DEFAULT_COST),
            erc20: zeroAddress
        });
    }

    // ============ ACCESS CONTROL TESTS ============

    function test_initializeClaim_withMerkleRoot_requiresAdmin() public {
        vm.startPrank(unauthorized);
        
        IERC1155Serendipity.ClaimParameters memory claimP = _createBasicClaimParameters();
        
        // WILL FAIL - Function doesn't exist yet
        vm.expectRevert();
        serendipityWithAllowlist.initializeClaimWithAllowlist(
            address(creatorCore1), 
            1, 
            claimP, 
            merkleRoot,
            10 // walletMax
        );
        vm.stopPrank();
    }

    function test_initializeClaim_withMerkleRoot_succeedsForAdmin() public {
        vm.startPrank(creator);
        
        IERC1155Serendipity.ClaimParameters memory claimP = _createBasicClaimParameters();
        
        // WILL FAIL - Function doesn't exist yet
        serendipityWithAllowlist.initializeClaimWithAllowlist(
            address(creatorCore1), 
            1, 
            claimP, 
            merkleRoot,
            5 // walletMax
        );
        
        // WILL FAIL - Function doesn't exist yet
        IERC1155Serendipity.Claim memory claim = serendipityWithAllowlist.getClaim(address(creatorCore1), 1);
        
        assertEq(claim.totalMax, 100);
        assertEq(claim.tokenVariations, 5);
        vm.stopPrank();
    }

    function test_updateClaim_updatesMerkleRoot_requiresAdmin() public {
        vm.startPrank(creator);
        IERC1155Serendipity.ClaimParameters memory claimP = _createBasicClaimParameters();
        
        // WILL FAIL - Function doesn't exist yet
        serendipityWithAllowlist.initializeClaimWithAllowlist(
            address(creatorCore1), 
            1, 
            claimP, 
            merkleRoot,
            5
        );
        vm.stopPrank();

        // Setup new merkle root
        bytes32[] memory newAllowlist = new bytes32[](2);
        newAllowlist[0] = keccak256(abi.encode(alice));
        newAllowlist[1] = keccak256(abi.encode(bob));
        bytes32 newMerkleRoot = merkle.getRoot(newAllowlist);

        vm.startPrank(unauthorized);
        
        // Should revert as user is not admin
        vm.expectRevert();
        serendipityWithAllowlist.updateAllowlist(
            address(creatorCore1), 
            1, 
            newMerkleRoot,
            3  // walletMax
        );
        vm.stopPrank();

        vm.startPrank(creator);
        // Should succeed as creator is admin
        serendipityWithAllowlist.updateAllowlist(
            address(creatorCore1), 
            1, 
            newMerkleRoot,
            3  // walletMax
        );
        vm.stopPrank();
    }

    function test_initializeClaim_revertsForNonAdmin() public {
        vm.startPrank(alice);
        
        IERC1155Serendipity.ClaimParameters memory claimP = _createBasicClaimParameters();
        
        // WILL FAIL - Function doesn't exist yet
        vm.expectRevert("Wallet is not an administrator for contract");
        serendipityWithAllowlist.initializeClaimWithAllowlist(
            address(creatorCore1), 
            1, 
            claimP, 
            merkleRoot,
            5
        );
        vm.stopPrank();
    }

    // ============ MERKLE VALIDATION TESTS ============

    function test_mintReserve_validMerkleProof_alice() public {
        vm.startPrank(creator);
        IERC1155Serendipity.ClaimParameters memory claimP = _createBasicClaimParameters();
        
        // WILL FAIL - Function doesn't exist yet
        serendipityWithAllowlist.initializeClaimWithAllowlist(
            address(creatorCore1), 
            1, 
            claimP, 
            merkleRoot,
            5
        );
        vm.stopPrank();

        vm.startPrank(alice);
        
        // Mint with merkle proof
        mintIndices = new uint32[](1);
        mintIndices[0] = 0; // alice's index
        proofs = new bytes32[][](1);
        proofs[0] = merkleProofs[0]; // alice's proof
        
        serendipityWithAllowlist.mintReserve{value: DEFAULT_COST + MINT_FEE}(
            address(creatorCore1), 
            1, 
            1, // mint count
            mintIndices,
            proofs,
            alice
        );
        
        // Check user mint details
        Serendipity.UserMintDetails memory userMints = serendipityWithAllowlist.getUserMints(
            alice, 
            address(creatorCore1), 
            1
        );
        assertEq(userMints.reservedCount, 1);
        vm.stopPrank();
    }

    function test_mintReserve_validMerkleProof_bob() public {
        vm.startPrank(creator);
        IERC1155Serendipity.ClaimParameters memory claimP = _createBasicClaimParameters();
        
        // WILL FAIL - Function doesn't exist yet
        serendipityWithAllowlist.initializeClaimWithAllowlist(
            address(creatorCore1), 
            1, 
            claimP, 
            merkleRoot,
            5
        );
        vm.stopPrank();

        vm.startPrank(bob);
        
        // Mint with merkle proof
        mintIndices = new uint32[](1);
        mintIndices[0] = 1; // bob's index
        proofs = new bytes32[][](1);
        proofs[0] = merkleProofs[1]; // bob's proof
        
        serendipityWithAllowlist.mintReserve{value: (DEFAULT_COST + MINT_FEE) * 2}(
            address(creatorCore1), 
            1, 
            2, // mint count
            mintIndices,
            proofs,
            bob
        );
        
        // Check user mint details
        Serendipity.UserMintDetails memory userMints = serendipityWithAllowlist.getUserMints(
            bob, 
            address(creatorCore1), 
            1
        );
        assertEq(userMints.reservedCount, 2);
        vm.stopPrank();
    }

    function test_mintReserve_invalidMerkleProof() public {
        vm.startPrank(creator);
        IERC1155Serendipity.ClaimParameters memory claimP = _createBasicClaimParameters();
        
        // WILL FAIL - Function doesn't exist yet
        serendipityWithAllowlist.initializeClaimWithAllowlist(
            address(creatorCore1), 
            1, 
            claimP, 
            merkleRoot,
            5
        );
        vm.stopPrank();

        vm.startPrank(unauthorized);
        
        // WILL FAIL - Function doesn't exist yet
        vm.expectRevert("Invalid merkle proof");
        mintIndices = new uint32[](1);
        mintIndices[0] = 0;
        proofs = new bytes32[][](1);
        proofs[0] = merkleProofs[0]; // alice's proof but unauthorized sender
        
        serendipityWithAllowlist.mintReserve{value: DEFAULT_COST + MINT_FEE}(
            address(creatorCore1),
            1,
            1,
            mintIndices,
            proofs,
            unauthorized // Using unauthorized address with alice's proof should fail
        );
        vm.stopPrank();
    }

    function test_mintReserve_preventsMerkleReplay() public {
        vm.startPrank(creator);
        IERC1155Serendipity.ClaimParameters memory claimP = _createBasicClaimParameters();
        
        // WILL FAIL - Function doesn't exist yet
        serendipityWithAllowlist.initializeClaimWithAllowlist(
            address(creatorCore1), 
            1, 
            claimP, 
            merkleRoot,
            2 // walletMax of 2
        );
        vm.stopPrank();

        vm.startPrank(alice);
        
        // First mint should succeed
        // WILL FAIL - Function doesn't exist yet
        uint32[] memory mintIndices = new uint32[](1);
        mintIndices[0] = 0;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = merkleProofs[0];
        
        serendipityWithAllowlist.mintReserve{value: DEFAULT_COST + MINT_FEE}(
            address(creatorCore1),
            1,
            1,
            mintIndices,
            proofs,
            alice
        );
        
        // Second mint should succeed (still within wallet max)
        // WILL FAIL - Function doesn't exist yet
        mintIndices = new uint32[](1);
        mintIndices[0] = 0;
        proofs = new bytes32[][](1);
        proofs[0] = merkleProofs[0];
        
        serendipityWithAllowlist.mintReserve{value: DEFAULT_COST + MINT_FEE}(
            address(creatorCore1),
            1,
            1,
            mintIndices,
            proofs,
            alice
        );
        
        // Third mint should fail (exceeds wallet max)
        // WILL FAIL - Function doesn't exist yet
        vm.expectRevert("Exceeds wallet max");
        mintIndices = new uint32[](1);
        mintIndices[0] = 0;
        proofs = new bytes32[][](1);
        proofs[0] = merkleProofs[0];
        
        serendipityWithAllowlist.mintReserve{value: DEFAULT_COST + MINT_FEE}(
            address(creatorCore1),
            1,
            1,
            mintIndices,
            proofs,
            alice
        );
        vm.stopPrank();
    }

    function test_mintReserve_batchWithMerkle() public {
        vm.startPrank(creator);
        IERC1155Serendipity.ClaimParameters memory claimP = _createBasicClaimParameters();
        
        // WILL FAIL - Function doesn't exist yet
        serendipityWithAllowlist.initializeClaimWithAllowlist(
            address(creatorCore1), 
            1, 
            claimP, 
            merkleRoot,
            10
        );
        vm.stopPrank();

        vm.startPrank(alice);
        
        // WILL FAIL - Function doesn't exist yet
        mintIndices = new uint32[](1);
        mintIndices[0] = 0;
        proofs = new bytes32[][](1);
        proofs[0] = // batch mint 3
            merkleProofs[0];
        
        serendipityWithAllowlist.mintReserve{value: (DEFAULT_COST + MINT_FEE) * 3}(
            address(creatorCore1),
            1,
            3,
            mintIndices,
            proofs,
            alice
        );
        
        // Check user mint details
        Serendipity.UserMintDetails memory userMints = serendipityWithAllowlist.getUserMints(
            alice, 
            address(creatorCore1), 
            1
        );
        assertEq(userMints.reservedCount, 3);
        vm.stopPrank();
    }

    // ============ ALLOWLIST ENFORCEMENT TESTS ============

    function test_mintReserve_onlyAllowlisted() public {
        vm.startPrank(creator);
        IERC1155Serendipity.ClaimParameters memory claimP = _createBasicClaimParameters();
        
        // WILL FAIL - Function doesn't exist yet
        serendipityWithAllowlist.initializeClaimWithAllowlist(
            address(creatorCore1), 
            1, 
            claimP, 
            merkleRoot,
            5
        );
        vm.stopPrank();

        vm.startPrank(unauthorized);
        
        // Should fail for non-allowlisted user
        // WILL FAIL - Function doesn't exist yet
        vm.expectRevert("Invalid merkle proof");
        mintIndices = new uint32[](1);
        mintIndices[0] = 0;
        proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](0);
        
        serendipityWithAllowlist.mintReserve{value: DEFAULT_COST + MINT_FEE}(
            address(creatorCore1),
            1,
            1,
            mintIndices,
            proofs,
            unauthorized
        );
        vm.stopPrank();
    }

    function test_mintReserve_respectsWalletMax() public {
        vm.startPrank(creator);
        IERC1155Serendipity.ClaimParameters memory claimP = _createBasicClaimParameters();
        
        // WILL FAIL - Function doesn't exist yet
        serendipityWithAllowlist.initializeClaimWithAllowlist(
            address(creatorCore1), 
            1, 
            claimP, 
            merkleRoot,
            3 // wallet max of 3
        );
        vm.stopPrank();

        vm.startPrank(alice);
        
        // Mint up to wallet max should succeed
        // WILL FAIL - Function doesn't exist yet
        mintIndices = new uint32[](1);
        mintIndices[0] = 0;
        proofs = new bytes32[][](1);
        proofs[0] = merkleProofs[0];
        
        serendipityWithAllowlist.mintReserve{value: (DEFAULT_COST + MINT_FEE) * 3}(
            address(creatorCore1),
            1,
            3,
            mintIndices,
            proofs,
            alice
        );
        
        // Exceeding wallet max should fail
        // WILL FAIL - Function doesn't exist yet
        vm.expectRevert("Exceeds wallet max");
        mintIndices = new uint32[](1);
        mintIndices[0] = 0;
        proofs = new bytes32[][](1);
        proofs[0] = merkleProofs[0];
        
        serendipityWithAllowlist.mintReserve{value: DEFAULT_COST + MINT_FEE}(
            address(creatorCore1),
            1,
            1,
            mintIndices,
            proofs,
            alice
        );
        vm.stopPrank();
    }

    function test_mintReserve_emptyMerkleAllowsAll() public {
        vm.startPrank(creator);
        IERC1155Serendipity.ClaimParameters memory claimP = _createBasicClaimParameters();
        
        // WILL FAIL - Function doesn't exist yet
        serendipityWithAllowlist.initializeClaimWithAllowlist(
            address(creatorCore1), 
            1, 
            claimP, 
            bytes32(0), // empty merkle root
            5
        );
        vm.stopPrank();

        vm.startPrank(unauthorized);
        
        // Should succeed with empty merkle root (no allowlist)
        // WILL FAIL - Function doesn't exist yet
        mintIndices = new uint32[](1);
        mintIndices[0] = 0;
        proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](0);
        
        serendipityWithAllowlist.mintReserve{value: DEFAULT_COST + MINT_FEE}(
            address(creatorCore1),
            1,
            1,
            mintIndices,
            proofs,
            unauthorized
        );
        vm.stopPrank();
    }

    // ============ PAYMENT PROCESSING TESTS ============

    function test_mintReserve_correctETHPayment() public {
        vm.startPrank(creator);
        IERC1155Serendipity.ClaimParameters memory claimP = _createBasicClaimParameters();
        
        // WILL FAIL - Function doesn't exist yet
        serendipityWithAllowlist.initializeClaimWithAllowlist(
            address(creatorCore1), 
            1, 
            claimP, 
            merkleRoot,
            5
        );
        vm.stopPrank();

        vm.startPrank(alice);
        uint256 initialBalance = alice.balance;
        
        // WILL FAIL - Function doesn't exist yet
        mintIndices = new uint32[](1);
        mintIndices[0] = 0;
        proofs = new bytes32[][](1);
        proofs[0] = merkleProofs[0];
        
        serendipityWithAllowlist.mintReserve{value: DEFAULT_COST + MINT_FEE}(
            address(creatorCore1),
            1,
            1,
            mintIndices,
            proofs,
            alice
        );
        
        assertEq(alice.balance, initialBalance - (DEFAULT_COST + MINT_FEE));
        vm.stopPrank();
    }

    function test_mintReserve_correctERC20Payment() public {
        vm.startPrank(creator);
        IERC1155Serendipity.ClaimParameters memory claimP = _createBasicClaimParameters();
        claimP.erc20 = address(erc20Token);
        claimP.cost = 100 ether;
        
        // WILL FAIL - Function doesn't exist yet
        serendipityWithAllowlist.initializeClaimWithAllowlist(
            address(creatorCore1), 
            1, 
            claimP, 
            merkleRoot,
            5
        );
        vm.stopPrank();

        vm.startPrank(alice);
        erc20Token.approve(address(serendipityWithAllowlist), 100 ether);
        uint256 initialBalance = erc20Token.balanceOf(alice);
        
        // WILL FAIL - Function doesn't exist yet
        mintIndices = new uint32[](1);
        mintIndices[0] = 0;
        proofs = new bytes32[][](1);
        proofs[0] = merkleProofs[0];
        
        serendipityWithAllowlist.mintReserve{value: MINT_FEE}(
            // Still need ETH for mint fee
            address(creatorCore1),
            1,
            1,
            mintIndices,
            proofs,
            alice
        );
        
        assertEq(erc20Token.balanceOf(alice), initialBalance - 100 ether);
        vm.stopPrank();
    }

    function test_mintReserve_membershipDiscount() public {
        vm.startPrank(creator);
        IERC1155Serendipity.ClaimParameters memory claimP = _createBasicClaimParameters();
        
        // WILL FAIL - Function doesn't exist yet
        serendipityWithAllowlist.initializeClaimWithAllowlist(
            address(creatorCore1), 
            1, 
            claimP, 
            merkleRoot,
            5
        );
        vm.stopPrank();

        // Set membership address from owner context
        vm.startPrank(owner);
        serendipityWithAllowlist.setMembershipAddress(address(manifoldMembership));
        vm.stopPrank();

        vm.startPrank(alice); // alice is a member
        uint256 initialBalance = alice.balance;
        
        // WILL FAIL - Function doesn't exist yet
        mintIndices = new uint32[](1);
        mintIndices[0] = 0;
        proofs = new bytes32[][](1);
        proofs[0] = merkleProofs[0];
        
        serendipityWithAllowlist.mintReserve{value: DEFAULT_COST + MINT_FEE}(
            address(creatorCore1),
            1,
            1,
            mintIndices,
            proofs,
            alice
        );
        
        // Should pay less than DEFAULT_COST due to membership discount
        assertTrue(alice.balance > initialBalance - (DEFAULT_COST + MINT_FEE));
        vm.stopPrank();
    }

    // ============ DELIVERY SYSTEM TESTS ============

    function test_deliverMints_validSignature() public {
        vm.startPrank(creator);
        IERC1155Serendipity.ClaimParameters memory claimP = _createBasicClaimParameters();
        
        // WILL FAIL - Function doesn't exist yet
        serendipityWithAllowlist.initializeClaimWithAllowlist(
            address(creatorCore1), 
            1, 
            claimP, 
            merkleRoot,
            5
        );
        vm.stopPrank();

        vm.startPrank(alice);
        // WILL FAIL - Function doesn't exist yet
        mintIndices = new uint32[](1);
        mintIndices[0] = 0;
        proofs = new bytes32[][](1);
        proofs[0] = merkleProofs[0];
        
        serendipityWithAllowlist.mintReserve{value: DEFAULT_COST + MINT_FEE}(
            address(creatorCore1),
            1,
            1,
            mintIndices,
            proofs,
            alice
        );
        vm.stopPrank();

        vm.startPrank(signingAddress);
        ISerendipity.ClaimMint[] memory mints = new ISerendipity.ClaimMint[](1);
        ISerendipity.VariationMint[] memory variationMints = new ISerendipity.VariationMint[](1);
        variationMints[0] = ISerendipity.VariationMint({
            variationIndex: 1, 
            amount: 1, 
            recipient: alice
        });
        mints[0] = ISerendipity.ClaimMint({
            creatorContractAddress: address(creatorCore1),
            instanceId: 1,
            variationMints: variationMints
        });
        
        // WILL FAIL - Function doesn't exist yet
        serendipityWithAllowlist.deliverMints(mints);
        
        // Check user mint details
        Serendipity.UserMintDetails memory userMints = serendipityWithAllowlist.getUserMints(
            alice, 
            address(creatorCore1), 
            1
        );
        assertEq(userMints.deliveredCount, 1);
        vm.stopPrank();
    }

    function test_deliverMints_invalidSignature() public {
        vm.startPrank(creator);
        IERC1155Serendipity.ClaimParameters memory claimP = _createBasicClaimParameters();
        
        // WILL FAIL - Function doesn't exist yet
        serendipityWithAllowlist.initializeClaimWithAllowlist(
            address(creatorCore1), 
            1, 
            claimP, 
            merkleRoot,
            5
        );
        vm.stopPrank();

        vm.startPrank(alice);
        // WILL FAIL - Function doesn't exist yet
        mintIndices = new uint32[](1);
        mintIndices[0] = 0;
        proofs = new bytes32[][](1);
        proofs[0] = merkleProofs[0];
        
        serendipityWithAllowlist.mintReserve{value: DEFAULT_COST + MINT_FEE}(
            address(creatorCore1),
            1,
            1,
            mintIndices,
            proofs,
            alice
        );
        vm.stopPrank();

        vm.startPrank(unauthorized); // Invalid signer
        ISerendipity.ClaimMint[] memory mints = new ISerendipity.ClaimMint[](1);
        ISerendipity.VariationMint[] memory variationMints = new ISerendipity.VariationMint[](1);
        variationMints[0] = ISerendipity.VariationMint({
            variationIndex: 1, 
            amount: 1, 
            recipient: alice
        });
        mints[0] = ISerendipity.ClaimMint({
            creatorContractAddress: address(creatorCore1),
            instanceId: 1,
            variationMints: variationMints
        });
        
        // WILL FAIL - Function doesn't exist yet
        vm.expectRevert();
        serendipityWithAllowlist.deliverMints(mints);
        vm.stopPrank();
    }

    function test_deliverMints_updatesDeliveredCount() public {
        vm.startPrank(creator);
        IERC1155Serendipity.ClaimParameters memory claimP = _createBasicClaimParameters();
        
        // WILL FAIL - Function doesn't exist yet
        serendipityWithAllowlist.initializeClaimWithAllowlist(
            address(creatorCore1), 
            1, 
            claimP, 
            merkleRoot,
            5
        );
        vm.stopPrank();

        vm.startPrank(alice);
        // WILL FAIL - Function doesn't exist yet
        mintIndices = new uint32[](1);
        mintIndices[0] = 0;
        proofs = new bytes32[][](1);
        proofs[0] = merkleProofs[0];
        
        serendipityWithAllowlist.mintReserve{value: (DEFAULT_COST + MINT_FEE) * 3}(
            address(creatorCore1),
            1,
            3,
            mintIndices,
            proofs,
            alice
        );
        vm.stopPrank();

        vm.startPrank(signingAddress);
        ISerendipity.ClaimMint[] memory mints = new ISerendipity.ClaimMint[](1);
        ISerendipity.VariationMint[] memory variationMints = new ISerendipity.VariationMint[](1);
        variationMints[0] = ISerendipity.VariationMint({
            variationIndex: 1, 
            amount: 2, 
            recipient: alice
        });
        mints[0] = ISerendipity.ClaimMint({
            creatorContractAddress: address(creatorCore1),
            instanceId: 1,
            variationMints: variationMints
        });
        
        // WILL FAIL - Function doesn't exist yet
        serendipityWithAllowlist.deliverMints(mints);
        
        // Check user mint details
        Serendipity.UserMintDetails memory userMints = serendipityWithAllowlist.getUserMints(
            alice, 
            address(creatorCore1), 
            1
        );
        assertEq(userMints.reservedCount, 3);
        assertEq(userMints.deliveredCount, 2);
        vm.stopPrank();
    }

    // ============ STATE MANAGEMENT TESTS ============

    function test_reservation_tracking() public {
        vm.startPrank(creator);
        IERC1155Serendipity.ClaimParameters memory claimP = _createBasicClaimParameters();
        
        // WILL FAIL - Function doesn't exist yet
        serendipityWithAllowlist.initializeClaimWithAllowlist(
            address(creatorCore1), 
            1, 
            claimP, 
            merkleRoot,
            10
        );
        vm.stopPrank();

        // Alice reserves 2
        vm.startPrank(alice);
        // WILL FAIL - Function doesn't exist yet
        mintIndices = new uint32[](1);
        mintIndices[0] = 0;
        proofs = new bytes32[][](1);
        proofs[0] = merkleProofs[0];
        
        serendipityWithAllowlist.mintReserve{value: (DEFAULT_COST + MINT_FEE) * 2}(
            address(creatorCore1),
            1,
            2,
            mintIndices,
            proofs,
            alice
        );
        vm.stopPrank();

        // Bob reserves 3
        vm.startPrank(bob);
        // WILL FAIL - Function doesn't exist yet
        mintIndices = new uint32[](1);
        mintIndices[0] = 1;
        proofs = new bytes32[][](1);
        proofs[0] = merkleProofs[1];
        
        serendipityWithAllowlist.mintReserve{value: (DEFAULT_COST + MINT_FEE) * 3}(
            address(creatorCore1),
            1,
            3,
            mintIndices,
            proofs,
            bob
        );
        vm.stopPrank();

        // Check claim state
        // WILL FAIL - Function doesn't exist yet
        IERC1155Serendipity.Claim memory claim = serendipityWithAllowlist.getClaim(address(creatorCore1), 1);
        assertEq(claim.total, 5); // 2 + 3 = 5 reserved
    }

    function test_claimExpiry_blocksMinting() public {
        vm.startPrank(creator);
        IERC1155Serendipity.ClaimParameters memory claimP = _createBasicClaimParameters();
        claimP.endDate = uint48(block.timestamp + 100); // Short expiry
        
        // WILL FAIL - Function doesn't exist yet
        serendipityWithAllowlist.initializeClaimWithAllowlist(
            address(creatorCore1), 
            1, 
            claimP, 
            merkleRoot,
            5
        );
        vm.stopPrank();

        // Fast forward past expiry
        vm.warp(block.timestamp + 200);

        vm.startPrank(alice);
        // WILL FAIL - Function doesn't exist yet
        vm.expectRevert(ISerendipity.ClaimInactive.selector);
        mintIndices = new uint32[](1);
        mintIndices[0] = 0;
        proofs = new bytes32[][](1);
        proofs[0] = merkleProofs[0];
        
        serendipityWithAllowlist.mintReserve{value: DEFAULT_COST + MINT_FEE}(
            address(creatorCore1),
            1,
            1,
            mintIndices,
            proofs,
            alice
        );
        vm.stopPrank();
    }

    function test_totalMax_enforcement() public {
        vm.startPrank(creator);
        IERC1155Serendipity.ClaimParameters memory claimP = _createBasicClaimParameters();
        claimP.totalMax = 3; // Very small limit
        
        // WILL FAIL - Function doesn't exist yet
        serendipityWithAllowlist.initializeClaimWithAllowlist(
            address(creatorCore1), 
            1, 
            claimP, 
            merkleRoot,
            5
        );
        vm.stopPrank();

        // Alice reserves 2
        vm.startPrank(alice);
        // WILL FAIL - Function doesn't exist yet
        mintIndices = new uint32[](1);
        mintIndices[0] = 0;
        proofs = new bytes32[][](1);
        proofs[0] = merkleProofs[0];
        
        serendipityWithAllowlist.mintReserve{value: (DEFAULT_COST + MINT_FEE) * 2}(
            address(creatorCore1),
            1,
            2,
            mintIndices,
            proofs,
            alice
        );
        vm.stopPrank();

        // Bob tries to reserve 2 more (would exceed totalMax of 3)
        vm.startPrank(bob);
        // WILL FAIL - Function doesn't exist yet
        vm.expectRevert(ISerendipity.ClaimSoldOut.selector);
        mintIndices = new uint32[](1);
        mintIndices[0] = 1;
        proofs = new bytes32[][](1);
        proofs[0] = merkleProofs[1];
        
        serendipityWithAllowlist.mintReserve{value: (DEFAULT_COST + MINT_FEE) * 2}(
            address(creatorCore1),
            1,
            2,
            mintIndices,
            proofs,
            bob
        );
        vm.stopPrank();

        // Bob should be able to reserve exactly 1 more (total = 3)
        vm.startPrank(bob);
        // WILL FAIL - Function doesn't exist yet
        mintIndices = new uint32[](1);
        mintIndices[0] = 1;
        proofs = new bytes32[][](1);
        proofs[0] = merkleProofs[1];
        
        serendipityWithAllowlist.mintReserve{value: DEFAULT_COST + MINT_FEE}(
            address(creatorCore1),
            1,
            1,
            mintIndices,
            proofs,
            bob
        );
        vm.stopPrank();
    }

    // ============ EDGE CASE TESTS ============

    function test_mintReserve_zeroAmount() public {
        vm.startPrank(creator);
        IERC1155Serendipity.ClaimParameters memory claimP = _createBasicClaimParameters();
        
        // WILL FAIL - Function doesn't exist yet
        serendipityWithAllowlist.initializeClaimWithAllowlist(
            address(creatorCore1), 
            1, 
            claimP, 
            merkleRoot,
            5
        );
        vm.stopPrank();

        vm.startPrank(alice);
        // WILL FAIL - Function doesn't exist yet
        vm.expectRevert(ISerendipity.InvalidMintCount.selector);
        mintIndices = new uint32[](1);
        mintIndices[0] = 0;
        proofs = new bytes32[][](1);
        proofs[0] = // zero amount
            merkleProofs[0];
        
        serendipityWithAllowlist.mintReserve{value: MINT_FEE}(
            address(creatorCore1),
            1,
            0,
            mintIndices,
            proofs,
            alice
        );
        vm.stopPrank();
    }

    function test_mintReserve_insufficientPayment() public {
        vm.startPrank(creator);
        IERC1155Serendipity.ClaimParameters memory claimP = _createBasicClaimParameters();
        
        // WILL FAIL - Function doesn't exist yet
        serendipityWithAllowlist.initializeClaimWithAllowlist(
            address(creatorCore1), 
            1, 
            claimP, 
            merkleRoot,
            5
        );
        vm.stopPrank();

        vm.startPrank(alice);
        // WILL FAIL - Function doesn't exist yet
        vm.expectRevert(ISerendipity.InvalidPayment.selector);
        mintIndices = new uint32[](1);
        mintIndices[0] = 0;
        proofs = new bytes32[][](1);
        proofs[0] = merkleProofs[0];
        
        serendipityWithAllowlist.mintReserve{value: DEFAULT_COST}(
            // Missing MINT_FEE
            address(creatorCore1),
            1,
            1,
            mintIndices,
            proofs,
            alice
        );
        vm.stopPrank();
    }

    function test_allowlistUpdate_afterMinting() public {
        vm.startPrank(creator);
        IERC1155Serendipity.ClaimParameters memory claimP = _createBasicClaimParameters();
        
        // WILL FAIL - Function doesn't exist yet
        serendipityWithAllowlist.initializeClaimWithAllowlist(
            address(creatorCore1), 
            1, 
            claimP, 
            merkleRoot,
            5
        );
        vm.stopPrank();

        // Alice mints with original allowlist
        vm.startPrank(alice);
        // WILL FAIL - Function doesn't exist yet
        mintIndices = new uint32[](1);
        mintIndices[0] = 0;
        proofs = new bytes32[][](1);
        proofs[0] = merkleProofs[0];
        
        serendipityWithAllowlist.mintReserve{value: DEFAULT_COST + MINT_FEE}(
            address(creatorCore1),
            1,
            1,
            mintIndices,
            proofs,
            alice
        );
        vm.stopPrank();

        // Update allowlist to exclude alice
        bytes32[] memory newAllowlist = new bytes32[](2);
        newAllowlist[0] = keccak256(abi.encode(bob));
        newAllowlist[1] = keccak256(abi.encode(charlie));
        bytes32 newMerkleRoot = merkle.getRoot(newAllowlist);

        vm.startPrank(creator);
        // WILL FAIL - Function doesn't exist yet
        serendipityWithAllowlist.updateAllowlist(address(creatorCore1), 1, newMerkleRoot, 3);
        vm.stopPrank();

        // Alice should no longer be able to mint
        vm.startPrank(alice);
        // WILL FAIL - Function doesn't exist yet
        vm.expectRevert("Invalid merkle proof");
        mintIndices = new uint32[](1);
        mintIndices[0] = 0;
        proofs = new bytes32[][](1);
        proofs[0] = merkleProofs[0]; // Old proof no longer valid
        
        serendipityWithAllowlist.mintReserve{value: DEFAULT_COST + MINT_FEE}(
            address(creatorCore1),
            1,
            1,
            mintIndices,
            proofs,
            alice
        );
        vm.stopPrank();
    }

    function test_delegation_support() public {
        vm.startPrank(creator);
        IERC1155Serendipity.ClaimParameters memory claimP = _createBasicClaimParameters();
        
        // WILL FAIL - Function doesn't exist yet
        serendipityWithAllowlist.initializeClaimWithAllowlist(
            address(creatorCore1), 
            1, 
            claimP, 
            merkleRoot,
            5
        );
        vm.stopPrank();

        // Setup delegation (alice delegates to bob)
        vm.startPrank(alice);
        delegationRegistry.delegateForContract(bob, address(creatorCore1), true);
        vm.stopPrank();

        vm.startPrank(bob);
        // WILL FAIL - Function doesn't exist yet
        mintIndices = new uint32[](1);
        mintIndices[0] = 0;
        proofs = new bytes32[][](1);
        proofs[0] = merkleProofs[0]; // alice's proof
        
        serendipityWithAllowlist.mintReserve{value: DEFAULT_COST + MINT_FEE}(
            address(creatorCore1),
            1,
            1,
            mintIndices,
            proofs,
            alice // delegator
        );
        
        // Check user mint details
        Serendipity.UserMintDetails memory userMints = serendipityWithAllowlist.getUserMints(
            alice, 
            address(creatorCore1), 
            1
        );
        assertEq(userMints.reservedCount, 1);
        vm.stopPrank();
    }

    // ============ INTEGRATION TESTS ============

    function test_fullWorkflow_multipleUsers() public {
        vm.startPrank(creator);
        IERC1155Serendipity.ClaimParameters memory claimP = _createBasicClaimParameters();
        
        // WILL FAIL - Function doesn't exist yet
        serendipityWithAllowlist.initializeClaimWithAllowlist(
            address(creatorCore1), 
            1, 
            claimP, 
            merkleRoot,
            5
        );
        vm.stopPrank();

        // Alice mints 2
        vm.startPrank(alice);
        // WILL FAIL - Function doesn't exist yet
        mintIndices = new uint32[](1);
        mintIndices[0] = 0;
        proofs = new bytes32[][](1);
        proofs[0] = merkleProofs[0];
        
        serendipityWithAllowlist.mintReserve{value: (DEFAULT_COST + MINT_FEE) * 2}(
            address(creatorCore1),
            1,
            2,
            mintIndices,
            proofs,
            alice
        );
        vm.stopPrank();

        // Bob mints 1
        vm.startPrank(bob);
        // WILL FAIL - Function doesn't exist yet
        mintIndices = new uint32[](1);
        mintIndices[0] = 1;
        proofs = new bytes32[][](1);
        proofs[0] = merkleProofs[1];
        
        serendipityWithAllowlist.mintReserve{value: DEFAULT_COST + MINT_FEE}(
            address(creatorCore1),
            1,
            1,
            mintIndices,
            proofs,
            bob
        );
        vm.stopPrank();

        // Charlie mints 2
        vm.startPrank(charlie);
        // WILL FAIL - Function doesn't exist yet
        mintIndices = new uint32[](1);
        mintIndices[0] = 2;
        proofs = new bytes32[][](1);
        proofs[0] = merkleProofs[2];
        
        serendipityWithAllowlist.mintReserve{value: (DEFAULT_COST + MINT_FEE) * 2}(
            address(creatorCore1),
            1,
            2,
            mintIndices,
            proofs,
            charlie
        );
        vm.stopPrank();

        // Deliver mints
        vm.startPrank(signingAddress);
        ISerendipity.ClaimMint[] memory mints = new ISerendipity.ClaimMint[](3);
        
        // Alice gets 2 different variations
        ISerendipity.VariationMint[] memory aliceVariations = new ISerendipity.VariationMint[](2);
        aliceVariations[0] = ISerendipity.VariationMint({variationIndex: 1, amount: 1, recipient: alice});
        aliceVariations[1] = ISerendipity.VariationMint({variationIndex: 2, amount: 1, recipient: alice});
        mints[0] = ISerendipity.ClaimMint({
            creatorContractAddress: address(creatorCore1),
            instanceId: 1,
            variationMints: aliceVariations
        });

        // Bob gets 1 variation
        ISerendipity.VariationMint[] memory bobVariations = new ISerendipity.VariationMint[](1);
        bobVariations[0] = ISerendipity.VariationMint({variationIndex: 3, amount: 1, recipient: bob});
        mints[1] = ISerendipity.ClaimMint({
            creatorContractAddress: address(creatorCore1),
            instanceId: 1,
            variationMints: bobVariations
        });

        // Charlie gets 2 of same variation
        ISerendipity.VariationMint[] memory charlieVariations = new ISerendipity.VariationMint[](1);
        charlieVariations[0] = ISerendipity.VariationMint({variationIndex: 4, amount: 2, recipient: charlie});
        mints[2] = ISerendipity.ClaimMint({
            creatorContractAddress: address(creatorCore1),
            instanceId: 1,
            variationMints: charlieVariations
        });

        // WILL FAIL - Function doesn't exist yet
        serendipityWithAllowlist.deliverMints(mints);
        vm.stopPrank();

        // Verify final state
        // WILL FAIL - Function doesn't exist yet
        IERC1155Serendipity.Claim memory claim = serendipityWithAllowlist.getClaim(address(creatorCore1), 1);
        assertEq(claim.total, 5); // 2 + 1 + 2 = 5

        // WILL FAIL - Function doesn't exist yet
        Serendipity.UserMintDetails memory aliceDetails = serendipityWithAllowlist.getUserMints(alice, address(creatorCore1), 1);
        assertEq(aliceDetails.reservedCount, 2);
        assertEq(aliceDetails.deliveredCount, 2);

        // WILL FAIL - Function doesn't exist yet
        Serendipity.UserMintDetails memory bobDetails = serendipityWithAllowlist.getUserMints(bob, address(creatorCore1), 1);
        assertEq(bobDetails.reservedCount, 1);
        assertEq(bobDetails.deliveredCount, 1);

        // WILL FAIL - Function doesn't exist yet
        Serendipity.UserMintDetails memory charlieDetails = serendipityWithAllowlist.getUserMints(charlie, address(creatorCore1), 1);
        assertEq(charlieDetails.reservedCount, 2);
        assertEq(charlieDetails.deliveredCount, 2);

        // Check token balances
        assertEq(creatorCore1.balanceOf(alice, 1), 1); // variation 1
        assertEq(creatorCore1.balanceOf(alice, 2), 1); // variation 2
        assertEq(creatorCore1.balanceOf(bob, 3), 1); // variation 3
        assertEq(creatorCore1.balanceOf(charlie, 4), 2); // variation 4
    }
}