// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../contracts/gachaclaims/IERC1155SerendipityWithAllowlist.sol";
import "../../contracts/gachaclaims/ERC1155SerendipityWithAllowlist.sol";
import "../../contracts/gachaclaims/ISerendipity.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC1155Creator.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract ERC1155SerendipityWithAllowlistTest is Test {
    ERC1155SerendipityWithAllowlist public extension;
    ERC1155Creator public creatorCore;

    address public creator = 0xc78Dc443c126af6E4f6Ed540c1e740C1b5be09cd;
    address public owner = 0x6140F00e4Ff3936702E68744f2b5978885464cbB;
    address public signingAddress = 0xc78dC443c126Af6E4f6eD540C1E740c1B5be09CE;
    address public alice = 0x5174cD462b60c536eb51D4ceC1D561D3Ea31004F;
    address public bob = 0x80AAC46bbd3C2FcE33681541a52CacBEd14bF425;
    address public charlie = 0x1234567890123456789012345678901234567890;
    address public unauthorized = 0x9876543210987654321098765432109876543210;

    uint256 public constant MINT_FEE = 500000000000000;
    uint256 public constant MINT_FEE_MERKLE = 690000000000000;

    // Merkle tree data for testing (alice, bob, charlie)
    bytes32 public merkleRoot;
    bytes32[] public aliceProof;
    bytes32[] public bobProof;
    bytes32[] public charlieProof;

    function setUp() public {
        // Deploy creator contract
        vm.startPrank(creator);
        creatorCore = new ERC1155Creator("Test", "TEST");
        vm.stopPrank();

        // Deploy extension
        vm.startPrank(owner);
        extension = new ERC1155SerendipityWithAllowlist(owner);
        extension.setSigner(signingAddress);
        vm.stopPrank();

        // Register extension
        vm.startPrank(creator);
        creatorCore.registerExtension(address(extension), "override");
        vm.stopPrank();

        // Setup merkle tree
        _setupMerkleTree();

        // Fund test accounts
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        vm.deal(charlie, 10 ether);
        vm.deal(unauthorized, 10 ether);
    }

    function _setupMerkleTree() internal {
        // Create a simple merkle tree with alice, bob, charlie
        // For simplicity, we'll use a 4-leaf tree (padding with duplicate)
        bytes32[] memory leaves = new bytes32[](4);
        leaves[0] = keccak256(abi.encodePacked(alice));
        leaves[1] = keccak256(abi.encodePacked(bob));
        leaves[2] = keccak256(abi.encodePacked(charlie));
        leaves[3] = keccak256(abi.encodePacked(charlie)); // Duplicate for even number

        // Build merkle tree
        // Level 0: [alice, bob, charlie, charlie]
        // Level 1: [hash(alice, bob), hash(charlie, charlie)]
        // Level 2: [root]
        bytes32 hash01 = _hashPair(leaves[0], leaves[1]);
        bytes32 hash23 = _hashPair(leaves[2], leaves[3]);
        merkleRoot = _hashPair(hash01, hash23);

        // Build proofs
        aliceProof = new bytes32[](2);
        aliceProof[0] = leaves[1]; // bob
        aliceProof[1] = hash23; // hash(charlie, charlie)

        bobProof = new bytes32[](2);
        bobProof[0] = leaves[0]; // alice
        bobProof[1] = hash23; // hash(charlie, charlie)

        charlieProof = new bytes32[](2);
        charlieProof[0] = leaves[3]; // charlie (duplicate)
        charlieProof[1] = hash01; // hash(alice, bob)
    }

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    // ============ Initialization Tests ============

    function test_initializeClaim_withMerkleRoot_succeedsForAdmin() public {
        vm.startPrank(creator);
        
        IERC1155SerendipityWithAllowlist.ClaimParameters memory params = IERC1155SerendipityWithAllowlist.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 100,
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + 1000),
            tokenVariations: 5,
            location: "test-location",
            paymentReceiver: payable(creator),
            cost: 0.01 ether,
            erc20: address(0),
            merkleRoot: merkleRoot,
            walletMax: 2
        });

        extension.initializeClaim(address(creatorCore), 1, params);

        IERC1155SerendipityWithAllowlist.Claim memory claim = extension.getClaim(address(creatorCore), 1);
        assertEq(claim.merkleRoot, merkleRoot);
        assertEq(claim.walletMax, 2);
        assertEq(claim.totalMax, 100);
    }

    function test_initializeClaim_withoutMerkleRoot_succeedsForAdmin() public {
        vm.startPrank(creator);
        
        IERC1155SerendipityWithAllowlist.ClaimParameters memory params = IERC1155SerendipityWithAllowlist.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.IPFS,
            totalMax: 50,
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + 2000),
            tokenVariations: 3,
            location: "ipfs-location",
            paymentReceiver: payable(creator),
            cost: 0.02 ether,
            erc20: address(0),
            merkleRoot: bytes32(0),
            walletMax: 5
        });

        extension.initializeClaim(address(creatorCore), 2, params);

        IERC1155SerendipityWithAllowlist.Claim memory claim = extension.getClaim(address(creatorCore), 2);
        assertEq(claim.merkleRoot, bytes32(0));
        assertEq(claim.walletMax, 5);
        assertEq(claim.totalMax, 50);
    }

    function test_initializeClaim_revertsForNonAdmin() public {
        vm.startPrank(unauthorized);
        
        IERC1155SerendipityWithAllowlist.ClaimParameters memory params = IERC1155SerendipityWithAllowlist.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 100,
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + 1000),
            tokenVariations: 5,
            location: "test-location",
            paymentReceiver: payable(creator),
            cost: 0.01 ether,
            erc20: address(0),
            merkleRoot: merkleRoot,
            walletMax: 2
        });

        vm.expectRevert("Wallet is not an administrator for contract");
        extension.initializeClaim(address(creatorCore), 3, params);
    }

    // ============ Update Tests ============

    function test_updateClaim_withMerkleRoot_succeedsForAdmin() public {
        // First initialize a claim
        vm.startPrank(creator);
        
        IERC1155SerendipityWithAllowlist.ClaimParameters memory params = IERC1155SerendipityWithAllowlist.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 100,
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + 1000),
            tokenVariations: 5,
            location: "test-location",
            paymentReceiver: payable(creator),
            cost: 0.01 ether,
            erc20: address(0),
            merkleRoot: bytes32(0),
            walletMax: 0
        });

        extension.initializeClaim(address(creatorCore), 4, params);

        // Now update it with merkle root
        IERC1155SerendipityWithAllowlist.UpdateClaimParameters memory updateParams = IERC1155SerendipityWithAllowlist.UpdateClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.IPFS,
            paymentReceiver: payable(bob),
            totalMax: 200,
            startDate: uint48(block.timestamp + 100),
            endDate: uint48(block.timestamp + 2000),
            cost: 0.02 ether,
            location: "updated-location",
            merkleRoot: merkleRoot,
            walletMax: 3
        });

        extension.updateClaim(address(creatorCore), 4, updateParams);

        IERC1155SerendipityWithAllowlist.Claim memory claim = extension.getClaim(address(creatorCore), 4);
        assertEq(claim.merkleRoot, merkleRoot);
        assertEq(claim.walletMax, 3);
        assertEq(claim.totalMax, 200);
        assertEq(claim.paymentReceiver, bob);
    }

    function test_updateClaim_revertsForNonAdmin() public {
        // First initialize a claim as admin
        vm.startPrank(creator);
        
        IERC1155SerendipityWithAllowlist.ClaimParameters memory params = IERC1155SerendipityWithAllowlist.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 100,
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + 1000),
            tokenVariations: 5,
            location: "test-location",
            paymentReceiver: payable(creator),
            cost: 0.01 ether,
            erc20: address(0),
            merkleRoot: bytes32(0),
            walletMax: 0
        });

        extension.initializeClaim(address(creatorCore), 5, params);
        vm.stopPrank();

        // Try to update as non-admin
        vm.startPrank(unauthorized);
        
        IERC1155SerendipityWithAllowlist.UpdateClaimParameters memory updateParams = IERC1155SerendipityWithAllowlist.UpdateClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.IPFS,
            paymentReceiver: payable(unauthorized),
            totalMax: 200,
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + 2000),
            cost: 0.02 ether,
            location: "hacked-location",
            merkleRoot: merkleRoot,
            walletMax: 10
        });

        vm.expectRevert("Wallet is not an administrator for contract");
        extension.updateClaim(address(creatorCore), 5, updateParams);
    }

    // ============ Minting Tests with Merkle Proof ============

    function test_mintReserve_validMerkleProof_alice() public {
        // Initialize claim with merkle root
        vm.startPrank(creator);
        
        IERC1155SerendipityWithAllowlist.ClaimParameters memory params = IERC1155SerendipityWithAllowlist.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 100,
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + 1000),
            tokenVariations: 5,
            location: "test-location",
            paymentReceiver: payable(creator),
            cost: 0.01 ether,
            erc20: address(0),
            merkleRoot: merkleRoot,
            walletMax: 2
        });

        extension.initializeClaim(address(creatorCore), 10, params);
        vm.stopPrank();

        // Alice mints with valid proof
        vm.startPrank(alice);
        uint256 totalCost = (0.01 ether + MINT_FEE_MERKLE);
        
        extension.mintReserve{value: totalCost}(
            address(creatorCore), 
            10, 
            1,
            aliceProof
        );

        ISerendipity.UserMintDetails memory details = extension.getUserMints(alice, address(creatorCore), 10);
        assertEq(details.reservedCount, 1);
    }

    function test_mintReserve_validMerkleProof_bob() public {
        // Initialize claim with merkle root
        vm.startPrank(creator);
        
        IERC1155SerendipityWithAllowlist.ClaimParameters memory params = IERC1155SerendipityWithAllowlist.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 100,
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + 1000),
            tokenVariations: 5,
            location: "test-location",
            paymentReceiver: payable(creator),
            cost: 0.01 ether,
            erc20: address(0),
            merkleRoot: merkleRoot,
            walletMax: 2
        });

        extension.initializeClaim(address(creatorCore), 11, params);
        vm.stopPrank();

        // Bob mints with valid proof
        vm.startPrank(bob);
        uint256 totalCost = (0.01 ether + MINT_FEE_MERKLE);
        
        extension.mintReserve{value: totalCost}(
            address(creatorCore), 
            11, 
            1,
            bobProof
        );

        ISerendipity.UserMintDetails memory details = extension.getUserMints(bob, address(creatorCore), 11);
        assertEq(details.reservedCount, 1);
    }

    function test_mintReserve_invalidMerkleProof_reverts() public {
        // Initialize claim with merkle root
        vm.startPrank(creator);
        
        IERC1155SerendipityWithAllowlist.ClaimParameters memory params = IERC1155SerendipityWithAllowlist.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 100,
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + 1000),
            tokenVariations: 5,
            location: "test-location",
            paymentReceiver: payable(creator),
            cost: 0.01 ether,
            erc20: address(0),
            merkleRoot: merkleRoot,
            walletMax: 2
        });

        extension.initializeClaim(address(creatorCore), 12, params);
        vm.stopPrank();

        // Unauthorized user tries to mint with alice's proof
        vm.startPrank(unauthorized);
        uint256 totalCost = (0.01 ether + MINT_FEE_MERKLE);
        
        vm.expectRevert(ERC1155SerendipityWithAllowlist.InvalidMerkleProof.selector);
        extension.mintReserve{value: totalCost}(
            address(creatorCore), 
            12, 
            1,
            aliceProof
        );
    }

    function test_mintReserve_emptyMerkleProof_whenNoMerkleRoot() public {
        // Initialize claim without merkle root
        vm.startPrank(creator);
        
        IERC1155SerendipityWithAllowlist.ClaimParameters memory params = IERC1155SerendipityWithAllowlist.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 100,
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + 1000),
            tokenVariations: 5,
            location: "test-location",
            paymentReceiver: payable(creator),
            cost: 0.01 ether,
            erc20: address(0),
            merkleRoot: bytes32(0),
            walletMax: 0
        });

        extension.initializeClaim(address(creatorCore), 13, params);
        vm.stopPrank();

        // Anyone can mint when no merkle root
        vm.startPrank(unauthorized);
        uint256 totalCost = (0.01 ether + MINT_FEE);
        bytes32[] memory emptyProof = new bytes32[](0);
        
        extension.mintReserve{value: totalCost}(
            address(creatorCore), 
            13, 
            1,
            emptyProof
        );

        ISerendipity.UserMintDetails memory details = extension.getUserMints(unauthorized, address(creatorCore), 13);
        assertEq(details.reservedCount, 1);
    }

    // ============ Wallet Max Tests ============

    function test_walletMax_withMerkleRoot_enforced() public {
        // Initialize claim with merkle root and wallet max
        vm.startPrank(creator);
        
        IERC1155SerendipityWithAllowlist.ClaimParameters memory params = IERC1155SerendipityWithAllowlist.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 100,
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + 1000),
            tokenVariations: 5,
            location: "test-location",
            paymentReceiver: payable(creator),
            cost: 0.01 ether,
            erc20: address(0),
            merkleRoot: merkleRoot,
            walletMax: 2
        });

        extension.initializeClaim(address(creatorCore), 20, params);
        vm.stopPrank();

        // Alice mints 2 (wallet max)
        vm.startPrank(alice);
        uint256 totalCost = (0.01 ether + MINT_FEE_MERKLE) * 2;
        
        extension.mintReserve{value: totalCost}(
            address(creatorCore), 
            20, 
            2,
            aliceProof
        );

        // Try to mint more than wallet max
        vm.expectRevert(ISerendipity.TooManyRequested.selector);
        extension.mintReserve{value: 0.01 ether + MINT_FEE_MERKLE}(
            address(creatorCore), 
            20, 
            1,
            aliceProof
        );
    }

    function test_walletMax_withoutMerkleRoot_enforced() public {
        // Initialize claim without merkle root but with wallet max
        vm.startPrank(creator);
        
        IERC1155SerendipityWithAllowlist.ClaimParameters memory params = IERC1155SerendipityWithAllowlist.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 100,
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + 1000),
            tokenVariations: 5,
            location: "test-location",
            paymentReceiver: payable(creator),
            cost: 0.01 ether,
            erc20: address(0),
            merkleRoot: bytes32(0),
            walletMax: 3
        });

        extension.initializeClaim(address(creatorCore), 21, params);
        vm.stopPrank();

        // Unauthorized user mints 3 (wallet max)
        vm.startPrank(unauthorized);
        uint256 totalCost = (0.01 ether + MINT_FEE) * 3;
        bytes32[] memory emptyProof = new bytes32[](0);
        
        extension.mintReserve{value: totalCost}(
            address(creatorCore), 
            21, 
            3,
            emptyProof
        );

        // Try to mint more than wallet max
        vm.expectRevert(ISerendipity.TooManyRequested.selector);
        extension.mintReserve{value: 0.01 ether + MINT_FEE}(
            address(creatorCore), 
            21, 
            1,
            emptyProof
        );
    }

    // ============ Delivery Tests ============

    function test_deliverMints_afterReservation() public {
        // Initialize claim
        vm.startPrank(creator);
        
        IERC1155SerendipityWithAllowlist.ClaimParameters memory params = IERC1155SerendipityWithAllowlist.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 100,
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + 1000),
            tokenVariations: 5,
            location: "test-location",
            paymentReceiver: payable(creator),
            cost: 0.01 ether,
            erc20: address(0),
            merkleRoot: merkleRoot,
            walletMax: 5
        });

        extension.initializeClaim(address(creatorCore), 30, params);
        vm.stopPrank();

        // Alice reserves mints
        vm.startPrank(alice);
        uint256 totalCost = (0.01 ether + MINT_FEE_MERKLE) * 3;
        
        extension.mintReserve{value: totalCost}(
            address(creatorCore), 
            30, 
            3,
            aliceProof
        );
        vm.stopPrank();

        // Deliver mints as signer
        vm.startPrank(signingAddress);
        
        ISerendipity.VariationMint[] memory variations = new ISerendipity.VariationMint[](1);
        variations[0] = ISerendipity.VariationMint({
            variationIndex: 1,
            amount: 3,
            recipient: alice
        });

        ISerendipity.ClaimMint[] memory mints = new ISerendipity.ClaimMint[](1);
        mints[0] = ISerendipity.ClaimMint({
            creatorContractAddress: address(creatorCore),
            instanceId: 30,
            variationMints: variations
        });

        extension.deliverMints(mints);

        ISerendipity.UserMintDetails memory details = extension.getUserMints(alice, address(creatorCore), 30);
        assertEq(details.reservedCount, 3);
        assertEq(details.deliveredCount, 3);
    }

    // ============ Payment Tests ============

    function test_payment_correctAmountRequired() public {
        // Initialize claim with cost
        vm.startPrank(creator);
        
        IERC1155SerendipityWithAllowlist.ClaimParameters memory params = IERC1155SerendipityWithAllowlist.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 100,
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + 1000),
            tokenVariations: 5,
            location: "test-location",
            paymentReceiver: payable(creator),
            cost: 0.1 ether,
            erc20: address(0),
            merkleRoot: merkleRoot,
            walletMax: 2
        });

        extension.initializeClaim(address(creatorCore), 40, params);
        vm.stopPrank();

        vm.startPrank(alice);
        
        // Try with insufficient payment
        vm.expectRevert(ISerendipity.InvalidPayment.selector);
        extension.mintReserve{value: 0.05 ether}(
            address(creatorCore), 
            40, 
            1,
            aliceProof
        );

        // Mint with correct payment
        uint256 correctPayment = 0.1 ether + MINT_FEE_MERKLE;
        uint256 creatorBalanceBefore = creator.balance;
        
        extension.mintReserve{value: correctPayment}(
            address(creatorCore), 
            40, 
            1,
            aliceProof
        );

        // Verify payment was sent to creator
        assertEq(creator.balance - creatorBalanceBefore, 0.1 ether);
    }

    // ============ Edge Cases ============

    function test_claimExpired_reverts() public {
        // Initialize claim that will be expired
        vm.startPrank(creator);
        
        IERC1155SerendipityWithAllowlist.ClaimParameters memory params = IERC1155SerendipityWithAllowlist.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 100,
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + 1000),
            tokenVariations: 5,
            location: "test-location",
            paymentReceiver: payable(creator),
            cost: 0.01 ether,
            erc20: address(0),
            merkleRoot: merkleRoot,
            walletMax: 2
        });

        extension.initializeClaim(address(creatorCore), 50, params);
        vm.stopPrank();

        // Fast forward time to after the claim expires
        vm.warp(block.timestamp + 1001);

        vm.startPrank(alice);
        uint256 totalCost = (0.01 ether + MINT_FEE_MERKLE);
        
        vm.expectRevert(ISerendipity.ClaimInactive.selector);
        extension.mintReserve{value: totalCost}(
            address(creatorCore), 
            50, 
            1,
            aliceProof
        );
    }

    function test_claimNotStarted_reverts() public {
        // Initialize claim that hasn't started yet
        vm.startPrank(creator);
        
        IERC1155SerendipityWithAllowlist.ClaimParameters memory params = IERC1155SerendipityWithAllowlist.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 100,
            startDate: uint48(block.timestamp + 1000),
            endDate: uint48(block.timestamp + 2000),
            tokenVariations: 5,
            location: "test-location",
            paymentReceiver: payable(creator),
            cost: 0.01 ether,
            erc20: address(0),
            merkleRoot: merkleRoot,
            walletMax: 2
        });

        extension.initializeClaim(address(creatorCore), 51, params);
        vm.stopPrank();

        vm.startPrank(alice);
        uint256 totalCost = (0.01 ether + MINT_FEE_MERKLE);
        
        vm.expectRevert(ISerendipity.ClaimInactive.selector);
        extension.mintReserve{value: totalCost}(
            address(creatorCore), 
            51, 
            1,
            aliceProof
        );
    }

    function test_claimSoldOut_reverts() public {
        // Initialize claim with very limited supply
        vm.startPrank(creator);
        
        IERC1155SerendipityWithAllowlist.ClaimParameters memory params = IERC1155SerendipityWithAllowlist.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 1,
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + 1000),
            tokenVariations: 5,
            location: "test-location",
            paymentReceiver: payable(creator),
            cost: 0.01 ether,
            erc20: address(0),
            merkleRoot: merkleRoot,
            walletMax: 2
        });

        extension.initializeClaim(address(creatorCore), 52, params);
        vm.stopPrank();

        // Alice mints the only available token
        vm.startPrank(alice);
        uint256 totalCost = (0.01 ether + MINT_FEE_MERKLE);
        
        extension.mintReserve{value: totalCost}(
            address(creatorCore), 
            52, 
            1,
            aliceProof
        );
        vm.stopPrank();

        // Bob tries to mint but it's sold out
        vm.startPrank(bob);
        
        vm.expectRevert(ISerendipity.ClaimSoldOut.selector);
        extension.mintReserve{value: totalCost}(
            address(creatorCore), 
            52, 
            1,
            bobProof
        );
    }

    // ============ Interface Support Tests ============

    function test_supportsInterface() public {
        assertTrue(extension.supportsInterface(type(IERC1155SerendipityWithAllowlist).interfaceId));
        assertTrue(extension.supportsInterface(type(ISerendipity).interfaceId));
        assertTrue(extension.supportsInterface(type(IERC165).interfaceId));
    }

    // ============ Token URI Tests ============

    function test_tokenURI_generation() public {
        // Initialize claim
        vm.startPrank(creator);
        
        IERC1155SerendipityWithAllowlist.ClaimParameters memory params = IERC1155SerendipityWithAllowlist.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 100,
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + 1000),
            tokenVariations: 5,
            location: "arweave-hash-123",
            paymentReceiver: payable(creator),
            cost: 0,
            erc20: address(0),
            merkleRoot: bytes32(0),
            walletMax: 0
        });

        extension.initializeClaim(address(creatorCore), 60, params);

        IERC1155SerendipityWithAllowlist.Claim memory claim = extension.getClaim(address(creatorCore), 60);
        uint256 tokenId = claim.startingTokenId;

        string memory uri = extension.tokenURI(address(creatorCore), tokenId);
        assertEq(uri, "https://arweave.net/arweave-hash-123/1");
    }

    function test_updateTokenURIParams() public {
        // Initialize claim
        vm.startPrank(creator);
        
        IERC1155SerendipityWithAllowlist.ClaimParameters memory params = IERC1155SerendipityWithAllowlist.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 100,
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + 1000),
            tokenVariations: 5,
            location: "old-location",
            paymentReceiver: payable(creator),
            cost: 0,
            erc20: address(0),
            merkleRoot: bytes32(0),
            walletMax: 0
        });

        extension.initializeClaim(address(creatorCore), 61, params);

        // Update token URI params
        extension.updateTokenURIParams(
            address(creatorCore),
            61,
            ISerendipity.StorageProtocol.IPFS,
            "new-ipfs-location"
        );

        IERC1155SerendipityWithAllowlist.Claim memory claim = extension.getClaim(address(creatorCore), 61);
        uint256 tokenId = claim.startingTokenId;

        string memory uri = extension.tokenURI(address(creatorCore), tokenId);
        assertEq(uri, "ipfs://new-ipfs-location/1");
    }

    // ============ Admin Tests ============

    function test_deprecate_blocksNewClaims() public {
        vm.startPrank(owner);
        extension.deprecate(true);
        vm.stopPrank();

        vm.startPrank(creator);
        
        IERC1155SerendipityWithAllowlist.ClaimParameters memory params = IERC1155SerendipityWithAllowlist.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 100,
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + 1000),
            tokenVariations: 5,
            location: "test-location",
            paymentReceiver: payable(creator),
            cost: 0.01 ether,
            erc20: address(0),
            merkleRoot: merkleRoot,
            walletMax: 2
        });

        vm.expectRevert(ISerendipity.ContractDeprecated.selector);
        extension.initializeClaim(address(creatorCore), 70, params);
    }

    function test_withdraw_onlyAdmin() public {
        // Send some ETH to the contract
        vm.deal(address(extension), 1 ether);

        // Non-admin cannot withdraw
        vm.startPrank(unauthorized);
        vm.expectRevert();
        extension.withdraw(payable(unauthorized), 0.5 ether);
        vm.stopPrank();

        // Admin can withdraw
        vm.startPrank(owner);
        uint256 balanceBefore = owner.balance;
        extension.withdraw(payable(owner), 0.5 ether);
        assertEq(owner.balance - balanceBefore, 0.5 ether);
    }
}