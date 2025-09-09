// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../contracts/gachaclaims/IERC1155Serendipity.sol";
import "../../contracts/gachaclaims/ERC1155Serendipity.sol";
import "../../contracts/gachaclaims/ISerendipity.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC1155Creator.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "../../contracts/libraries/delegation-registry/IDelegationRegistry.sol";
import "../../contracts/libraries/delegation-registry/IDelegationRegistryV2.sol";

// Mock Delegation Registry V1
contract MockDelegationRegistry is IDelegationRegistry {
    mapping(address => mapping(address => mapping(address => bool))) private _contractDelegations;
    
    function delegateForContract(address delegate, address contract_, bool value) external {
        _contractDelegations[msg.sender][delegate][contract_] = value;
    }
    
    function checkDelegateForContract(address delegate, address vault, address contract_) 
        external 
        view 
        override
        returns (bool) 
    {
        return _contractDelegations[vault][delegate][contract_];
    }
    
    // Implement other required interface methods with empty/default implementations
    function checkDelegateForAll(address, address) external pure returns (bool) { return false; }
    function checkDelegateForToken(address, address, address, uint256) external pure returns (bool) { return false; }
    function delegateForAll(address, bool) external {}
    function delegateForToken(address, address, uint256, bool) external {}
    function revokeAllDelegates() external {}
    function revokeDelegate(address) external {}
    function revokeSelf(address) external {}
    function getDelegationsByDelegate(address) external pure returns (DelegationInfo[] memory) {
        return new DelegationInfo[](0);
    }
    function getDelegatesForAll(address) external pure returns (address[] memory) {
        return new address[](0);
    }
    function getDelegatesForContract(address, address) external pure returns (address[] memory) {
        return new address[](0);
    }
    function getDelegatesForToken(address, address, uint256) external pure returns (address[] memory) {
        return new address[](0);
    }
    function getContractLevelDelegations(address) external pure returns (ContractDelegation[] memory) {
        return new ContractDelegation[](0);
    }
    function getTokenLevelDelegations(address) external pure returns (TokenDelegation[] memory) {
        return new TokenDelegation[](0);
    }
    function getDelegatesForTokens(address, address, uint256[] calldata) external pure returns (address[] memory) {
        return new address[](0);
    }
}

// Mock Delegation Registry V2
contract MockDelegationRegistryV2 {
    mapping(address => mapping(address => mapping(address => bool))) private _contractDelegations;
    
    function delegateContract(address delegate, address contract_, bool enable) external {
        _contractDelegations[msg.sender][delegate][contract_] = enable;
    }
    
    function checkDelegateForContract(
        address delegate,
        address vault,
        address contract_,
        bytes32
    ) external view returns (bool) {
        return _contractDelegations[vault][delegate][contract_];
    }
}

