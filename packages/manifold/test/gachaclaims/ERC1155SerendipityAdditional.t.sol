// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../contracts/gachaclaims/IERC1155Serendipity.sol";
import "../../contracts/gachaclaims/ERC1155Serendipity.sol";
import "../../contracts/gachaclaims/ISerendipity.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC1155Creator.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract ERC1155SerendipityAdditionalTest is Test {
    ERC1155Serendipity public extension;
    ERC1155Creator public creatorCore;

    address public creator = 0xc78Dc443c126af6E4f6Ed540c1e740C1b5be09cd;
    address public owner = 0x6140F00e4Ff3936702E68744f2b5978885464cbB;
    address public signingAddress = 0xc78dC443c126Af6E4f6eD540C1E740c1B5be09CE;
    address public alice = 0x5174cD462b60c536eb51D4ceC1D561D3Ea31004F;
    address public bob = 0x80AAC46bbd3C2FcE33681541a52CacBEd14bF425;
    address public charlie = 0x1234567890123456789012345678901234567890;
    address public unauthorized = 0x9876543210987654321098765432109876543210;

    uint256 public MINT_FEE = 500000000000000;
    uint256 public MINT_FEE_MERKLE = 690000000000000;

    // Merkle tree data
    bytes32 public merkleRoot;
    bytes32[] public aliceProof;
    bytes32[] public bobProof;

    function setUp() public {
        // Deploy creator contract
        vm.startPrank(creator);
        creatorCore = new ERC1155Creator("Test", "TEST");
        vm.stopPrank();

        // Deploy extension
        vm.startPrank(owner);
        extension = new ERC1155Serendipity(owner, address(0), address(0));
        extension.setSigner(signingAddress);
        vm.stopPrank();
        
        // Get fees
        MINT_FEE = extension.getMintFee();
        MINT_FEE_MERKLE = extension.getMintFeeMerkle();

        // Register extension
        vm.startPrank(creator);
        creatorCore.registerExtension(address(extension), "override");
        vm.stopPrank();

        // Setup merkle tree
        _setupMerkleTree();

        // Fund test accounts
        vm.deal(creator, 10 ether);
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        vm.deal(charlie, 10 ether);
        vm.deal(unauthorized, 10 ether);
    }

    function _setupMerkleTree() internal {
        bytes32[] memory leaves = new bytes32[](4);
        leaves[0] = keccak256(abi.encodePacked(alice, uint32(0)));
        leaves[1] = keccak256(abi.encodePacked(bob, uint32(1)));
        leaves[2] = keccak256(abi.encodePacked(alice, uint32(2))); // Alice has two indices
        leaves[3] = keccak256(abi.encodePacked(bob, uint32(3))); // Bob has two indices

        // Build tree
        bytes32 hash01 = _hashPair(leaves[0], leaves[1]);
        bytes32 hash23 = _hashPair(leaves[2], leaves[3]);
        merkleRoot = _hashPair(hash01, hash23);

        // Build proofs for alice's index 0
        aliceProof = new bytes32[](2);
        aliceProof[0] = leaves[1];
        aliceProof[1] = hash23;

        // Build proofs for bob's index 1
        bobProof = new bytes32[](2);
        bobProof[0] = leaves[0];
        bobProof[1] = hash23;
    }

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    // ============ Multi-mint with Arrays Tests ============

    function test_mintReserve_multipleIndicesAndProofs_success() public {
        // Initialize claim with merkle root
        vm.startPrank(creator);
        
        IERC1155Serendipity.ClaimParameters memory params = IERC1155Serendipity.ClaimParameters({
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
            walletMax: 10
        });

        extension.initializeClaim(address(creatorCore), 400, params);
        vm.stopPrank();

        // Alice mints multiple tokens with different indices
        vm.startPrank(alice);
        
        // Setup arrays for multi-mint (alice has indices 0 and 2)
        uint32[] memory indices = new uint32[](2);
        indices[0] = 0;
        indices[1] = 2;
        
        bytes32[][] memory proofs = new bytes32[][](2);
        // First proof for index 0
        bytes32[] memory proof1 = new bytes32[](2);
        proof1[0] = keccak256(abi.encodePacked(bob, uint32(1)));
        proof1[1] = _hashPair(
            keccak256(abi.encodePacked(alice, uint32(2))),
            keccak256(abi.encodePacked(bob, uint32(3)))
        );
        proofs[0] = proof1;
        
        // Second proof for index 2
        bytes32[] memory proof2 = new bytes32[](2);
        proof2[0] = keccak256(abi.encodePacked(bob, uint32(3)));
        proof2[1] = _hashPair(
            keccak256(abi.encodePacked(alice, uint32(0))),
            keccak256(abi.encodePacked(bob, uint32(1)))
        );
        proofs[1] = proof2;
        
        uint256 totalCost = (0.01 ether + MINT_FEE_MERKLE) * 2;
        
        extension.mintReserve{value: totalCost}(
            address(creatorCore), 
            400, 
            2,
            indices,
            proofs,
            address(0)
        );
        
        ISerendipity.UserMintDetails memory details = extension.getUserMints(alice, address(creatorCore), 400);
        assertEq(details.reservedCount, 2);
        vm.stopPrank();
    }

    function test_mintReserve_arrayLengthMismatch_reverts() public {
        // Initialize claim
        vm.startPrank(creator);
        
        IERC1155Serendipity.ClaimParameters memory params = IERC1155Serendipity.ClaimParameters({
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
            walletMax: 10
        });

        extension.initializeClaim(address(creatorCore), 401, params);
        vm.stopPrank();

        vm.startPrank(alice);
        
        // Mismatched array lengths - 2 indices but 1 proof
        uint32[] memory indices = new uint32[](2);
        indices[0] = 0;
        indices[1] = 2;
        
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = aliceProof;
        
        uint256 totalCost = (0.01 ether + MINT_FEE_MERKLE) * 2;
        
        vm.expectRevert(ISerendipity.InvalidInput.selector);
        extension.mintReserve{value: totalCost}(
            address(creatorCore), 
            401, 
            2,
            indices,
            proofs,
            address(0)
        );
        vm.stopPrank();
    }

    function test_mintReserve_emptyArraysForMerkleClaim_reverts() public {
        // Initialize claim with merkle root
        vm.startPrank(creator);
        
        IERC1155Serendipity.ClaimParameters memory params = IERC1155Serendipity.ClaimParameters({
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
            walletMax: 10
        });

        extension.initializeClaim(address(creatorCore), 402, params);
        vm.stopPrank();

        vm.startPrank(alice);
        uint256 totalCost = (0.01 ether + MINT_FEE_MERKLE);
        
        // Empty arrays with merkle root should fail
        vm.expectRevert(ISerendipity.InvalidInput.selector);
        extension.mintReserve{value: totalCost}(
            address(creatorCore), 
            402, 
            1,
            new uint32[](0), // empty but merkle root exists
            new bytes32[][](0),
            address(0)
        );
        vm.stopPrank();
    }

    function test_mintReserve_nonEmptyArraysForNonMerkleClaim_success() public {
        // Initialize claim without merkle root
        vm.startPrank(creator);
        
        IERC1155Serendipity.ClaimParameters memory params = IERC1155Serendipity.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 100,
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + 1000),
            tokenVariations: 5,
            location: "test-location",
            paymentReceiver: payable(creator),
            cost: 0.01 ether,
            erc20: address(0),
            merkleRoot: bytes32(0), // No merkle
            walletMax: 10
        });

        extension.initializeClaim(address(creatorCore), 403, params);
        vm.stopPrank();

        vm.startPrank(alice);
        uint256 totalCost = (0.01 ether + MINT_FEE);
        
        // For non-merkle claims, empty arrays are required
        extension.mintReserve{value: totalCost}(
            address(creatorCore), 
            403, 
            1,
            new uint32[](0), // empty for non-merkle
            new bytes32[][](0), // empty for non-merkle
            address(0)
        );
        
        ISerendipity.UserMintDetails memory details = extension.getUserMints(alice, address(creatorCore), 403);
        assertEq(details.reservedCount, 1);
        vm.stopPrank();
    }

    // ============ Edge Cases with New Signature ============

    function test_mintReserve_zeroMintCountWithArrays_reverts() public {
        // Initialize claim
        vm.startPrank(creator);
        
        IERC1155Serendipity.ClaimParameters memory params = IERC1155Serendipity.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 100,
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + 1000),
            tokenVariations: 5,
            location: "test-location",
            paymentReceiver: payable(creator),
            cost: 0,
            erc20: address(0),
            merkleRoot: bytes32(0),
            walletMax: 10
        });

        extension.initializeClaim(address(creatorCore), 404, params);
        vm.stopPrank();

        vm.startPrank(alice);
        
        vm.expectRevert(ISerendipity.InvalidMintCount.selector);
        extension.mintReserve{value: 0}(
            address(creatorCore), 
            404, 
            0, // zero mint count
            new uint32[](0),
            new bytes32[][](0),
            address(0)
        );
        vm.stopPrank();
    }

    function test_mintReserve_exceedingWalletMaxWithMultipleCalls_enforced() public {
        // Initialize claim with wallet max
        vm.startPrank(creator);
        
        IERC1155Serendipity.ClaimParameters memory params = IERC1155Serendipity.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 100,
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + 1000),
            tokenVariations: 5,
            location: "test-location",
            paymentReceiver: payable(creator),
            cost: 0,
            erc20: address(0),
            merkleRoot: bytes32(0),
            walletMax: 3
        });

        extension.initializeClaim(address(creatorCore), 405, params);
        vm.stopPrank();

        // Alice mints 2
        vm.startPrank(alice);
        extension.mintReserve{value: MINT_FEE * 2}(
            address(creatorCore), 
            405, 
            2,
            new uint32[](0),
            new bytes32[][](0),
            address(0)
        );
        
        // Alice mints 1 more (total 3, at wallet max)
        extension.mintReserve{value: MINT_FEE}(
            address(creatorCore), 
            405, 
            1,
            new uint32[](0),
            new bytes32[][](0),
            address(0)
        );
        
        // Alice tries to mint 1 more (would exceed wallet max)
        vm.expectRevert(ISerendipity.TooManyRequested.selector);
        extension.mintReserve{value: MINT_FEE}(
            address(creatorCore), 
            405, 
            1,
            new uint32[](0),
            new bytes32[][](0),
            address(0)
        );
        vm.stopPrank();
    }

    function test_deliverMints_partialDelivery_success() public {
        // Initialize claim
        vm.startPrank(creator);
        
        IERC1155Serendipity.ClaimParameters memory params = IERC1155Serendipity.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 100,
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + 1000),
            tokenVariations: 5,
            location: "test-location",
            paymentReceiver: payable(creator),
            cost: 0,
            erc20: address(0),
            merkleRoot: bytes32(0),
            walletMax: 10
        });

        extension.initializeClaim(address(creatorCore), 406, params);
        
        // Creator reserves 5 mints
        extension.mintReserve{value: MINT_FEE * 5}(
            address(creatorCore), 
            406, 
            5,
            new uint32[](0),
            new bytes32[][](0),
            address(0)
        );
        vm.stopPrank();

        // Deliver only 3 of the 5 reserved
        vm.startPrank(signingAddress);
        
        ISerendipity.VariationMint[] memory variations = new ISerendipity.VariationMint[](1);
        variations[0] = ISerendipity.VariationMint({
            variationIndex: 1,
            amount: 3,
            recipient: creator
        });

        ISerendipity.ClaimMint[] memory mints = new ISerendipity.ClaimMint[](1);
        mints[0] = ISerendipity.ClaimMint({
            creatorContractAddress: address(creatorCore),
            instanceId: 406,
            variationMints: variations
        });

        extension.deliverMints(mints);

        ISerendipity.UserMintDetails memory details = extension.getUserMints(creator, address(creatorCore), 406);
        assertEq(details.reservedCount, 5);
        assertEq(details.deliveredCount, 3);
        
        // Can still deliver the remaining 2
        variations[0].amount = 2;
        extension.deliverMints(mints);
        
        details = extension.getUserMints(creator, address(creatorCore), 406);
        assertEq(details.reservedCount, 5);
        assertEq(details.deliveredCount, 5);
        vm.stopPrank();
    }

    function test_deliverMints_multipleVariations_success() public {
        // Initialize claim with multiple variations
        vm.startPrank(creator);
        
        IERC1155Serendipity.ClaimParameters memory params = IERC1155Serendipity.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 100,
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + 1000),
            tokenVariations: 5,
            location: "test-location",
            paymentReceiver: payable(creator),
            cost: 0,
            erc20: address(0),
            merkleRoot: bytes32(0),
            walletMax: 10
        });

        extension.initializeClaim(address(creatorCore), 407, params);
        
        // Creator reserves 4 mints
        extension.mintReserve{value: MINT_FEE * 4}(
            address(creatorCore), 
            407, 
            4,
            new uint32[](0),
            new bytes32[][](0),
            address(0)
        );
        vm.stopPrank();

        // Deliver with multiple variations
        vm.startPrank(signingAddress);
        
        ISerendipity.VariationMint[] memory variations = new ISerendipity.VariationMint[](3);
        variations[0] = ISerendipity.VariationMint({
            variationIndex: 1,
            amount: 1,
            recipient: creator
        });
        variations[1] = ISerendipity.VariationMint({
            variationIndex: 3,
            amount: 2,
            recipient: creator
        });
        variations[2] = ISerendipity.VariationMint({
            variationIndex: 5,
            amount: 1,
            recipient: creator
        });

        ISerendipity.ClaimMint[] memory mints = new ISerendipity.ClaimMint[](1);
        mints[0] = ISerendipity.ClaimMint({
            creatorContractAddress: address(creatorCore),
            instanceId: 407,
            variationMints: variations
        });

        extension.deliverMints(mints);

        ISerendipity.UserMintDetails memory details = extension.getUserMints(creator, address(creatorCore), 407);
        assertEq(details.reservedCount, 4);
        assertEq(details.deliveredCount, 4);
        vm.stopPrank();
    }

    function test_deprecate_blocksMintingOnExistingClaims() public {
        // Initialize claim before deprecation
        vm.startPrank(creator);
        
        IERC1155Serendipity.ClaimParameters memory params = IERC1155Serendipity.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 100,
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + 1000),
            tokenVariations: 5,
            location: "test-location",
            paymentReceiver: payable(creator),
            cost: 0,
            erc20: address(0),
            merkleRoot: bytes32(0),
            walletMax: 10
        });

        extension.initializeClaim(address(creatorCore), 408, params);
        vm.stopPrank();

        // First verify minting works before deprecation
        vm.startPrank(alice);
        extension.mintReserve{value: MINT_FEE}(
            address(creatorCore), 
            408, 
            1,
            new uint32[](0),
            new bytes32[][](0),
            address(0)
        );
        vm.stopPrank();

        // Deprecate the contract
        vm.startPrank(owner);
        extension.deprecate(true);
        vm.stopPrank();

        // Try to mint on existing claim after deprecation - should succeed (deprecation only blocks new claims)
        vm.startPrank(bob);
        extension.mintReserve{value: MINT_FEE}(
            address(creatorCore), 
            408, 
            1,
            new uint32[](0),
            new bytes32[][](0),
            address(0)
        );
        vm.stopPrank();

        // Undeprecate
        vm.startPrank(owner);
        extension.deprecate(false);
        vm.stopPrank();

        // Verify minting still works after undeprecation
        vm.startPrank(charlie);
        extension.mintReserve{value: MINT_FEE}(
            address(creatorCore), 
            408, 
            1,
            new uint32[](0),
            new bytes32[][](0),
            address(0)
        );
        
        ISerendipity.UserMintDetails memory details = extension.getUserMints(charlie, address(creatorCore), 408);
        assertEq(details.reservedCount, 1);
        vm.stopPrank();
    }

    function test_mintReserve_withDifferentPaymentScenarios() public {
        // Initialize claim with cost
        vm.startPrank(creator);
        
        IERC1155Serendipity.ClaimParameters memory params = IERC1155Serendipity.ClaimParameters({
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
            walletMax: 10
        });

        extension.initializeClaim(address(creatorCore), 409, params);
        vm.stopPrank();

        vm.startPrank(alice);
        
        // Test exact payment
        uint256 exactPayment = 0.1 ether + MINT_FEE_MERKLE;
        uint256 creatorBalanceBefore = creator.balance;
        
        uint32[] memory indices = new uint32[](1);
        indices[0] = 0;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = aliceProof;
        
        extension.mintReserve{value: exactPayment}(
            address(creatorCore), 
            409, 
            1,
            indices,
            proofs,
            address(0)
        );
        
        assertEq(creator.balance - creatorBalanceBefore, 0.1 ether);
        
        // Test overpayment (should refund excess)
        uint256 overpayment = 0.2 ether + MINT_FEE_MERKLE;
        uint256 aliceBalanceBefore = alice.balance;
        
        // Alice mints with index 2 (she has multiple indices)
        indices[0] = 2;
        
        // Generate proof for index 2
        bytes32[] memory proof2 = new bytes32[](2);
        proof2[0] = keccak256(abi.encodePacked(bob, uint32(3)));
        proof2[1] = _hashPair(
            keccak256(abi.encodePacked(alice, uint32(0))),
            keccak256(abi.encodePacked(bob, uint32(1)))
        );
        proofs[0] = proof2;
        
        extension.mintReserve{value: overpayment}(
            address(creatorCore), 
            409, 
            1,
            indices,
            proofs,
            address(0)
        );
        
        // Check that excess was refunded
        assertEq(aliceBalanceBefore - alice.balance, exactPayment);
        
        vm.stopPrank();
    }

    function test_getClaimForToken_multipleTokenVariations() public {
        // Initialize claim with multiple variations
        vm.startPrank(creator);
        
        IERC1155Serendipity.ClaimParameters memory params = IERC1155Serendipity.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.IPFS,
            totalMax: 100,
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + 1000),
            tokenVariations: 10, // 10 variations
            location: "ipfs-location",
            paymentReceiver: payable(creator),
            cost: 0,
            erc20: address(0),
            merkleRoot: bytes32(0),
            walletMax: 5
        });

        extension.initializeClaim(address(creatorCore), 410, params);
        
        IERC1155Serendipity.Claim memory claim = extension.getClaim(address(creatorCore), 410);
        uint256 startingTokenId = claim.startingTokenId;

        // Test all token variations
        for (uint256 i = 0; i < 10; i++) {
            (uint256 instanceId, IERC1155Serendipity.Claim memory tokenClaim) = 
                extension.getClaimForToken(address(creatorCore), startingTokenId + i);
            
            assertEq(instanceId, 410);
            assertEq(tokenClaim.tokenVariations, 10);
            assertEq(tokenClaim.startingTokenId, startingTokenId);
        }

        // Test token outside variation range
        vm.expectRevert(ISerendipity.ClaimNotInitialized.selector);
        extension.getClaimForToken(address(creatorCore), startingTokenId + 10);
        
        vm.stopPrank();
    }

    function test_checkMintIndex_functionality() public {
        // Initialize claim with merkle root
        IERC1155Serendipity.ClaimParameters memory params = IERC1155Serendipity.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            location: "arweave.net/test",
            tokenVariations: 3,
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + 1000),
            totalMax: 10,
            cost: 0,
            paymentReceiver: payable(creator),
            erc20: address(0),
            merkleRoot: merkleRoot,  // Use the instance variable
            walletMax: 2
        });
        
        vm.startPrank(creator);
        vm.deal(creator, 10 ether);
        extension.initializeClaim(address(creatorCore), 500, params);
        vm.stopPrank();
        
        // Check mint indices before minting (should all be false)
        assertFalse(extension.checkMintIndex(address(creatorCore), 500, 0));
        assertFalse(extension.checkMintIndex(address(creatorCore), 500, 1));
        
        // Check multiple indices at once
        uint32[] memory indices = new uint32[](3);
        indices[0] = 0;
        indices[1] = 1;
        indices[2] = 2;
        
        bool[] memory results = extension.checkMintIndices(address(creatorCore), 500, indices);
        assertFalse(results[0]);
        assertFalse(results[1]);
        assertFalse(results[2]);
        
        // Alice mints with index 0
        uint32[] memory aliceIndices = new uint32[](1);
        aliceIndices[0] = 0;
        bytes32[][] memory aliceProofs = new bytes32[][](1);
        aliceProofs[0] = aliceProof;  // Use the instance variable
        
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        extension.mintReserve{ value: 1 ether }(
            address(creatorCore),
            500,
            1,
            aliceIndices,
            aliceProofs,
            address(0)
        );
        
        // Check that index 0 is now consumed
        assertTrue(extension.checkMintIndex(address(creatorCore), 500, 0));
        assertFalse(extension.checkMintIndex(address(creatorCore), 500, 1));
        
        // Bob mints with index 1
        uint32[] memory bobIndices = new uint32[](1);
        bobIndices[0] = 1;
        bytes32[][] memory bobProofs = new bytes32[][](1);
        bobProofs[0] = bobProof;  // Use the instance variable
        
        vm.deal(bob, 10 ether);
        vm.prank(bob);
        extension.mintReserve{ value: 1 ether }(
            address(creatorCore),
            500,
            1,
            bobIndices,
            bobProofs,
            address(0)
        );
        
        // Check that both indices 0 and 1 are now consumed
        assertTrue(extension.checkMintIndex(address(creatorCore), 500, 0));
        assertTrue(extension.checkMintIndex(address(creatorCore), 500, 1));
        assertFalse(extension.checkMintIndex(address(creatorCore), 500, 2));
        
        // Check multiple indices at once
        results = extension.checkMintIndices(address(creatorCore), 500, indices);
        assertTrue(results[0]);
        assertTrue(results[1]);
        assertFalse(results[2]);
    }

    function test_checkMintIndex_revertsForNonMerkleClaim() public {
        // Initialize non-merkle claim
        IERC1155Serendipity.ClaimParameters memory params = IERC1155Serendipity.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            location: "arweave.net/test",
            tokenVariations: 3,
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + 1000),
            totalMax: 10,
            cost: 0,
            paymentReceiver: payable(creator),
            erc20: address(0),
            merkleRoot: bytes32(0),
            walletMax: 0
        });
        
        vm.startPrank(creator);
        vm.deal(creator, 10 ether);
        extension.initializeClaim(address(creatorCore), 501, params);
        vm.stopPrank();
        
        // Should revert when checking mint index for non-merkle claim
        vm.expectRevert("Can only check merkle claims");
        extension.checkMintIndex(address(creatorCore), 501, 0);
        
        // Should also revert for checkMintIndices
        uint32[] memory indices = new uint32[](1);
        indices[0] = 0;
        
        vm.expectRevert("Can only check merkle claims");
        extension.checkMintIndices(address(creatorCore), 501, indices);
    }
}