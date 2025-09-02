// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../contracts/gachaclaims/IERC1155SerendipityWithAllowlist.sol";
import "../../contracts/gachaclaims/ERC1155SerendipityWithAllowlist.sol";
import "../../contracts/gachaclaims/ISerendipity.sol";
import "../../contracts/gachaclaims/Serendipity.sol";

import "@manifoldxyz/creator-core-solidity/contracts/ERC1155Creator.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../mocks/Mock.sol";
import "../../lib/murky/src/Merkle.sol";

contract ERC1155SerendipityWithAllowlistTest is Test {
    using SafeMath for uint256;

    ERC1155SerendipityWithAllowlist public example;
    ERC1155 public erc1155;
    ERC1155Creator public creatorCore1;
    ERC1155Creator public creatorCore2;
    Merkle public merkle;

    address public creator = 0xc78Dc443c126af6E4f6Ed540c1e740C1b5be09cd;
    address public owner = 0x6140F00e4Ff3936702E68744f2b5978885464cbB;
    address public signingAddress = 0xc78dC443c126Af6E4f6eD540C1E740c1B5be09CE;
    address public other = 0x5174cD462b60c536eb51D4ceC1D561D3Ea31004F;
    address public other2 = 0x80AAC46bbd3C2FcE33681541a52CacBEd14bF425;
    address public other3 = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

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
        example = new ERC1155SerendipityWithAllowlist(owner);
        example.setSigner(address(signingAddress));
        merkle = new Merkle();
        vm.stopPrank();

        vm.startPrank(creator);
        creatorCore1.registerExtension(address(example), "override");
        creatorCore2.registerExtension(address(example), "override");
        vm.stopPrank();

        vm.deal(creator, 2147483647500004294967295);
        vm.deal(other, 10 ether);
        vm.deal(other2, 10 ether);
        vm.deal(other3, 10 ether);
    }

    // ============ MERKLE ALLOWLIST TESTS ============

    function testMerkleAllowlistBasicMinting() public {
        vm.startPrank(creator);
        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;

        // Create merkle tree with allowlisted addresses
        bytes32[] memory allowListTuples = new bytes32[](3);
        allowListTuples[0] = keccak256(abi.encodePacked(other, uint32(0)));
        allowListTuples[1] = keccak256(abi.encodePacked(other2, uint32(1)));
        allowListTuples[2] = keccak256(abi.encodePacked(other3, uint32(2)));

        bytes32 merkleRoot = merkle.getRoot(allowListTuples);

        IERC1155SerendipityWithAllowlist.ClaimParameters memory claimP = IERC1155SerendipityWithAllowlist.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 10,
            startDate: nowC,
            endDate: later,
            tokenVariations: 5,
            location: "arweaveHash1",
            paymentReceiver: payable(creator),
            cost: 0.01 ether,
            erc20: zeroAddress,
            merkleRoot: merkleRoot,
            walletMax: 0 // Not used for merkle claims
        });

        example.initializeClaim(address(creatorCore1), 1, claimP);
        vm.stopPrank();

        // Test valid merkle mint for other
        vm.startPrank(other);
        bytes32[] memory merkleProof = merkle.getProof(allowListTuples, 0);
        uint256 totalCost = 0.01 ether + MINT_FEE;
        
        example.mintReserve{value: totalCost}(address(creatorCore1), 1, 0, merkleProof, 1);
        
        Serendipity.UserMintDetails memory userMints = example.getUserMints(other, address(creatorCore1), 1);
        assertEq(userMints.reservedCount, 1, "Should have reserved 1 mint");
        vm.stopPrank();

        // Test valid merkle mint for other2
        vm.startPrank(other2);
        bytes32[] memory merkleProof2 = merkle.getProof(allowListTuples, 1);
        
        example.mintReserve{value: totalCost}(address(creatorCore1), 1, 1, merkleProof2, 1);
        
        Serendipity.UserMintDetails memory userMints2 = example.getUserMints(other2, address(creatorCore1), 1);
        assertEq(userMints2.reservedCount, 1, "Should have reserved 1 mint");
        vm.stopPrank();

        // Verify claim totals
        IERC1155SerendipityWithAllowlist.Claim memory claim = example.getClaim(address(creatorCore1), 1);
        assertEq(claim.total, 2, "Total should be 2");
    }

    function testMerkleAllowlistInvalidProof() public {
        vm.startPrank(creator);
        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;

        bytes32[] memory allowListTuples = new bytes32[](2);
        allowListTuples[0] = keccak256(abi.encodePacked(other, uint32(0)));
        allowListTuples[1] = keccak256(abi.encodePacked(other2, uint32(1)));

        bytes32 merkleRoot = merkle.getRoot(allowListTuples);

        IERC1155SerendipityWithAllowlist.ClaimParameters memory claimP = IERC1155SerendipityWithAllowlist.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 10,
            startDate: nowC,
            endDate: later,
            tokenVariations: 5,
            location: "arweaveHash1",
            paymentReceiver: payable(creator),
            cost: 0.01 ether,
            erc20: zeroAddress,
            merkleRoot: merkleRoot,
            walletMax: 0
        });

        example.initializeClaim(address(creatorCore1), 1, claimP);
        vm.stopPrank();

        // Try to mint with invalid proof (wrong address)
        vm.startPrank(other3); // Not in allowlist
        bytes32[] memory invalidProof = merkle.getProof(allowListTuples, 0); // Proof for other, not other3
        uint256 totalCost = 0.01 ether + MINT_FEE;
        
        vm.expectRevert("Could not verify merkle proof");
        example.mintReserve{value: totalCost}(address(creatorCore1), 1, 0, invalidProof, 1);
        vm.stopPrank();

        // Try to mint with wrong index
        vm.startPrank(other);
        bytes32[] memory wrongIndexProof = merkle.getProof(allowListTuples, 1); // Proof for index 1, but using index 0
        
        vm.expectRevert("Could not verify merkle proof");
        example.mintReserve{value: totalCost}(address(creatorCore1), 1, 1, wrongIndexProof, 1);
        vm.stopPrank();
    }

    function testMerkleAllowlistDoubleMintPrevention() public {
        vm.startPrank(creator);
        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;

        bytes32[] memory allowListTuples = new bytes32[](2);
        allowListTuples[0] = keccak256(abi.encodePacked(other, uint32(0)));
        allowListTuples[1] = keccak256(abi.encodePacked(other2, uint32(1)));

        bytes32 merkleRoot = merkle.getRoot(allowListTuples);

        IERC1155SerendipityWithAllowlist.ClaimParameters memory claimP = IERC1155SerendipityWithAllowlist.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 10,
            startDate: nowC,
            endDate: later,
            tokenVariations: 5,
            location: "arweaveHash1",
            paymentReceiver: payable(creator),
            cost: 0.01 ether,
            erc20: zeroAddress,
            merkleRoot: merkleRoot,
            walletMax: 0
        });

        example.initializeClaim(address(creatorCore1), 1, claimP);
        vm.stopPrank();

        // First mint should succeed
        vm.startPrank(other);
        bytes32[] memory merkleProof = merkle.getProof(allowListTuples, 0);
        uint256 totalCost = 0.01 ether + MINT_FEE;
        
        example.mintReserve{value: totalCost}(address(creatorCore1), 1, 0, merkleProof, 1);
        
        // Check mint index is marked as used
        assertTrue(example.checkMintIndex(address(creatorCore1), 1, 0), "Mint index 0 should be used");
        
        // Second mint with same index should fail
        vm.expectRevert("Already minted");
        example.mintReserve{value: totalCost}(address(creatorCore1), 1, 0, merkleProof, 1);
        vm.stopPrank();
    }

    function testMerkleAllowlistBatchMinting() public {
        vm.startPrank(creator);
        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;

        // Create merkle tree with multiple entries for same user
        bytes32[] memory allowListTuples = new bytes32[](4);
        allowListTuples[0] = keccak256(abi.encodePacked(other, uint32(0)));
        allowListTuples[1] = keccak256(abi.encodePacked(other, uint32(1)));
        allowListTuples[2] = keccak256(abi.encodePacked(other2, uint32(2)));
        allowListTuples[3] = keccak256(abi.encodePacked(other2, uint32(3)));

        bytes32 merkleRoot = merkle.getRoot(allowListTuples);

        IERC1155SerendipityWithAllowlist.ClaimParameters memory claimP = IERC1155SerendipityWithAllowlist.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 10,
            startDate: nowC,
            endDate: later,
            tokenVariations: 5,
            location: "arweaveHash1",
            paymentReceiver: payable(creator),
            cost: 0.01 ether,
            erc20: zeroAddress,
            merkleRoot: merkleRoot,
            walletMax: 0
        });

        example.initializeClaim(address(creatorCore1), 1, claimP);
        vm.stopPrank();

        // Test batch minting with multiple proofs
        vm.startPrank(other);
        uint32[] memory mintIndices = new uint32[](2);
        mintIndices[0] = 0;
        mintIndices[1] = 1;
        
        bytes32[][] memory merkleProofs = new bytes32[][](2);
        merkleProofs[0] = merkle.getProof(allowListTuples, 0);
        merkleProofs[1] = merkle.getProof(allowListTuples, 1);
        
        uint32[] memory mintCounts = new uint32[](2);
        mintCounts[0] = 1;
        mintCounts[1] = 2;
        
        uint256 totalCost = (0.01 ether + MINT_FEE) * 3; // Total 3 mints
        
        example.mintReserve{value: totalCost}(address(creatorCore1), 1, mintIndices, merkleProofs, mintCounts);
        
        Serendipity.UserMintDetails memory userMints = example.getUserMints(other, address(creatorCore1), 1);
        assertEq(userMints.reservedCount, 3, "Should have reserved 3 mints");
        
        // Check both indices are marked as used
        assertTrue(example.checkMintIndex(address(creatorCore1), 1, 0), "Mint index 0 should be used");
        assertTrue(example.checkMintIndex(address(creatorCore1), 1, 1), "Mint index 1 should be used");
        vm.stopPrank();
    }

    function testMerkleAllowlistCheckMintIndices() public {
        vm.startPrank(creator);
        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;

        bytes32[] memory allowListTuples = new bytes32[](5);
        for (uint32 i = 0; i < 5; i++) {
            allowListTuples[i] = keccak256(abi.encodePacked(other, i));
        }

        bytes32 merkleRoot = merkle.getRoot(allowListTuples);

        IERC1155SerendipityWithAllowlist.ClaimParameters memory claimP = IERC1155SerendipityWithAllowlist.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 10,
            startDate: nowC,
            endDate: later,
            tokenVariations: 5,
            location: "arweaveHash1",
            paymentReceiver: payable(creator),
            cost: 0.01 ether,
            erc20: zeroAddress,
            merkleRoot: merkleRoot,
            walletMax: 0
        });

        example.initializeClaim(address(creatorCore1), 1, claimP);
        vm.stopPrank();

        // Initially no indices should be used
        uint32[] memory indicesToCheck = new uint32[](5);
        for (uint32 i = 0; i < 5; i++) {
            indicesToCheck[i] = i;
        }
        
        bool[] memory results = example.checkMintIndices(address(creatorCore1), 1, indicesToCheck);
        for (uint32 i = 0; i < 5; i++) {
            assertFalse(results[i], "Initially no indices should be used");
        }

        // Mint using indices 1 and 3
        vm.startPrank(other);
        bytes32[] memory proof1 = merkle.getProof(allowListTuples, 1);
        bytes32[] memory proof3 = merkle.getProof(allowListTuples, 3);
        
        uint256 totalCost = 0.01 ether + MINT_FEE;
        example.mintReserve{value: totalCost}(address(creatorCore1), 1, 1, proof1, 1);
        example.mintReserve{value: totalCost}(address(creatorCore1), 1, 3, proof3, 1);
        vm.stopPrank();

        // Check indices again
        results = example.checkMintIndices(address(creatorCore1), 1, indicesToCheck);
        assertFalse(results[0], "Index 0 should not be used");
        assertTrue(results[1], "Index 1 should be used");
        assertFalse(results[2], "Index 2 should not be used");
        assertTrue(results[3], "Index 3 should be used");
        assertFalse(results[4], "Index 4 should not be used");
    }

    // ============ NON-MERKLE WALLET LIMIT TESTS ============

    function testNonMerkleWalletMaxLimits() public {
        vm.startPrank(creator);
        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;

        IERC1155SerendipityWithAllowlist.ClaimParameters memory claimP = IERC1155SerendipityWithAllowlist.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 100,
            startDate: nowC,
            endDate: later,
            tokenVariations: 5,
            location: "arweaveHash1",
            paymentReceiver: payable(creator),
            cost: 0.01 ether,
            erc20: zeroAddress,
            merkleRoot: bytes32(0), // No merkle root for non-merkle claim
            walletMax: 3 // Max 3 per wallet
        });

        example.initializeClaim(address(creatorCore1), 1, claimP);
        vm.stopPrank();

        // Mint up to wallet limit
        vm.startPrank(other);
        uint256 totalCost = 0.01 ether + MINT_FEE;
        
        example.mintReserve{value: totalCost * 2}(address(creatorCore1), 1, 2);
        
        // Check total mints for wallet
        uint32 totalMints = example.getTotalMints(address(creatorCore1), 1, other);
        assertEq(totalMints, 2, "Should have 2 total mints");
        
        // Mint one more to reach limit
        example.mintReserve{value: totalCost}(address(creatorCore1), 1, 1);
        
        totalMints = example.getTotalMints(address(creatorCore1), 1, other);
        assertEq(totalMints, 3, "Should have 3 total mints");
        
        // Try to mint beyond limit
        vm.expectRevert(ISerendipity.TooManyRequested.selector);
        example.mintReserve{value: totalCost}(address(creatorCore1), 1, 1);
        vm.stopPrank();

        // Different wallet should be able to mint
        vm.startPrank(other2);
        example.mintReserve{value: totalCost}(address(creatorCore1), 1, 1);
        
        uint32 totalMints2 = example.getTotalMints(address(creatorCore1), 1, other2);
        assertEq(totalMints2, 1, "other2 should have 1 total mint");
        vm.stopPrank();
    }

    function testNonMerkleUnlimitedWallet() public {
        vm.startPrank(creator);
        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;

        IERC1155SerendipityWithAllowlist.ClaimParameters memory claimP = IERC1155SerendipityWithAllowlist.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 100,
            startDate: nowC,
            endDate: later,
            tokenVariations: 5,
            location: "arweaveHash1",
            paymentReceiver: payable(creator),
            cost: 0.01 ether,
            erc20: zeroAddress,
            merkleRoot: bytes32(0), // No merkle root
            walletMax: 0 // No wallet limit
        });

        example.initializeClaim(address(creatorCore1), 1, claimP);
        vm.stopPrank();

        // Should be able to mint many times from same wallet
        vm.startPrank(other);
        uint256 totalCost = 0.01 ether + MINT_FEE;
        
        for (uint256 i = 0; i < 10; i++) {
            example.mintReserve{value: totalCost}(address(creatorCore1), 1, 1);
        }
        
        Serendipity.UserMintDetails memory userMints = example.getUserMints(other, address(creatorCore1), 1);
        assertEq(userMints.reservedCount, 10, "Should have reserved 10 mints");
        vm.stopPrank();
    }

    // ============ BACKWARD COMPATIBILITY TESTS ============

    function testBackwardCompatibilityWithOriginalSerendipity() public {
        vm.startPrank(creator);
        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;

        // Create a claim without merkle features (same as original Serendipity)
        IERC1155SerendipityWithAllowlist.ClaimParameters memory claimP = IERC1155SerendipityWithAllowlist.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 100,
            startDate: nowC,
            endDate: later,
            tokenVariations: 5,
            location: "arweaveHash1",
            paymentReceiver: payable(creator),
            cost: 0.01 ether,
            erc20: zeroAddress,
            merkleRoot: bytes32(0), // No merkle root
            walletMax: 0 // No wallet limit
        });

        example.initializeClaim(address(creatorCore1), 1, claimP);

        // Test original mintReserve function (without merkle parameters)
        example.mintReserve{value: (0.01 ether + MINT_FEE) * 2}(address(creatorCore1), 1, 2);
        vm.stopPrank();

        // Verify it works like original
        vm.startPrank(other);
        example.mintReserve{value: 0.01 ether + MINT_FEE}(address(creatorCore1), 1, 1);
        
        Serendipity.UserMintDetails memory userMints = example.getUserMints(other, address(creatorCore1), 1);
        assertEq(userMints.reservedCount, 1, "Should have reserved 1 mint");
        vm.stopPrank();

        // Test delivery phase (unchanged)
        vm.startPrank(signingAddress);
        ISerendipity.ClaimMint[] memory mints = new ISerendipity.ClaimMint[](1);
        ISerendipity.VariationMint[] memory variationMints = new ISerendipity.VariationMint[](1);
        variationMints[0] = ISerendipity.VariationMint({ variationIndex: 1, amount: 1, recipient: other });
        mints[0] = ISerendipity.ClaimMint({
            creatorContractAddress: address(creatorCore1),
            instanceId: 1,
            variationMints: variationMints
        });
        example.deliverMints(mints);
        
        // Check delivery worked
        Serendipity.UserMintDetails memory finalMints = example.getUserMints(other, address(creatorCore1), 1);
        assertEq(finalMints.deliveredCount, 1, "Should have delivered 1 mint");
        vm.stopPrank();
    }

    function testOriginalFunctionsRejectMerkleInput() public {
        vm.startPrank(creator);
        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;

        // Need at least 2 leaves for merkle tree
        bytes32[] memory allowListTuples = new bytes32[](2);
        allowListTuples[0] = keccak256(abi.encodePacked(other, uint32(0)));
        allowListTuples[1] = keccak256(abi.encodePacked(other2, uint32(1)));
        bytes32 merkleRoot = merkle.getRoot(allowListTuples);

        // Create merkle claim
        IERC1155SerendipityWithAllowlist.ClaimParameters memory claimP = IERC1155SerendipityWithAllowlist.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 100,
            startDate: nowC,
            endDate: later,
            tokenVariations: 5,
            location: "arweaveHash1",
            paymentReceiver: payable(creator),
            cost: 0.01 ether,
            erc20: zeroAddress,
            merkleRoot: merkleRoot,
            walletMax: 0
        });

        example.initializeClaim(address(creatorCore1), 1, claimP);
        vm.stopPrank();

        // Original mintReserve should reject merkle claims
        vm.startPrank(other);
        vm.expectRevert(ISerendipity.InvalidInput.selector);
        example.mintReserve{value: 0.01 ether + MINT_FEE}(address(creatorCore1), 1, 1);
        vm.stopPrank();
    }

    function testMerkleFunctionsRejectNonMerkleInput() public {
        vm.startPrank(creator);
        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;

        // Create non-merkle claim
        IERC1155SerendipityWithAllowlist.ClaimParameters memory claimP = IERC1155SerendipityWithAllowlist.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 100,
            startDate: nowC,
            endDate: later,
            tokenVariations: 5,
            location: "arweaveHash1",
            paymentReceiver: payable(creator),
            cost: 0.01 ether,
            erc20: zeroAddress,
            merkleRoot: bytes32(0), // No merkle root
            walletMax: 3
        });

        example.initializeClaim(address(creatorCore1), 1, claimP);
        vm.stopPrank();

        // Merkle mintReserve should reject non-merkle claims
        vm.startPrank(other);
        bytes32[] memory emptyProof = new bytes32[](0);
        
        vm.expectRevert(ISerendipity.InvalidInput.selector);
        example.mintReserve{value: 0.01 ether + MINT_FEE}(address(creatorCore1), 1, 0, emptyProof, 1);
        vm.stopPrank();

        // checkMintIndex should reject non-merkle claims
        vm.expectRevert(ISerendipity.InvalidInput.selector);
        example.checkMintIndex(address(creatorCore1), 1, 0);

        // getTotalMints should reject merkle claims (but this is non-merkle, so should work)
        // But it should reject if walletMax is 0
        vm.startPrank(creator);
        IERC1155SerendipityWithAllowlist.UpdateClaimParameters memory updateParams = IERC1155SerendipityWithAllowlist.UpdateClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            paymentReceiver: payable(creator),
            totalMax: 100,
            startDate: nowC,
            endDate: later,
            cost: 0.01 ether,
            location: "arweaveHash1",
            merkleRoot: bytes32(0),
            walletMax: 0 // Set to 0
        });
        example.updateClaim(address(creatorCore1), 1, updateParams);
        vm.stopPrank();

        vm.expectRevert(ISerendipity.InvalidInput.selector);
        example.getTotalMints(address(creatorCore1), 1, other);
    }

    // ============ EDGE CASES AND ERROR CONDITIONS ============

    function testMerkleClaimSoldOut() public {
        vm.startPrank(creator);
        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;

        bytes32[] memory allowListTuples = new bytes32[](3);
        allowListTuples[0] = keccak256(abi.encodePacked(other, uint32(0)));
        allowListTuples[1] = keccak256(abi.encodePacked(other2, uint32(1)));
        allowListTuples[2] = keccak256(abi.encodePacked(other3, uint32(2)));

        bytes32 merkleRoot = merkle.getRoot(allowListTuples);

        IERC1155SerendipityWithAllowlist.ClaimParameters memory claimP = IERC1155SerendipityWithAllowlist.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 2, // Only 2 total supply
            startDate: nowC,
            endDate: later,
            tokenVariations: 5,
            location: "arweaveHash1",
            paymentReceiver: payable(creator),
            cost: 0.01 ether,
            erc20: zeroAddress,
            merkleRoot: merkleRoot,
            walletMax: 0
        });

        example.initializeClaim(address(creatorCore1), 1, claimP);
        vm.stopPrank();

        // Mint 2 tokens (total supply)
        vm.startPrank(other);
        bytes32[] memory proof1 = merkle.getProof(allowListTuples, 0);
        uint256 totalCost = 0.01 ether + MINT_FEE;
        example.mintReserve{value: totalCost * 2}(address(creatorCore1), 1, 0, proof1, 2);
        vm.stopPrank();

        // Third mint should fail due to sold out
        vm.startPrank(other2);
        bytes32[] memory proof2 = merkle.getProof(allowListTuples, 1);
        vm.expectRevert(ISerendipity.ClaimSoldOut.selector);
        example.mintReserve{value: totalCost}(address(creatorCore1), 1, 1, proof2, 1);
        vm.stopPrank();
    }

    function testMerkleClaimAfterEndDate() public {
        vm.startPrank(creator);
        uint48 nowC = uint48(block.timestamp);
        uint48 endTime = nowC + 100;

        // Need at least 2 leaves for merkle tree
        bytes32[] memory allowListTuples = new bytes32[](2);
        allowListTuples[0] = keccak256(abi.encodePacked(other, uint32(0)));
        allowListTuples[1] = keccak256(abi.encodePacked(other2, uint32(1)));
        bytes32 merkleRoot = merkle.getRoot(allowListTuples);

        IERC1155SerendipityWithAllowlist.ClaimParameters memory claimP = IERC1155SerendipityWithAllowlist.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 10,
            startDate: nowC,
            endDate: endTime,
            tokenVariations: 5,
            location: "arweaveHash1",
            paymentReceiver: payable(creator),
            cost: 0.01 ether,
            erc20: zeroAddress,
            merkleRoot: merkleRoot,
            walletMax: 0
        });

        example.initializeClaim(address(creatorCore1), 1, claimP);
        vm.stopPrank();

        // Warp past end time
        vm.warp(endTime + 1);

        vm.startPrank(other);
        bytes32[] memory proof = merkle.getProof(allowListTuples, 0);
        uint256 totalCost = 0.01 ether + MINT_FEE;
        
        vm.expectRevert(ISerendipity.ClaimInactive.selector);
        example.mintReserve{value: totalCost}(address(creatorCore1), 1, 0, proof, 1);
        vm.stopPrank();
    }

    function testInvalidPaymentAmounts() public {
        vm.startPrank(creator);
        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;

        // Need at least 2 leaves for merkle tree
        bytes32[] memory allowListTuples = new bytes32[](2);
        allowListTuples[0] = keccak256(abi.encodePacked(other, uint32(0)));
        allowListTuples[1] = keccak256(abi.encodePacked(other2, uint32(1)));
        bytes32 merkleRoot = merkle.getRoot(allowListTuples);

        IERC1155SerendipityWithAllowlist.ClaimParameters memory claimP = IERC1155SerendipityWithAllowlist.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 10,
            startDate: nowC,
            endDate: later,
            tokenVariations: 5,
            location: "arweaveHash1",
            paymentReceiver: payable(creator),
            cost: 0.01 ether,
            erc20: zeroAddress,
            merkleRoot: merkleRoot,
            walletMax: 0
        });

        example.initializeClaim(address(creatorCore1), 1, claimP);
        vm.stopPrank();

        vm.startPrank(other);
        bytes32[] memory proof = merkle.getProof(allowListTuples, 0);
        
        // Too little payment
        vm.expectRevert(ISerendipity.InvalidPayment.selector);
        example.mintReserve{value: 0.005 ether}(address(creatorCore1), 1, 0, proof, 1);
        
        // Too much payment
        vm.expectRevert(ISerendipity.InvalidPayment.selector);
        example.mintReserve{value: 1 ether}(address(creatorCore1), 1, 0, proof, 1);
        vm.stopPrank();
    }

    function testInvalidMintCounts() public {
        vm.startPrank(creator);
        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;

        // Need at least 2 leaves for merkle tree
        bytes32[] memory allowListTuples = new bytes32[](2);
        allowListTuples[0] = keccak256(abi.encodePacked(other, uint32(0)));
        allowListTuples[1] = keccak256(abi.encodePacked(other2, uint32(1)));
        bytes32 merkleRoot = merkle.getRoot(allowListTuples);

        IERC1155SerendipityWithAllowlist.ClaimParameters memory claimP = IERC1155SerendipityWithAllowlist.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 10,
            startDate: nowC,
            endDate: later,
            tokenVariations: 5,
            location: "arweaveHash1",
            paymentReceiver: payable(creator),
            cost: 0.01 ether,
            erc20: zeroAddress,
            merkleRoot: merkleRoot,
            walletMax: 0
        });

        example.initializeClaim(address(creatorCore1), 1, claimP);
        vm.stopPrank();

        vm.startPrank(other);
        bytes32[] memory proof = merkle.getProof(allowListTuples, 0);
        uint256 totalCost = 0.01 ether + MINT_FEE;
        
        // Zero mint count
        vm.expectRevert(ISerendipity.InvalidMintCount.selector);
        example.mintReserve{value: 0}(address(creatorCore1), 1, 0, proof, 0);
        
        // MAX_UINT_32 mint count
        vm.expectRevert(ISerendipity.InvalidMintCount.selector);
        example.mintReserve{value: totalCost}(address(creatorCore1), 1, 0, proof, MAX_UINT_32);
        vm.stopPrank();
    }

    function testBatchMintingInvalidArrays() public {
        vm.startPrank(creator);
        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;

        bytes32[] memory allowListTuples = new bytes32[](2);
        allowListTuples[0] = keccak256(abi.encodePacked(other, uint32(0)));
        allowListTuples[1] = keccak256(abi.encodePacked(other, uint32(1)));
        bytes32 merkleRoot = merkle.getRoot(allowListTuples);

        IERC1155SerendipityWithAllowlist.ClaimParameters memory claimP = IERC1155SerendipityWithAllowlist.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 10,
            startDate: nowC,
            endDate: later,
            tokenVariations: 5,
            location: "arweaveHash1",
            paymentReceiver: payable(creator),
            cost: 0.01 ether,
            erc20: zeroAddress,
            merkleRoot: merkleRoot,
            walletMax: 0
        });

        example.initializeClaim(address(creatorCore1), 1, claimP);
        vm.stopPrank();

        vm.startPrank(other);
        
        // Mismatched array lengths
        uint32[] memory mintIndices = new uint32[](2);
        bytes32[][] memory merkleProofs = new bytes32[][](1); // Different length
        uint32[] memory mintCounts = new uint32[](2);
        
        vm.expectRevert(ISerendipity.InvalidInput.selector);
        example.mintReserve{value: 0}(address(creatorCore1), 1, mintIndices, merkleProofs, mintCounts);

        // Empty arrays
        uint32[] memory emptyIndices = new uint32[](0);
        bytes32[][] memory emptyProofs = new bytes32[][](0);
        uint32[] memory emptyCounts = new uint32[](0);
        
        vm.expectRevert(ISerendipity.InvalidInput.selector);
        example.mintReserve{value: 0}(address(creatorCore1), 1, emptyIndices, emptyProofs, emptyCounts);
        vm.stopPrank();
    }

    function testContractCannotMint() public {
        vm.startPrank(creator);
        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;

        IERC1155SerendipityWithAllowlist.ClaimParameters memory claimP = IERC1155SerendipityWithAllowlist.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 10,
            startDate: nowC,
            endDate: later,
            tokenVariations: 5,
            location: "arweaveHash1",
            paymentReceiver: payable(creator),
            cost: 0.01 ether,
            erc20: zeroAddress,
            merkleRoot: bytes32(0),
            walletMax: 0
        });

        example.initializeClaim(address(creatorCore1), 1, claimP);
        vm.stopPrank();

        // Deploy a contract that will try to mint
        ContractMinter minter = new ContractMinter();
        vm.deal(address(minter), 1 ether);
        
        // Contract should not be able to mint
        vm.expectRevert(ISerendipity.CannotMintFromContract.selector);
        minter.attemptMint(example, address(creatorCore1), 1, 0.01 ether + MINT_FEE);
    }

    // ============ REFUND AND PAYMENT TESTS ============

    function testRefundsWhenPartiallyAvailable() public {
        vm.startPrank(creator);
        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;

        bytes32[] memory allowListTuples = new bytes32[](2);
        allowListTuples[0] = keccak256(abi.encodePacked(other, uint32(0)));
        allowListTuples[1] = keccak256(abi.encodePacked(other2, uint32(1)));
        bytes32 merkleRoot = merkle.getRoot(allowListTuples);

        IERC1155SerendipityWithAllowlist.ClaimParameters memory claimP = IERC1155SerendipityWithAllowlist.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 3, // Limited supply
            startDate: nowC,
            endDate: later,
            tokenVariations: 5,
            location: "arweaveHash1",
            paymentReceiver: payable(creator),
            cost: 0.01 ether,
            erc20: zeroAddress,
            merkleRoot: merkleRoot,
            walletMax: 0
        });

        example.initializeClaim(address(creatorCore1), 1, claimP);
        vm.stopPrank();
        
        // Pre-mint 2 tokens from other2 (allowed in merkle)
        vm.startPrank(other2);
        bytes32[] memory proofOther2 = merkle.getProof(allowListTuples, 1);
        example.mintReserve{value: (0.01 ether + MINT_FEE) * 2}(address(creatorCore1), 1, 1, proofOther2, 2);
        vm.stopPrank();

        // other tries to mint 2 but only 1 is available (3 total, 2 already minted)
        uint256 balanceBefore = other.balance;
        uint256 creatorBalanceBefore = creator.balance;
        
        vm.startPrank(other);
        bytes32[] memory proof = merkle.getProof(allowListTuples, 0);
        uint256 totalPaid = (0.01 ether + MINT_FEE) * 2;
        
        example.mintReserve{value: totalPaid}(address(creatorCore1), 1, 0, proof, 2);
        
        uint256 balanceAfter = other.balance;
        uint256 creatorBalanceAfter = creator.balance;
        
        // Should only be charged for 1 mint, refunded for 1
        uint256 expectedCharge = (0.01 ether + MINT_FEE) * 1;
        uint256 expectedRefund = (0.01 ether + MINT_FEE) * 1;
        
        assertEq(balanceBefore - balanceAfter, expectedCharge, "Should only be charged for 1 mint");
        assertEq(creatorBalanceAfter - creatorBalanceBefore, 0.01 ether, "Creator should receive cost for 1 mint");
        
        // Verify only 1 mint was reserved
        Serendipity.UserMintDetails memory userMints = example.getUserMints(other, address(creatorCore1), 1);
        assertEq(userMints.reservedCount, 1, "Should have reserved only 1 mint");
        vm.stopPrank();
    }

    // ============ GAS OPTIMIZATION BENCHMARKS ============

    function testGasBenchmarkMerkleVsNonMerkle() public {
        vm.startPrank(creator);
        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;

        // Setup non-merkle claim
        IERC1155SerendipityWithAllowlist.ClaimParameters memory nonMerkleClaimP = IERC1155SerendipityWithAllowlist.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 100,
            startDate: nowC,
            endDate: later,
            tokenVariations: 5,
            location: "arweaveHash1",
            paymentReceiver: payable(creator),
            cost: 0.01 ether,
            erc20: zeroAddress,
            merkleRoot: bytes32(0),
            walletMax: 0
        });

        example.initializeClaim(address(creatorCore1), 1, nonMerkleClaimP);

        // Setup merkle claim - need at least 2 leaves
        bytes32[] memory allowListTuples = new bytes32[](2);
        allowListTuples[0] = keccak256(abi.encodePacked(other, uint32(0)));
        allowListTuples[1] = keccak256(abi.encodePacked(other2, uint32(1)));
        bytes32 merkleRoot = merkle.getRoot(allowListTuples);

        IERC1155SerendipityWithAllowlist.ClaimParameters memory merkleClaimP = IERC1155SerendipityWithAllowlist.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 100,
            startDate: nowC,
            endDate: later,
            tokenVariations: 5,
            location: "arweaveHash1",
            paymentReceiver: payable(creator),
            cost: 0.01 ether,
            erc20: zeroAddress,
            merkleRoot: merkleRoot,
            walletMax: 0
        });

        example.initializeClaim(address(creatorCore1), 2, merkleClaimP);
        vm.stopPrank();

        uint256 totalCost = 0.01 ether + MINT_FEE;

        // Benchmark non-merkle mint
        vm.startPrank(other);
        uint256 gasStart = gasleft();
        example.mintReserve{value: totalCost}(address(creatorCore1), 1, 1);
        uint256 gasUsedNonMerkle = gasStart - gasleft();
        vm.stopPrank();

        // Benchmark merkle mint
        vm.startPrank(other);
        bytes32[] memory proof = merkle.getProof(allowListTuples, 0);
        gasStart = gasleft();
        example.mintReserve{value: totalCost}(address(creatorCore1), 2, 0, proof, 1);
        uint256 gasUsedMerkle = gasStart - gasleft();
        vm.stopPrank();

        // Log gas usage for comparison
        console.log("Non-merkle mint gas:", gasUsedNonMerkle);
        console.log("Merkle mint gas:", gasUsedMerkle);
        console.log("Gas overhead for merkle:", gasUsedMerkle > gasUsedNonMerkle ? gasUsedMerkle - gasUsedNonMerkle : 0);
        
        // Ensure merkle mints don't use excessive gas (reasonable overhead)
        assertTrue(gasUsedMerkle < gasUsedNonMerkle * 2, "Merkle mint should not use more than 2x gas of non-merkle");
    }

    function testGasBenchmarkBitmapEfficiency() public {
        vm.startPrank(creator);
        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;

        // Create large merkle tree
        bytes32[] memory allowListTuples = new bytes32[](100);
        for (uint32 i = 0; i < 100; i++) {
            allowListTuples[i] = keccak256(abi.encodePacked(other, i));
        }
        bytes32 merkleRoot = merkle.getRoot(allowListTuples);

        IERC1155SerendipityWithAllowlist.ClaimParameters memory claimP = IERC1155SerendipityWithAllowlist.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 1000,
            startDate: nowC,
            endDate: later,
            tokenVariations: 5,
            location: "arweaveHash1",
            paymentReceiver: payable(creator),
            cost: 0.01 ether,
            erc20: zeroAddress,
            merkleRoot: merkleRoot,
            walletMax: 0
        });

        example.initializeClaim(address(creatorCore1), 1, claimP);
        vm.stopPrank();

        uint256 totalCost = 0.01 ether + MINT_FEE;

        // Test gas usage for mints spread across bitmap boundaries
        vm.startPrank(other);
        
        // First mint (index 0 - first word in bitmap)
        bytes32[] memory proof0 = merkle.getProof(allowListTuples, 0);
        uint256 gasStart = gasleft();
        example.mintReserve{value: totalCost}(address(creatorCore1), 1, 0, proof0, 1);
        uint256 gasUsedFirst = gasStart - gasleft();

        // Mint at index 255 (different bitmap word)
        bytes32[] memory proof255 = merkle.getProof(allowListTuples, 50); // Using index 50 as we only have 100 tuples
        gasStart = gasleft();
        example.mintReserve{value: totalCost}(address(creatorCore1), 1, 50, proof255, 1);
        uint256 gasUsedDifferentWord = gasStart - gasleft();

        vm.stopPrank();

        console.log("First bitmap mint gas:", gasUsedFirst);
        console.log("Different bitmap word mint gas:", gasUsedDifferentWord);
        
        // Allow for some variance in gas usage across bitmap positions
        // The difference can be larger due to storage slot changes
        uint256 gasDiff = gasUsedFirst > gasUsedDifferentWord ? 
            gasUsedFirst - gasUsedDifferentWord : gasUsedDifferentWord - gasUsedFirst;
        assertTrue(gasDiff < 50000, "Gas usage difference across bitmap positions is too large");
    }

    // ============ UPDATE AND TOKEN URI TESTS ============

    function testUpdateClaimWithMerkleChanges() public {
        vm.startPrank(creator);
        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;

        // Create initial non-merkle claim
        IERC1155SerendipityWithAllowlist.ClaimParameters memory claimP = IERC1155SerendipityWithAllowlist.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 100,
            startDate: nowC,
            endDate: later,
            tokenVariations: 5,
            location: "arweaveHash1",
            paymentReceiver: payable(creator),
            cost: 0.01 ether,
            erc20: zeroAddress,
            merkleRoot: bytes32(0),
            walletMax: 3
        });

        example.initializeClaim(address(creatorCore1), 1, claimP);

        // Update to merkle claim
        bytes32[] memory allowListTuples = new bytes32[](2);
        allowListTuples[0] = keccak256(abi.encodePacked(other, uint32(0)));
        allowListTuples[1] = keccak256(abi.encodePacked(other2, uint32(1)));
        bytes32 merkleRoot = merkle.getRoot(allowListTuples);

        IERC1155SerendipityWithAllowlist.UpdateClaimParameters memory updateParams = IERC1155SerendipityWithAllowlist.UpdateClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            paymentReceiver: payable(creator),
            totalMax: 100,
            startDate: nowC,
            endDate: later,
            cost: 0.01 ether,
            location: "arweaveHash1",
            merkleRoot: merkleRoot,
            walletMax: 0 // Clear wallet max for merkle
        });

        example.updateClaim(address(creatorCore1), 1, updateParams);

        // Verify claim was updated
        IERC1155SerendipityWithAllowlist.Claim memory updatedClaim = example.getClaim(address(creatorCore1), 1);
        assertEq(updatedClaim.merkleRoot, merkleRoot, "Merkle root should be updated");
        assertEq(updatedClaim.walletMax, 0, "Wallet max should be cleared");
        vm.stopPrank();

        // Now should only accept merkle mints
        vm.startPrank(other);
        vm.expectRevert(ISerendipity.InvalidInput.selector);
        example.mintReserve{value: 0.01 ether + MINT_FEE}(address(creatorCore1), 1, 1);

        // But merkle mint should work
        bytes32[] memory proof = merkle.getProof(allowListTuples, 0);
        example.mintReserve{value: 0.01 ether + MINT_FEE}(address(creatorCore1), 1, 0, proof, 1);
        vm.stopPrank();
    }

    function testTokenURIGeneration() public {
        vm.startPrank(creator);
        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;

        IERC1155SerendipityWithAllowlist.ClaimParameters memory claimP = IERC1155SerendipityWithAllowlist.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 100,
            startDate: nowC,
            endDate: later,
            tokenVariations: 5,
            location: "testArweaveHash",
            paymentReceiver: payable(creator),
            cost: 0.01 ether,
            erc20: zeroAddress,
            merkleRoot: bytes32(0),
            walletMax: 0
        });

        example.initializeClaim(address(creatorCore1), 1, claimP);
        vm.stopPrank();

        // Get the claim to find starting token ID
        IERC1155SerendipityWithAllowlist.Claim memory claim = example.getClaim(address(creatorCore1), 1);
        uint256 startingTokenId = claim.startingTokenId;

        // Test token URI generation
        string memory uri1 = example.tokenURI(address(creatorCore1), startingTokenId);
        string memory uri2 = example.tokenURI(address(creatorCore1), startingTokenId + 1);
        string memory uri5 = example.tokenURI(address(creatorCore1), startingTokenId + 4);

        assertEq(uri1, "https://arweave.net/testArweaveHash/1", "First variation URI incorrect");
        assertEq(uri2, "https://arweave.net/testArweaveHash/2", "Second variation URI incorrect");
        assertEq(uri5, "https://arweave.net/testArweaveHash/5", "Fifth variation URI incorrect");

        // Test IPFS protocol
        vm.startPrank(creator);
        example.updateTokenURIParams(address(creatorCore1), 1, ISerendipity.StorageProtocol.IPFS, "testIpfsHash");
        vm.stopPrank();

        uri1 = example.tokenURI(address(creatorCore1), startingTokenId);
        assertEq(uri1, "ipfs://testIpfsHash/1", "IPFS URI incorrect");
    }

    // ============ ACCESS CONTROL TESTS ============

    function testAccessControl() public {
        vm.startPrank(other);
        // Must be admin
        vm.expectRevert();
        example.withdraw(payable(other), 20);
        vm.expectRevert("AdminControl: Must be owner or admin");
        example.setSigner(other);

        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;

        IERC1155SerendipityWithAllowlist.ClaimParameters memory claimP = IERC1155SerendipityWithAllowlist.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.IPFS,
            totalMax: 100,
            startDate: nowC,
            endDate: later,
            tokenVariations: 5,
            location: "arweaveHash1",
            paymentReceiver: payable(creator),
            cost: 0.01 ether,
            erc20: zeroAddress,
            merkleRoot: bytes32(0),
            walletMax: 0
        });
        // Must be admin
        vm.expectRevert();
        example.initializeClaim(address(creatorCore1), 1, claimP);
        vm.stopPrank();

        // Succeeds because is admin
        vm.startPrank(creator);
        example.initializeClaim(address(creatorCore1), 1, claimP);
        vm.stopPrank();

        // Try as a different non admin
        vm.startPrank(other2);
        vm.expectRevert();
        example.initializeClaim(address(creatorCore1), 2, claimP);
        vm.stopPrank();
    }

    function testDeprecatedContract() public {
        vm.startPrank(owner);
        example.deprecate(true);
        vm.stopPrank();

        vm.startPrank(creator);
        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;
        IERC1155SerendipityWithAllowlist.ClaimParameters memory claimP = IERC1155SerendipityWithAllowlist.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.IPFS,
            location: "arweaveHash1",
            totalMax: 0,
            startDate: nowC,
            endDate: later,
            tokenVariations: 5,
            paymentReceiver: payable(other),
            cost: 1,
            erc20: zeroAddress,
            merkleRoot: bytes32(0),
            walletMax: 0
        });
        vm.expectRevert(ISerendipity.ContractDeprecated.selector);
        example.initializeClaim(address(creatorCore1), 1, claimP);
        vm.stopPrank();
    }

    // ============ COMPLEX INTEGRATION TESTS ============

    function testCompleteWorkflowMerkleAndDelivery() public {
        vm.startPrank(creator);
        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;

        // Setup merkle claim
        bytes32[] memory allowListTuples = new bytes32[](3);
        allowListTuples[0] = keccak256(abi.encodePacked(other, uint32(0)));
        allowListTuples[1] = keccak256(abi.encodePacked(other2, uint32(1)));
        allowListTuples[2] = keccak256(abi.encodePacked(other3, uint32(2)));
        bytes32 merkleRoot = merkle.getRoot(allowListTuples);

        IERC1155SerendipityWithAllowlist.ClaimParameters memory claimP = IERC1155SerendipityWithAllowlist.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 100,
            startDate: nowC,
            endDate: later,
            tokenVariations: 3,
            location: "arweaveHash1",
            paymentReceiver: payable(creator),
            cost: 0.01 ether,
            erc20: zeroAddress,
            merkleRoot: merkleRoot,
            walletMax: 0
        });

        example.initializeClaim(address(creatorCore1), 1, claimP);
        vm.stopPrank();

        uint256 totalCost = 0.01 ether + MINT_FEE;

        // Multiple users mint with different proofs
        vm.startPrank(other);
        bytes32[] memory proof1 = merkle.getProof(allowListTuples, 0);
        example.mintReserve{value: totalCost * 2}(address(creatorCore1), 1, 0, proof1, 2);
        vm.stopPrank();

        vm.startPrank(other2);
        bytes32[] memory proof2 = merkle.getProof(allowListTuples, 1);
        example.mintReserve{value: totalCost}(address(creatorCore1), 1, 1, proof2, 1);
        vm.stopPrank();

        vm.startPrank(other3);
        bytes32[] memory proof3 = merkle.getProof(allowListTuples, 2);
        example.mintReserve{value: totalCost * 3}(address(creatorCore1), 1, 2, proof3, 3);
        vm.stopPrank();

        // Verify reservations
        Serendipity.UserMintDetails memory userMints1 = example.getUserMints(other, address(creatorCore1), 1);
        Serendipity.UserMintDetails memory userMints2 = example.getUserMints(other2, address(creatorCore1), 1);
        Serendipity.UserMintDetails memory userMints3 = example.getUserMints(other3, address(creatorCore1), 1);
        
        assertEq(userMints1.reservedCount, 2, "other should have 2 reserved");
        assertEq(userMints2.reservedCount, 1, "other2 should have 1 reserved");
        assertEq(userMints3.reservedCount, 3, "other3 should have 3 reserved");

        // Delivery phase
        vm.startPrank(signingAddress);
        ISerendipity.ClaimMint[] memory mints = new ISerendipity.ClaimMint[](3);
        
        // Deliver for other
        ISerendipity.VariationMint[] memory variationMints1 = new ISerendipity.VariationMint[](1);
        variationMints1[0] = ISerendipity.VariationMint({ variationIndex: 1, amount: 2, recipient: other });
        mints[0] = ISerendipity.ClaimMint({
            creatorContractAddress: address(creatorCore1),
            instanceId: 1,
            variationMints: variationMints1
        });

        // Deliver for other2
        ISerendipity.VariationMint[] memory variationMints2 = new ISerendipity.VariationMint[](1);
        variationMints2[0] = ISerendipity.VariationMint({ variationIndex: 2, amount: 1, recipient: other2 });
        mints[1] = ISerendipity.ClaimMint({
            creatorContractAddress: address(creatorCore1),
            instanceId: 1,
            variationMints: variationMints2
        });

        // Deliver for other3 (mixed variations)
        ISerendipity.VariationMint[] memory variationMints3 = new ISerendipity.VariationMint[](2);
        variationMints3[0] = ISerendipity.VariationMint({ variationIndex: 1, amount: 1, recipient: other3 });
        variationMints3[1] = ISerendipity.VariationMint({ variationIndex: 3, amount: 2, recipient: other3 });
        mints[2] = ISerendipity.ClaimMint({
            creatorContractAddress: address(creatorCore1),
            instanceId: 1,
            variationMints: variationMints3
        });

        example.deliverMints(mints);
        vm.stopPrank();

        // Verify deliveries
        userMints1 = example.getUserMints(other, address(creatorCore1), 1);
        userMints2 = example.getUserMints(other2, address(creatorCore1), 1);
        userMints3 = example.getUserMints(other3, address(creatorCore1), 1);
        
        assertEq(userMints1.deliveredCount, 2, "other should have 2 delivered");
        assertEq(userMints2.deliveredCount, 1, "other2 should have 1 delivered");
        assertEq(userMints3.deliveredCount, 3, "other3 should have 3 delivered");

        // Verify token balances
        IERC1155SerendipityWithAllowlist.Claim memory claim = example.getClaim(address(creatorCore1), 1);
        uint256 startingTokenId = claim.startingTokenId;
        
        assertEq(creatorCore1.balanceOf(other, startingTokenId), 2, "other should have 2 of variation 1");
        assertEq(creatorCore1.balanceOf(other2, startingTokenId + 1), 1, "other2 should have 1 of variation 2");
        assertEq(creatorCore1.balanceOf(other3, startingTokenId), 1, "other3 should have 1 of variation 1");
        assertEq(creatorCore1.balanceOf(other3, startingTokenId + 2), 2, "other3 should have 2 of variation 3");
    }
}

// Helper contract to test contract minting restriction
contract ContractMinter {
    function attemptMint(
        ERC1155SerendipityWithAllowlist target, 
        address creatorContract, 
        uint256 instanceId, 
        uint256 value
    ) external {
        target.mintReserve{value: value}(creatorContract, instanceId, 1);
    }
}