contract ERC1155SerendipityTest is Test {
    ERC1155Serendipity public extension;
    ERC1155Creator public creatorCore;
    ERC1155Creator public creatorCore2;
    MockDelegationRegistry public delegationRegistryV1;
    MockDelegationRegistryV2 public delegationRegistryV2;

    address public creator = 0xc78Dc443c126af6E4f6Ed540c1e740C1b5be09cd;
    address public owner = 0x6140F00e4Ff3936702E68744f2b5978885464cbB;
    address public signingAddress = 0xc78dC443c126Af6E4f6eD540C1E740c1B5be09CE;
    address public alice = 0x5174cD462b60c536eb51D4ceC1D561D3Ea31004F;
    address public bob = 0x80AAC46bbd3C2FcE33681541a52CacBEd14bF425;
    address public charlie = 0x1234567890123456789012345678901234567890;
    address public unauthorized = 0x9876543210987654321098765432109876543210;

    uint256 public MINT_FEE = 500000000000000;
    uint256 public MINT_FEE_MERKLE = 690000000000000;
    uint32 constant MAX_UINT_32 = 0xffffffff;

    // Merkle tree data for testing (alice, bob, charlie)
    bytes32 public merkleRoot;
    bytes32[] public aliceProof;
    bytes32[] public bobProof;
    bytes32[] public charlieProof;

    function setUp() public {
        // Deploy creator contracts
        vm.startPrank(creator);
        creatorCore = new ERC1155Creator("Test", "TEST");
        creatorCore2 = new ERC1155Creator("Test2", "TEST2");
        vm.stopPrank();

        // Deploy delegation registries
        delegationRegistryV1 = new MockDelegationRegistry();
        delegationRegistryV2 = new MockDelegationRegistryV2();
        
        // Deploy extension with delegation support
        vm.startPrank(owner);
        extension = new ERC1155Serendipity(
            owner,
            address(delegationRegistryV1),
            address(delegationRegistryV2)
        );
        extension.setSigner(signingAddress);
        vm.stopPrank();
        
        // Get initial fees from contract
        MINT_FEE = extension.getMintFee();
        MINT_FEE_MERKLE = extension.getMintFeeMerkle();

        // Register extension with both creator contracts
        vm.startPrank(creator);
        creatorCore.registerExtension(address(extension), "override");
        creatorCore2.registerExtension(address(extension), "override");
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
        // Create a simple merkle tree with alice (mintIndex 0), bob (mintIndex 1), charlie (mintIndex 2)
        // For simplicity, we'll use a 4-leaf tree (padding with duplicate)
        bytes32[] memory leaves = new bytes32[](4);
        leaves[0] = keccak256(abi.encodePacked(alice, uint32(0)));
        leaves[1] = keccak256(abi.encodePacked(bob, uint32(1)));
        leaves[2] = keccak256(abi.encodePacked(charlie, uint32(2)));
        leaves[3] = keccak256(abi.encodePacked(charlie, uint32(2))); // Duplicate for even number

        // Build merkle tree
        // Level 0: [alice+0, bob+1, charlie+2, charlie+2]
        // Level 1: [hash(alice+0, bob+1), hash(charlie+2, charlie+2)]
        // Level 2: [root]
        bytes32 hash01 = _hashPair(leaves[0], leaves[1]);
        bytes32 hash23 = _hashPair(leaves[2], leaves[3]);
        merkleRoot = _hashPair(hash01, hash23);

        // Build proofs
        aliceProof = new bytes32[](2);
        aliceProof[0] = leaves[1]; // bob+1
        aliceProof[1] = hash23; // hash(charlie+2, charlie+2)

        bobProof = new bytes32[](2);
        bobProof[0] = leaves[0]; // alice+0
        bobProof[1] = hash23; // hash(charlie+2, charlie+2)

        charlieProof = new bytes32[](2);
        charlieProof[0] = leaves[3]; // charlie+2 (duplicate)
        charlieProof[1] = hash01; // hash(alice+0, bob+1)
    }

    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    // ============ Initialization Tests ============

    function test_initializeClaim_withMerkleRoot_succeedsForAdmin() public {
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
            walletMax: 2
        });

        extension.initializeClaim(address(creatorCore), 1, params);

        IERC1155Serendipity.Claim memory claim = extension.getClaim(address(creatorCore), 1);
        assertEq(claim.merkleRoot, merkleRoot);
        assertEq(claim.walletMax, 2);
        assertEq(claim.totalMax, 100);
    }

    function test_initializeClaim_withoutMerkleRoot_succeedsForAdmin() public {
        vm.startPrank(creator);
        
        IERC1155Serendipity.ClaimParameters memory params = IERC1155Serendipity.ClaimParameters({
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

        IERC1155Serendipity.Claim memory claim = extension.getClaim(address(creatorCore), 2);
        assertEq(claim.merkleRoot, bytes32(0));
        assertEq(claim.walletMax, 5);
        assertEq(claim.totalMax, 50);
    }

    function test_initializeClaim_revertsForNonAdmin() public {
        vm.startPrank(unauthorized);
        
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
            walletMax: 2
        });

        vm.expectRevert("Wallet is not an administrator for contract");
        extension.initializeClaim(address(creatorCore), 3, params);
    }

    // ============ Update Tests ============

    function test_updateClaim_withMerkleRoot_succeedsForAdmin() public {
        // First initialize a claim
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
            merkleRoot: bytes32(0),
            walletMax: 0
        });

        extension.initializeClaim(address(creatorCore), 4, params);

        // Now update it with merkle root
        IERC1155Serendipity.UpdateClaimParameters memory updateParams = IERC1155Serendipity.UpdateClaimParameters({
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

        IERC1155Serendipity.Claim memory claim = extension.getClaim(address(creatorCore), 4);
        assertEq(claim.merkleRoot, merkleRoot);
        assertEq(claim.walletMax, 3);
        assertEq(claim.totalMax, 200);
        assertEq(claim.paymentReceiver, bob);
    }

    function test_updateClaim_revertsForNonAdmin() public {
        // First initialize a claim as admin
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
            merkleRoot: bytes32(0),
            walletMax: 0
        });

        extension.initializeClaim(address(creatorCore), 5, params);
        vm.stopPrank();

        // Try to update as non-admin
        vm.startPrank(unauthorized);
        
        IERC1155Serendipity.UpdateClaimParameters memory updateParams = IERC1155Serendipity.UpdateClaimParameters({
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
            walletMax: 2
        });

        extension.initializeClaim(address(creatorCore), 10, params);
        vm.stopPrank();

        // Alice mints with valid proof
        vm.startPrank(alice);
        uint256 totalCost = (0.01 ether + MINT_FEE_MERKLE);
        
        uint32[] memory indices = new uint32[](1);
        indices[0] = 0; // mintIndex for alice
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = aliceProof;
        
        extension.mintReserve{value: totalCost}(
            address(creatorCore), 
            10, 
            1,
            indices,
            proofs,
            address(0)
        );

        ISerendipity.UserMintDetails memory details = extension.getUserMints(alice, address(creatorCore), 10);
        assertEq(details.reservedCount, 1);
    }

    function test_mintReserve_validMerkleProof_bob() public {
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
            walletMax: 2
        });

        extension.initializeClaim(address(creatorCore), 11, params);
        vm.stopPrank();

        // Bob mints with valid proof
        vm.startPrank(bob);
        uint256 totalCost = (0.01 ether + MINT_FEE_MERKLE);
        
        uint32[] memory indices = new uint32[](1);
        indices[0] = 1; // mintIndex for bob
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = bobProof;
        
        extension.mintReserve{value: totalCost}(
            address(creatorCore), 
            11, 
            1,
            indices,
            proofs,
            address(0)
        );

        ISerendipity.UserMintDetails memory details = extension.getUserMints(bob, address(creatorCore), 11);
        assertEq(details.reservedCount, 1);
    }

    function test_mintReserve_invalidMerkleProof_reverts() public {
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
            walletMax: 2
        });

        extension.initializeClaim(address(creatorCore), 12, params);
        vm.stopPrank();

        // Unauthorized user tries to mint with alice's proof
        vm.startPrank(unauthorized);
        uint256 totalCost = (0.01 ether + MINT_FEE_MERKLE);
        
        vm.expectRevert(ISerendipity.InvalidMerkleProof.selector);
        uint32[] memory indices = new uint32[](1);
        indices[0] = 0; // wrong mintIndex
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = bobProof; // Wrong proof for alice
        
        extension.mintReserve{value: totalCost}(
            address(creatorCore), 
            12, 
            1,
            indices,
            proofs,
            address(0)
        );
    }

    function test_mintReserve_emptyMerkleProof_whenNoMerkleRoot() public {
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
            merkleRoot: bytes32(0),
            walletMax: 0
        });

        extension.initializeClaim(address(creatorCore), 13, params);
        vm.stopPrank();

        // Anyone can mint when no merkle root
        vm.startPrank(unauthorized);
        uint256 totalCost = (0.01 ether + MINT_FEE);
        
        extension.mintReserve{value: totalCost}(
            address(creatorCore), 
            13, 
            1,
            new uint32[](0), // empty for non-merkle
            new bytes32[][](0), // empty for non-merkle
            address(0)
        );

        ISerendipity.UserMintDetails memory details = extension.getUserMints(unauthorized, address(creatorCore), 13);
        assertEq(details.reservedCount, 1);
    }

    // ============ Wallet Max Tests ============

    function test_walletMax_withMerkleRoot_enforced() public {
        // Initialize claim with merkle root and wallet max
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
            walletMax: 2
        });

        extension.initializeClaim(address(creatorCore), 20, params);
        vm.stopPrank();

        // Alice mints 1 (she only has proof for index 0)
        vm.startPrank(alice);
        uint256 totalCost = (0.01 ether + MINT_FEE_MERKLE);
        
        uint32[] memory indices = new uint32[](1);
        indices[0] = 0; // alice's mintIndex
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = aliceProof;
        
        extension.mintReserve{value: totalCost}(
            address(creatorCore), 
            20, 
            1,
            indices,
            proofs,
            address(0)
        );

        // Alice can mint again since wallet max is 2
        // But she cannot reuse the same mintIndex - should fail
        vm.expectRevert(ISerendipity.InvalidMerkleProof.selector);
        extension.mintReserve{value: totalCost}(
            address(creatorCore), 
            20, 
            1,
            indices,  // trying to reuse same index
            proofs,
            address(0)
        );
    }

    function test_walletMax_withoutMerkleRoot_enforced() public {
        // Initialize claim without merkle root but with wallet max
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
            merkleRoot: bytes32(0),
            walletMax: 3
        });

        extension.initializeClaim(address(creatorCore), 21, params);
        vm.stopPrank();

        // Unauthorized user mints 3 (wallet max)
        vm.startPrank(unauthorized);
        uint256 totalCost = (0.01 ether + MINT_FEE) * 3;
        
        extension.mintReserve{value: totalCost}(
            address(creatorCore), 
            21, 
            3,
            new uint32[](0), // empty for non-merkle
            new bytes32[][](0), // empty for non-merkle
            address(0)
        );

        // Try to mint more than wallet max
        vm.expectRevert(ISerendipity.TooManyRequested.selector);
        extension.mintReserve{value: 0.01 ether + MINT_FEE}(
            address(creatorCore), 
            21, 
            1,
            new uint32[](0), // empty for non-merkle
            new bytes32[][](0), // empty for non-merkle
            address(0)
        );
    }

    // ============ Delivery Tests ============

    function test_deliverMints_afterReservation() public {
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
            walletMax: 5
        });

        extension.initializeClaim(address(creatorCore), 30, params);
        vm.stopPrank();

        // Alice reserves mints - with merkle, alice can only mint 1 with her proof for index 0
        vm.startPrank(alice);
        uint256 totalCost = (0.01 ether + MINT_FEE_MERKLE);
        
        uint32[] memory indices = new uint32[](1);
        indices[0] = 0;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = aliceProof;
        
        extension.mintReserve{value: totalCost}(
            address(creatorCore), 
            30, 
            1,
            indices,
            proofs,
            address(0)
        );
        vm.stopPrank();

        // Deliver mints as signer
        vm.startPrank(signingAddress);
        
        ISerendipity.VariationMint[] memory variations = new ISerendipity.VariationMint[](1);
        variations[0] = ISerendipity.VariationMint({
            variationIndex: 1,
            amount: 1,
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
        assertEq(details.reservedCount, 1);
        assertEq(details.deliveredCount, 1);
    }

    // ============ Payment Tests ============

    function test_payment_correctAmountRequired() public {
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
            walletMax: 2
        });

        extension.initializeClaim(address(creatorCore), 40, params);
        vm.stopPrank();

        vm.startPrank(alice);
        
        // Try with insufficient payment
        vm.expectRevert(ISerendipity.InvalidPayment.selector);
        uint32[] memory indices = new uint32[](1);
        indices[0] = 0;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = aliceProof;
        
        extension.mintReserve{value: 0.05 ether}(
            address(creatorCore), 
            40, 
            1,
            indices,
            proofs,
            address(0)
        );

        // Mint with correct payment
        uint256 correctPayment = 0.1 ether + MINT_FEE_MERKLE;
        uint256 creatorBalanceBefore = creator.balance;
        
        uint32[] memory indices2 = new uint32[](1);
        indices2[0] = 0;
        bytes32[][] memory proofs2 = new bytes32[][](1);
        proofs2[0] = aliceProof;
        
        extension.mintReserve{value: correctPayment}(
            address(creatorCore), 
            40, 
            1,
            indices2,
            proofs2,
            address(0)
        );

        // Verify payment was sent to creator
        assertEq(creator.balance - creatorBalanceBefore, 0.1 ether);
    }

    // ============ Edge Cases ============

    function test_claimExpired_reverts() public {
        // Initialize claim that will be expired
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
            walletMax: 2
        });

        extension.initializeClaim(address(creatorCore), 50, params);
        vm.stopPrank();

        // Fast forward time to after the claim expires
        vm.warp(block.timestamp + 1001);

        vm.startPrank(alice);
        uint256 totalCost = (0.01 ether + MINT_FEE_MERKLE);
        
        vm.expectRevert(ISerendipity.ClaimInactive.selector);
        uint32[] memory indices = new uint32[](1);
        indices[0] = 0;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = aliceProof;
        
        extension.mintReserve{value: totalCost}(
            address(creatorCore), 
            50, 
            1,
            indices,
            proofs,
            address(0)
        );
    }

    function test_claimNotStarted_reverts() public {
        // Initialize claim that hasn't started yet
        vm.startPrank(creator);
        
        IERC1155Serendipity.ClaimParameters memory params = IERC1155Serendipity.ClaimParameters({
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
        uint32[] memory indices = new uint32[](1);
        indices[0] = 0;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = aliceProof;
        
        extension.mintReserve{value: totalCost}(
            address(creatorCore), 
            51, 
            1,
            indices,
            proofs,
            address(0)
        );
    }

    function test_claimSoldOut_reverts() public {
        // Initialize claim with very limited supply
        vm.startPrank(creator);
        
        IERC1155Serendipity.ClaimParameters memory params = IERC1155Serendipity.ClaimParameters({
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
        
        uint32[] memory indices = new uint32[](1);
        indices[0] = 0;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = aliceProof;
        
        extension.mintReserve{value: totalCost}(
            address(creatorCore), 
            52, 
            1,
            indices,
            proofs,
            address(0)
        );
        vm.stopPrank();

        // Bob tries to mint but it's sold out
        vm.startPrank(bob);
        
        vm.expectRevert(ISerendipity.ClaimSoldOut.selector);
        uint32[] memory indices2 = new uint32[](1);
        indices2[0] = 1;
        bytes32[][] memory proofs2 = new bytes32[][](1);
        proofs2[0] = bobProof;
        
        extension.mintReserve{value: totalCost}(
            address(creatorCore), 
            52, 
            1,
            indices2,
            proofs2,
            address(0)
        );
    }

    // ============ Interface Support Tests ============

    function test_supportsInterface() public {
        assertTrue(extension.supportsInterface(type(IERC1155Serendipity).interfaceId));
        assertTrue(extension.supportsInterface(type(ISerendipity).interfaceId));
        assertTrue(extension.supportsInterface(type(IERC165).interfaceId));
    }

    // ============ Token URI Tests ============

    function test_tokenURI_generation() public {
        // Initialize claim
        vm.startPrank(creator);
        
        IERC1155Serendipity.ClaimParameters memory params = IERC1155Serendipity.ClaimParameters({
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

        IERC1155Serendipity.Claim memory claim = extension.getClaim(address(creatorCore), 60);
        uint256 tokenId = claim.startingTokenId;

        string memory uri = extension.tokenURI(address(creatorCore), tokenId);
        assertEq(uri, "https://arweave.net/arweave-hash-123/1");
    }

    function test_updateTokenURIParams() public {
        // Initialize claim
        vm.startPrank(creator);
        
        IERC1155Serendipity.ClaimParameters memory params = IERC1155Serendipity.ClaimParameters({
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

        IERC1155Serendipity.Claim memory claim = extension.getClaim(address(creatorCore), 61);
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

    // ============ Fee Update Tests ============

    function test_setMintFees_onlyAdmin() public {
        uint256 newMintFee = 0.001 ether;
        uint256 newMintFeeMerkle = 0.0015 ether;

        // Non-admin cannot set fees
        vm.startPrank(unauthorized);
        vm.expectRevert("AdminControl: Must be owner or admin");
        extension.setMintFees(newMintFee, newMintFeeMerkle);
        vm.stopPrank();

        // Admin can set fees
        vm.startPrank(owner);
        extension.setMintFees(newMintFee, newMintFeeMerkle);
        assertEq(extension.getMintFee(), newMintFee);
        assertEq(extension.getMintFeeMerkle(), newMintFeeMerkle);
        vm.stopPrank();
    }

    function test_setMintFees_affectsMintingCost() public {
        // Initialize a claim without merkle
        vm.startPrank(creator);
        IERC1155Serendipity.ClaimParameters memory params = IERC1155Serendipity.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 100,
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + 1000),
            tokenVariations: 3,
            location: "test-location",
            paymentReceiver: payable(creator),
            cost: 0,
            erc20: address(0),
            merkleRoot: bytes32(0),
            walletMax: 0
        });
        extension.initializeClaim(address(creatorCore), 100, params);
        vm.stopPrank();

        // Update fees
        vm.startPrank(owner);
        uint256 newMintFee = 0.002 ether;
        extension.setMintFees(newMintFee, 0.003 ether);
        vm.stopPrank();

        // Mint with new fee
        vm.startPrank(alice);
        extension.mintReserve{value: newMintFee}(
            address(creatorCore), 
            100, 
            1,
            new uint32[](0), // empty for non-merkle
            new bytes32[][](0), // empty for non-merkle
            address(0)
        );
        vm.stopPrank();

        // Verify mint was successful with new fee
        ISerendipity.UserMintDetails memory details = extension.getUserMints(alice, address(creatorCore), 100);
        assertEq(details.reservedCount, 1);
    }

    function test_setMintFees_affectsMerkleMintingCost() public {
        // Initialize a claim with merkle
        vm.startPrank(creator);
        IERC1155Serendipity.ClaimParameters memory params = IERC1155Serendipity.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 100,
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + 1000),
            tokenVariations: 3,
            location: "test-location",
            paymentReceiver: payable(creator),
            cost: 0,
            erc20: address(0),
            merkleRoot: merkleRoot,
            walletMax: 0
        });
        extension.initializeClaim(address(creatorCore), 101, params);
        vm.stopPrank();

        // Update fees
        vm.startPrank(owner);
        uint256 newMintFeeMerkle = 0.003 ether;
        extension.setMintFees(0.002 ether, newMintFeeMerkle);
        vm.stopPrank();

        // Mint with new merkle fee
        vm.startPrank(alice);
        uint32[] memory indices = new uint32[](1);
        indices[0] = 0;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = aliceProof;
        
        extension.mintReserve{value: newMintFeeMerkle}(
            address(creatorCore), 
            101, 
            1,
            indices,
            proofs,
            address(0)
        );
        vm.stopPrank();

        // Verify mint was successful with new fee
        ISerendipity.UserMintDetails memory details = extension.getUserMints(alice, address(creatorCore), 101);
        assertEq(details.reservedCount, 1);
    }

    function test_setMintFees_insufficientPaymentAfterUpdate() public {
        // Initialize a claim
        vm.startPrank(creator);
        IERC1155Serendipity.ClaimParameters memory params = IERC1155Serendipity.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 100,
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + 1000),
            tokenVariations: 3,
            location: "test-location",
            paymentReceiver: payable(creator),
            cost: 0,
            erc20: address(0),
            merkleRoot: bytes32(0),
            walletMax: 0
        });
        extension.initializeClaim(address(creatorCore), 102, params);
        vm.stopPrank();

        // Update fees to higher amount
        vm.startPrank(owner);
        uint256 oldFee = extension.getMintFee();
        uint256 newMintFee = 0.005 ether;
        extension.setMintFees(newMintFee, 0.006 ether);
        vm.stopPrank();

        // Try to mint with old fee amount - should fail
        vm.startPrank(alice);
        vm.expectRevert(ISerendipity.InvalidPayment.selector);
        extension.mintReserve{value: oldFee}(
            address(creatorCore), 
            102, 
            1,
            new uint32[](0), // empty for non-merkle
            new bytes32[][](0), // empty for non-merkle
            address(0)
        );
        vm.stopPrank();
    }

    // ============ Delegation Tests ============

    function test_mintReserve_withDelegationV1_validProof() public {
        // Setup claim with merkle root
        vm.startPrank(creator);
        IERC1155Serendipity.ClaimParameters memory params = IERC1155Serendipity.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 100,
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + 1000),
            tokenVariations: 3,
            location: "test-location",
            paymentReceiver: payable(creator),
            cost: 0,
            erc20: address(0),
            merkleRoot: merkleRoot,
            walletMax: 2
        });
        extension.initializeClaim(address(creatorCore), 200, params);
        vm.stopPrank();

        // Alice delegates to unauthorized
        vm.startPrank(alice);
        delegationRegistryV1.delegateForContract(unauthorized, address(extension), true);
        vm.stopPrank();

        // Unauthorized mints on behalf of alice using delegation
        vm.startPrank(unauthorized);
        uint32[] memory indices = new uint32[](1);
        indices[0] = 0;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = aliceProof;
        
        extension.mintReserve{value: MINT_FEE_MERKLE}(
            address(creatorCore),
            200,
            1,
            indices,
            proofs,
            alice  // mintFor
        );
        vm.stopPrank();

        // Verify alice is credited with the mint
        ISerendipity.UserMintDetails memory details = extension.getUserMints(alice, address(creatorCore), 200);
        assertEq(details.reservedCount, 1);
    }

    function test_mintReserve_withDelegationV2_validProof() public {
        // Setup claim with merkle root
        vm.startPrank(creator);
        IERC1155Serendipity.ClaimParameters memory params = IERC1155Serendipity.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 100,
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + 1000),
            tokenVariations: 3,
            location: "test-location",
            paymentReceiver: payable(creator),
            cost: 0,
            erc20: address(0),
            merkleRoot: merkleRoot,
            walletMax: 2
        });
        extension.initializeClaim(address(creatorCore), 201, params);
        vm.stopPrank();

        // Bob delegates to unauthorized using V2
        vm.startPrank(bob);
        delegationRegistryV2.delegateContract(unauthorized, address(extension), true);
        vm.stopPrank();

        // Unauthorized mints on behalf of bob using V2 delegation
        vm.startPrank(unauthorized);
        uint32[] memory indices = new uint32[](1);
        indices[0] = 1;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = bobProof;
        
        extension.mintReserve{value: MINT_FEE_MERKLE}(
            address(creatorCore),
            201,
            1,
            indices,
            proofs,
            bob  // mintFor
        );
        vm.stopPrank();

        // Verify bob is credited with the mint
        ISerendipity.UserMintDetails memory details = extension.getUserMints(bob, address(creatorCore), 201);
        assertEq(details.reservedCount, 1);
    }

    function test_mintReserve_withInvalidDelegation_reverts() public {
        // Setup claim with merkle root
        vm.startPrank(creator);
        IERC1155Serendipity.ClaimParameters memory params = IERC1155Serendipity.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 100,
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + 1000),
            tokenVariations: 3,
            location: "test-location",
            paymentReceiver: payable(creator),
            cost: 0,
            erc20: address(0),
            merkleRoot: merkleRoot,
            walletMax: 2
        });
        extension.initializeClaim(address(creatorCore), 202, params);
        vm.stopPrank();

        // Unauthorized tries to mint on behalf of alice WITHOUT delegation
        vm.startPrank(unauthorized);
        vm.expectRevert(ISerendipity.InvalidDelegate.selector);
        uint32[] memory indices = new uint32[](1);
        indices[0] = 0;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = aliceProof;
        
        extension.mintReserve{value: MINT_FEE_MERKLE}(
            address(creatorCore),
            202,
            1,
            indices,
            proofs,
            alice  // mintFor
        );
        vm.stopPrank();
    }

    function test_mintReserve_delegation_respectsWalletMax() public {
        // Setup claim with merkle root and wallet max
        vm.startPrank(creator);
        IERC1155Serendipity.ClaimParameters memory params = IERC1155Serendipity.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 100,
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + 1000),
            tokenVariations: 3,
            location: "test-location",
            paymentReceiver: payable(creator),
            cost: 0,
            erc20: address(0),
            merkleRoot: merkleRoot,
            walletMax: 1  // Only 1 mint allowed per wallet
        });
        extension.initializeClaim(address(creatorCore), 203, params);
        vm.stopPrank();

        // Alice delegates to unauthorized
        vm.startPrank(alice);
        delegationRegistryV1.delegateForContract(unauthorized, address(extension), true);
        vm.stopPrank();

        // First mint should succeed
        vm.startPrank(unauthorized);
        uint32[] memory indices = new uint32[](1);
        indices[0] = 0;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = aliceProof;
        
        extension.mintReserve{value: MINT_FEE_MERKLE}(
            address(creatorCore),
            203,
            1,
            indices,
            proofs,
            alice
        );
        
        // Second mint should fail due to mintIndex reuse (security fix prevents proof reuse)
        vm.expectRevert(ISerendipity.InvalidMerkleProof.selector);
        uint32[] memory indices2 = new uint32[](1);
        indices2[0] = 0; // trying to reuse mintIndex 0
        bytes32[][] memory proofs2 = new bytes32[][](1);
        proofs2[0] = aliceProof;
        
        extension.mintReserve{value: MINT_FEE_MERKLE}(
            address(creatorCore),
            203,
            1,
            indices2,
            proofs2,
            alice
        );
        vm.stopPrank();
    }

    function test_mintReserve_selfDelegation_works() public {
        // Setup claim
        vm.startPrank(creator);
        IERC1155Serendipity.ClaimParameters memory params = IERC1155Serendipity.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 100,
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + 1000),
            tokenVariations: 3,
            location: "test-location",
            paymentReceiver: payable(creator),
            cost: 0,
            erc20: address(0),
            merkleRoot: merkleRoot,
            walletMax: 2
        });
        extension.initializeClaim(address(creatorCore), 204, params);
        vm.stopPrank();

        // Alice mints for herself (self-delegation)
        vm.startPrank(alice);
        uint32[] memory indices = new uint32[](1);
        indices[0] = 0; // mintIndex for alice
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = aliceProof;
        
        extension.mintReserve{value: MINT_FEE_MERKLE}(
            address(creatorCore),
            204,
            1,
            indices,
            proofs,
            alice  // mintFor = msg.sender (self)
        );
        vm.stopPrank();

        // Verify mint succeeded
        ISerendipity.UserMintDetails memory details = extension.getUserMints(alice, address(creatorCore), 204);
        assertEq(details.reservedCount, 1);
    }

    function test_mintReserve_withoutMerkle_andDelegation() public {
        // Setup claim without merkle root
        vm.startPrank(creator);
        IERC1155Serendipity.ClaimParameters memory params = IERC1155Serendipity.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 100,
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + 1000),
            tokenVariations: 3,
            location: "test-location",
            paymentReceiver: payable(creator),
            cost: 0,
            erc20: address(0),
            merkleRoot: bytes32(0),  // No merkle
            walletMax: 2
        });
        extension.initializeClaim(address(creatorCore), 205, params);
        vm.stopPrank();

        // Charlie delegates to unauthorized
        vm.startPrank(charlie);
        delegationRegistryV1.delegateForContract(unauthorized, address(extension), true);
        vm.stopPrank();

        // Unauthorized mints on behalf of charlie (no merkle proof needed)
        vm.startPrank(unauthorized);
        extension.mintReserve{value: MINT_FEE}(
            address(creatorCore), 
            205, 
            1,
            new uint32[](0), // empty for non-merkle
            new bytes32[][](0), // empty for non-merkle
            charlie  // mintFor charlie
        );
        vm.stopPrank();

        // Verify charlie is credited
        ISerendipity.UserMintDetails memory details = extension.getUserMints(charlie, address(creatorCore), 205);
        assertEq(details.reservedCount, 1);
    }

    // ============ Additional Tests from Base ERC1155Serendipity ============

    function test_setSigner_onlyAdmin() public {
        address newSigner = address(0x123);
        
        // Non-admin cannot set signer
        vm.startPrank(unauthorized);
        vm.expectRevert("AdminControl: Must be owner or admin");
        extension.setSigner(newSigner);
        vm.stopPrank();

        // Admin can set signer
        vm.startPrank(owner);
        extension.setSigner(newSigner);
        vm.stopPrank();

        // Verify new signer works
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
            walletMax: 0
        });
        extension.initializeClaim(address(creatorCore), 80, params);
        vm.deal(creator, 10 ether);
        extension.mintReserve{value: MINT_FEE}(
            address(creatorCore), 
            80, 
            1,
            new uint32[](0), // empty for non-merkle
            new bytes32[][](0), // empty for non-merkle
            address(0)
        );
        vm.stopPrank();

        // Old signer should fail
        vm.startPrank(signingAddress);
        ISerendipity.VariationMint[] memory variations = new ISerendipity.VariationMint[](1);
        variations[0] = ISerendipity.VariationMint({
            variationIndex: 1,
            amount: 1,
            recipient: creator
        });
        ISerendipity.ClaimMint[] memory mints = new ISerendipity.ClaimMint[](1);
        mints[0] = ISerendipity.ClaimMint({
            creatorContractAddress: address(creatorCore),
            instanceId: 80,
            variationMints: variations
        });
        vm.expectRevert(ISerendipity.InvalidSignature.selector);
        extension.deliverMints(mints);
        vm.stopPrank();

        // New signer should work
        vm.startPrank(newSigner);
        extension.deliverMints(mints);
        vm.stopPrank();
    }

    function test_initializeClaimSanitization() public {
        vm.startPrank(creator);

        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;

        IERC1155Serendipity.ClaimParameters memory params = IERC1155Serendipity.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.INVALID,
            totalMax: 100,
            startDate: nowC,
            endDate: later,
            tokenVariations: 5,
            location: "test-location",
            paymentReceiver: payable(creator),
            cost: 0.01 ether,
            erc20: address(0),
            merkleRoot: bytes32(0),
            walletMax: 0
        });

        // Invalid storage protocol
        vm.expectRevert(ISerendipity.InvalidStorageProtocol.selector);
        extension.initializeClaim(address(creatorCore), 81, params);

        // Invalid date (start > end)
        params.storageProtocol = ISerendipity.StorageProtocol.ARWEAVE;
        params.startDate = nowC + 2000;
        vm.expectRevert(ISerendipity.InvalidDate.selector);
        extension.initializeClaim(address(creatorCore), 81, params);

        // Successful with no end date
        params.endDate = 0;
        extension.initializeClaim(address(creatorCore), 81, params);

        // Successful with no start date
        params.startDate = 0;
        params.endDate = later;
        extension.initializeClaim(address(creatorCore), 82, params);

        // Successful with no start or end date
        params.endDate = 0;
        extension.initializeClaim(address(creatorCore), 83, params);
    }

    function test_mintReserveInvalidCases() public {
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
            merkleRoot: bytes32(0),
            walletMax: 0
        });

        extension.initializeClaim(address(creatorCore), 90, params);

        // Test minting 0 tokens
        vm.expectRevert(ISerendipity.InvalidMintCount.selector);
        extension.mintReserve{value: 0}(
            address(creatorCore), 
            90, 
            0,
            new uint32[](0), // empty for non-merkle
            new bytes32[][](0), // empty for non-merkle
            address(0)
        );

        // Test minting too many tokens - will trigger InvalidPayment due to cost calculation
        vm.expectRevert(ISerendipity.InvalidPayment.selector);
        extension.mintReserve{value: 0}(
            address(creatorCore), 
            90, 
            uint16(MAX_UINT_32),
            new uint32[](0),
            new bytes32[][](0),
            address(0)
        );
    }

    function test_mintFromContract_reverts() public {
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
            walletMax: 0
        });

        extension.initializeClaim(address(creatorCore), 91, params);
        vm.stopPrank();

        // Deploy a contract that tries to mint
        MintingContract mintContract = new MintingContract(extension);
        vm.deal(address(mintContract), 1 ether);
        
        vm.expectRevert(ISerendipity.CannotMintFromContract.selector);
        mintContract.tryMint(address(creatorCore), 91);
    }

    function test_getClaimForToken() public {
        vm.startPrank(creator);
        
        IERC1155Serendipity.ClaimParameters memory params = IERC1155Serendipity.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.IPFS,
            totalMax: 100,
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + 1000),
            tokenVariations: 3,
            location: "ipfs-location",
            paymentReceiver: payable(creator),
            cost: 0,
            erc20: address(0),
            merkleRoot: merkleRoot,
            walletMax: 5
        });

        extension.initializeClaim(address(creatorCore), 95, params);
        
        IERC1155Serendipity.Claim memory claim = extension.getClaim(address(creatorCore), 95);
        uint256 startingTokenId = claim.startingTokenId;

        // Test getting claim for each token variation
        for (uint256 i = 0; i < 3; i++) {
            (uint256 instanceId, IERC1155Serendipity.Claim memory tokenClaim) = 
                extension.getClaimForToken(address(creatorCore), startingTokenId + i);
            
            assertEq(instanceId, 95);
            assertEq(tokenClaim.totalMax, 100);
            assertEq(tokenClaim.merkleRoot, merkleRoot);
            assertEq(tokenClaim.walletMax, 5);
        }

        // Test non-existent token
        vm.expectRevert(ISerendipity.ClaimNotInitialized.selector);
        extension.getClaimForToken(address(creatorCore), startingTokenId + 100);
    }

    function test_multipleCreatorContracts() public {
        vm.startPrank(creator);
        
        // Create claim on first creator contract
        IERC1155Serendipity.ClaimParameters memory params1 = IERC1155Serendipity.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 50,
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + 1000),
            tokenVariations: 2,
            location: "location1",
            paymentReceiver: payable(creator),
            cost: 0.01 ether,
            erc20: address(0),
            merkleRoot: merkleRoot,
            walletMax: 2
        });
        extension.initializeClaim(address(creatorCore), 100, params1);

        // Create claim on second creator contract with same instance ID
        IERC1155Serendipity.ClaimParameters memory params2 = IERC1155Serendipity.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.IPFS,
            totalMax: 100,
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + 2000),
            tokenVariations: 5,
            location: "location2",
            paymentReceiver: payable(bob),
            cost: 0.02 ether,
            erc20: address(0),
            merkleRoot: bytes32(0),
            walletMax: 10
        });
        extension.initializeClaim(address(creatorCore2), 100, params2);

        // Verify claims are independent
        IERC1155Serendipity.Claim memory claim1 = extension.getClaim(address(creatorCore), 100);
        IERC1155Serendipity.Claim memory claim2 = extension.getClaim(address(creatorCore2), 100);

        assertEq(claim1.totalMax, 50);
        assertEq(claim1.location, "location1");
        assertEq(claim1.merkleRoot, merkleRoot);
        
        assertEq(claim2.totalMax, 100);
        assertEq(claim2.location, "location2");
        assertEq(claim2.merkleRoot, bytes32(0));
        
        vm.stopPrank();

        // Test minting on each independently
        vm.startPrank(alice);
        uint32[] memory indices1 = new uint32[](1);
        indices1[0] = 0;
        bytes32[][] memory proofs1 = new bytes32[][](1);
        proofs1[0] = aliceProof;
        
        extension.mintReserve{value: 0.01 ether + MINT_FEE_MERKLE}(
            address(creatorCore), 
            100, 
            1,
            indices1,
            proofs1,
            address(0)
        );
        
        extension.mintReserve{value: 0.02 ether + MINT_FEE}(
            address(creatorCore2), 
            100, 
            1,
            new uint32[](0), // empty for non-merkle
            new bytes32[][](0), // empty for non-merkle
            address(0)
        );
        
        // Verify mints are tracked separately
        ISerendipity.UserMintDetails memory details1 = extension.getUserMints(alice, address(creatorCore), 100);
        ISerendipity.UserMintDetails memory details2 = extension.getUserMints(alice, address(creatorCore2), 100);
        
        assertEq(details1.reservedCount, 1);
        assertEq(details2.reservedCount, 1);
    }

    function test_invalidInstanceIds() public {
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
            walletMax: 0
        });

        // Test instance ID 0
        vm.expectRevert(ISerendipity.InvalidInstance.selector);
        extension.initializeClaim(address(creatorCore), 0, params);

        // Test instance ID > MAX_UINT_56
        vm.expectRevert(ISerendipity.InvalidInstance.selector);
        extension.initializeClaim(address(creatorCore), 2**56, params);

        // Valid instance ID at boundary should work
        extension.initializeClaim(address(creatorCore), 2**56 - 1, params);
    }

    function test_deliverMoreThanReserved_reverts() public {
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
            walletMax: 0
        });

        extension.initializeClaim(address(creatorCore), 110, params);
        
        // Alice reserves 2  
        vm.deal(creator, 10 ether);
        extension.mintReserve{value: MINT_FEE * 2}(
            address(creatorCore), 
            110, 
            2,
            new uint32[](0), // empty for non-merkle
            new bytes32[][](0), // empty for non-merkle
            address(0)
        );
        vm.stopPrank();

        // Try to deliver 3 (more than reserved)
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
            instanceId: 110,
            variationMints: variations
        });

        vm.expectRevert(ISerendipity.CannotMintMoreThanReserved.selector);
        extension.deliverMints(mints);
    }

    function test_invalidVariationIndex_reverts() public {
        vm.startPrank(creator);
        
        IERC1155Serendipity.ClaimParameters memory params = IERC1155Serendipity.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 100,
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + 1000),
            tokenVariations: 3,
            location: "test-location",
            paymentReceiver: payable(creator),
            cost: 0,
            erc20: address(0),
            merkleRoot: bytes32(0),
            walletMax: 0
        });

        extension.initializeClaim(address(creatorCore), 111, params);
        vm.deal(creator, 10 ether);
        extension.mintReserve{value: MINT_FEE}(
            address(creatorCore), 
            111, 
            1,
            new uint32[](0), // empty for non-merkle
            new bytes32[][](0), // empty for non-merkle
            address(0)
        );
        vm.stopPrank();

        vm.startPrank(signingAddress);
        
        // Test variation index 0 (invalid - should be 1-based)
        ISerendipity.VariationMint[] memory variations = new ISerendipity.VariationMint[](1);
        variations[0] = ISerendipity.VariationMint({
            variationIndex: 0,
            amount: 1,
            recipient: creator
        });
        ISerendipity.ClaimMint[] memory mints = new ISerendipity.ClaimMint[](1);
        mints[0] = ISerendipity.ClaimMint({
            creatorContractAddress: address(creatorCore),
            instanceId: 111,
            variationMints: variations
        });

        vm.expectRevert(ISerendipity.InvalidVariationIndex.selector);
        extension.deliverMints(mints);

        // Test variation index > tokenVariations
        variations[0].variationIndex = 4; // Only 3 variations allowed
        vm.expectRevert(ISerendipity.InvalidVariationIndex.selector);
        extension.deliverMints(mints);

        // Valid variation index should work
        variations[0].variationIndex = 2;
        extension.deliverMints(mints);
    }

    function test_claimAlreadyInitialized_reverts() public {
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
            walletMax: 0
        });

        // Initialize claim once
        extension.initializeClaim(address(creatorCore), 120, params);

        // Try to initialize same claim again
        vm.expectRevert(ISerendipity.ClaimAlreadyInitialized.selector);
        extension.initializeClaim(address(creatorCore), 120, params);
    }

    function test_updateNonExistentClaim_reverts() public {
        vm.startPrank(creator);
        
        IERC1155Serendipity.UpdateClaimParameters memory updateParams = IERC1155Serendipity.UpdateClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.IPFS,
            paymentReceiver: payable(bob),
            totalMax: 200,
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + 2000),
            cost: 0.02 ether,
            location: "updated-location",
            merkleRoot: merkleRoot,
            walletMax: 3
        });

        // Try to update non-existent claim
        vm.expectRevert(ISerendipity.ClaimNotInitialized.selector);
        extension.updateClaim(address(creatorCore), 999, updateParams);
    }

    // ============ MintIndex Security Tests ============

    function test_mintIndex_preventsMerkleProofReuse() public {
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
            walletMax: 10  // High wallet max to test mintIndex separately
        });

        extension.initializeClaim(address(creatorCore), 300, params);
        vm.stopPrank();

        // Alice successfully mints with mintIndex 0
        vm.startPrank(alice);
        uint256 totalCost = (0.01 ether + MINT_FEE_MERKLE);
        
        uint32[] memory indices = new uint32[](1);
        indices[0] = 0; // mintIndex 0 for alice
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = aliceProof;
        
        extension.mintReserve{value: totalCost}(
            address(creatorCore), 
            300, 
            1,
            indices,
            proofs,
            address(0)
        );

        // Alice tries to reuse the same mintIndex 0 - should fail
        vm.expectRevert(ISerendipity.InvalidMerkleProof.selector);
        extension.mintReserve{value: totalCost}(
            address(creatorCore), 
            300, 
            1,
            indices,
            proofs,
            address(0)
        );
        
        // Alice tries to use a different mintIndex that wasn't in her proof - should fail
        vm.expectRevert(ISerendipity.InvalidMerkleProof.selector);
        uint32[] memory wrongIndices = new uint32[](1);
        wrongIndices[0] = 1; // mintIndex 1 is for bob, not alice
        bytes32[][] memory wrongProofs = new bytes32[][](1);
        wrongProofs[0] = aliceProof;
        
        extension.mintReserve{value: totalCost}(
            address(creatorCore), 
            300, 
            1,
            wrongIndices,
            wrongProofs,
            address(0)
        );
        
        vm.stopPrank();
        
        // Verify alice only minted once
        ISerendipity.UserMintDetails memory details = extension.getUserMints(alice, address(creatorCore), 300);
        assertEq(details.reservedCount, 1);
    }

    function test_mintIndex_nonMerkleClaims() public {
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
            merkleRoot: bytes32(0),  // No merkle root
            walletMax: 5
        });

        extension.initializeClaim(address(creatorCore), 301, params);
        vm.stopPrank();

        vm.startPrank(alice);
        uint256 totalCost = (0.01 ether + MINT_FEE);
        
        // For non-merkle claims, use empty arrays
        extension.mintReserve{value: totalCost}(
            address(creatorCore), 
            301, 
            1,
            new uint32[](0), // empty for non-merkle
            new bytes32[][](0), // empty for non-merkle
            address(0)
        );
        
        // Verify mint succeeded
        ISerendipity.UserMintDetails memory details = extension.getUserMints(alice, address(creatorCore), 301);
        assertEq(details.reservedCount, 1);
        
        vm.stopPrank();
    }

    function test_mintIndex_allowsDifferentUsersWithTheirOwnIndices() public {
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
            walletMax: 5
        });

        extension.initializeClaim(address(creatorCore), 302, params);
        vm.stopPrank();

        // Alice mints with her mintIndex 0
        vm.startPrank(alice);
        uint32[] memory aliceIndices = new uint32[](1);
        aliceIndices[0] = 0;
        bytes32[][] memory aliceProofs = new bytes32[][](1);
        aliceProofs[0] = aliceProof;
        
        extension.mintReserve{value: 0.01 ether + MINT_FEE_MERKLE}(
            address(creatorCore), 
            302, 
            1,
            aliceIndices,
            aliceProofs,
            address(0)
        );
        vm.stopPrank();

        // Bob mints with his mintIndex 1
        vm.startPrank(bob);
        uint32[] memory bobIndices = new uint32[](1);
        bobIndices[0] = 1; // bob's mintIndex
        bytes32[][] memory bobProofs = new bytes32[][](1);
        bobProofs[0] = bobProof;
        
        extension.mintReserve{value: 0.01 ether + MINT_FEE_MERKLE}(
            address(creatorCore), 
            302, 
            1,
            bobIndices,
            bobProofs,
            address(0)
        );
        vm.stopPrank();

        // Charlie mints with his mintIndex 2
        vm.startPrank(charlie);
        uint32[] memory charlieIndices = new uint32[](1);
        charlieIndices[0] = 2; // charlie's mintIndex
        bytes32[][] memory charlieProofs = new bytes32[][](1);
        charlieProofs[0] = charlieProof;
        
        extension.mintReserve{value: 0.01 ether + MINT_FEE_MERKLE}(
            address(creatorCore), 
            302, 
            1,
            charlieIndices,
            charlieProofs,
            address(0)
        );
        vm.stopPrank();

        // Verify all three users minted successfully
        assertEq(extension.getUserMints(alice, address(creatorCore), 302).reservedCount, 1);
        assertEq(extension.getUserMints(bob, address(creatorCore), 302).reservedCount, 1);
        assertEq(extension.getUserMints(charlie, address(creatorCore), 302).reservedCount, 1);
        
        // Bob tries to reuse his mintIndex - should fail
        vm.startPrank(bob);
        vm.expectRevert(ISerendipity.InvalidMerkleProof.selector);
        extension.mintReserve{value: 0.01 ether + MINT_FEE_MERKLE}(
            address(creatorCore), 
            302, 
            1,
            bobIndices,
            bobProofs,
            address(0)
        );
        vm.stopPrank();
    }

    function test_totalMaxReached_handlesMultipleMinters() public {
        vm.startPrank(creator);
        
        IERC1155Serendipity.ClaimParameters memory params = IERC1155Serendipity.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: 3,
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

        extension.initializeClaim(address(creatorCore), 130, params);
        vm.stopPrank();

        // Alice mints 1
        vm.startPrank(alice);
        uint32[] memory aliceIdx = new uint32[](1);
        aliceIdx[0] = 0;
        bytes32[][] memory alicePrf = new bytes32[][](1);
        alicePrf[0] = aliceProof;
        
        extension.mintReserve{value: 0.01 ether + MINT_FEE_MERKLE}(
            address(creatorCore), 
            130, 
            1,
            aliceIdx,
            alicePrf,
            address(0)
        );
        vm.stopPrank();

        // Bob mints 1
        vm.startPrank(bob);
        uint32[] memory bobIdx = new uint32[](1);
        bobIdx[0] = 1;
        bytes32[][] memory bobPrf = new bytes32[][](1);
        bobPrf[0] = bobProof;
        
        extension.mintReserve{value: 0.01 ether + MINT_FEE_MERKLE}(
            address(creatorCore), 
            130, 
            1,
            bobIdx,
            bobPrf,
            address(0)
        );
        vm.stopPrank();

        // Charlie mints 1 (should reach max)
        vm.startPrank(charlie);
        uint32[] memory charlieIdx = new uint32[](1);
        charlieIdx[0] = 2;
        bytes32[][] memory charliePrf = new bytes32[][](1);
        charliePrf[0] = charlieProof;
        
        extension.mintReserve{value: 0.01 ether + MINT_FEE_MERKLE}(
            address(creatorCore), 
            130, 
            1,
            charlieIdx,
            charliePrf,
            address(0)
        );
        vm.stopPrank();

        // Alice tries to mint again (should fail - sold out)
        vm.startPrank(alice);
        vm.expectRevert(ISerendipity.ClaimSoldOut.selector);
        aliceIdx = new uint32[](1);
        aliceIdx[0] = 0;
        alicePrf = new bytes32[][](1);
        alicePrf[0] = aliceProof;
        
        extension.mintReserve{value: 0.01 ether + MINT_FEE_MERKLE}(
            address(creatorCore), 
            130, 
            1,
            aliceIdx,
            alicePrf,
            address(0)
        );
    }
}

// Helper contract to test contract minting restriction
contract MintingContract {
    ERC1155Serendipity public extension;
    
    constructor(ERC1155Serendipity _extension) {
        extension = _extension;
    }
    
    function tryMint(address creatorContract, uint256 instanceId) external {
        extension.mintReserve{value: MINT_FEE}(
            creatorContract, 
            instanceId, 
            1,
            new uint32[](0), // empty for non-merkle
            new bytes32[][](0), // empty for non-merkle
            address(0)
        );
    }
    
    uint256 constant MINT_FEE = 500000000000000;
}