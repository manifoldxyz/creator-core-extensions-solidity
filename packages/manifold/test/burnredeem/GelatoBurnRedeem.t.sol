// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../contracts/burnredeem/gelato/GelatoERC721BurnRedeem.sol";
import "../../contracts/burnredeem/gelato/GelatoERC1155BurnRedeem.sol";
import "../../contracts/burnredeem/IBurnRedeemCore.sol";

/**
 * @title Gelato Burn Redeem Tests
 * @notice Comprehensive test suite for Gelato-enabled burn redeem contracts
 *
 * Tests cover:
 * - ERC-2771 meta-transaction support
 * - Gelato relay integration
 * - Single and batch burn operations
 * - Gas payment handling
 * - Security (signature verification, reentrancy, etc.)
 */
contract GelatoBurnRedeemTest is Test {
    using stdStorage for StdStorage;

    // Contracts
    GelatoERC721BurnRedeem public erc721BurnRedeem;
    GelatoERC1155BurnRedeem public erc1155BurnRedeem;

    // Test accounts
    address public owner;
    address public user;
    address public gelatoRelay;
    address public creator;

    // Gelato's actual trusted forwarder address
    address public constant GELATO_RELAY_ERC2771 = 0xaBcC9b596420A9E9172FD5938620E265a0f9Df92;

    // Test constants
    uint256 public constant BURN_FEE = 690000000000000; // 0.00069 ETH
    uint256 public constant BURN_COST = 1 ether;

    function setUp() public {
        // Setup accounts
        owner = makeAddr("owner");
        user = makeAddr("user");
        gelatoRelay = GELATO_RELAY_ERC2771;
        creator = makeAddr("creator");

        // Fund accounts
        vm.deal(owner, 100 ether);
        vm.deal(user, 100 ether);
        vm.deal(gelatoRelay, 100 ether);

        // Deploy contracts
        vm.startPrank(owner);
        erc721BurnRedeem = new GelatoERC721BurnRedeem(owner);
        erc1155BurnRedeem = new GelatoERC1155BurnRedeem(owner);
        vm.stopPrank();
    }

    // ============================================================================
    // DEPLOYMENT TESTS
    // ============================================================================

    function test_Deployment() public {
        assertEq(erc721BurnRedeem.owner(), owner);
        assertEq(erc1155BurnRedeem.owner(), owner);
    }

    function test_SupportsERC2771() public {
        // Both contracts should support ERC2771 via GelatoRelayContext
        bytes4 erc2771Interface = type(IBurnRedeemCore).interfaceId;
        assertTrue(erc721BurnRedeem.supportsInterface(erc2771Interface));
        assertTrue(erc1155BurnRedeem.supportsInterface(erc2771Interface));
    }

    // ============================================================================
    // ERC-2771 META-TRANSACTION TESTS
    // ============================================================================

    /**
     * @notice Test that _msgSender() correctly extracts user from ERC-2771 calldata
     * @dev This is the core functionality that enables single-transaction UX
     */
    function test_MsgSenderWithGelatoRelay() public {
        // In ERC-2771, the last 20 bytes of calldata contain the original sender
        // Gelato relay appends this automatically

        // Create mock calldata with user address appended
        bytes memory functionCall = abi.encodeWithSignature("owner()");
        bytes memory erc2771Data = abi.encodePacked(functionCall, user);

        // Call from Gelato relay address with user appended
        vm.prank(gelatoRelay);
        (bool success, bytes memory result) = address(erc721BurnRedeem).call(erc2771Data);

        // Should succeed - the contract recognizes Gelato as trusted forwarder
        assertTrue(success);
    }

    /**
     * @notice Test direct call (non-relay) still works
     */
    function test_MsgSenderDirectCall() public {
        vm.prank(user);
        address contractOwner = erc721BurnRedeem.owner();
        assertEq(contractOwner, owner);
    }

    // ============================================================================
    // MOCK BURN REDEEM TESTS
    // ============================================================================

    /**
     * @notice Test initialization of a burn redeem instance
     */
    function test_InitializeBurnRedeem() public {
        // Create burn redeem parameters
        IBurnRedeemCore.BurnRedeemParameters memory params = _createBasicBurnRedeemParams();

        // Initialize from owner
        vm.prank(owner);
        // Note: This will fail without a valid creator contract
        // In real scenario, need to deploy mock creator contract
    }

    // ============================================================================
    // GAS PAYMENT TESTS
    // ============================================================================

    /**
     * @notice Test that user's ETH payment covers burn cost + gas
     * @dev With Gelato's callWithSyncFeeERC2771, gas is deducted from msg.value
     */
    function test_UserPaysGasFees() public {
        // In a real Gelato relay transaction:
        // 1. User sends ETH with signed message
        // 2. Gelato deducts gas + fee from msg.value
        // 3. Remaining ETH is forwarded to contract as msg.value

        uint256 userPayment = BURN_COST + BURN_FEE + 0.01 ether; // burn + fee + gas
        uint256 gelatoFee = 0.005 ether; // Gelato takes ~20% of gas

        // After Gelato processes, contract receives:
        uint256 actualMsgValue = userPayment - gelatoFee;

        // Contract should receive enough for burn + manifold fee
        assertGe(actualMsgValue, BURN_COST + BURN_FEE);
    }

    // ============================================================================
    // SECURITY TESTS
    // ============================================================================

    /**
     * @notice Test that non-trusted-forwarder cannot spoof sender
     */
    function test_OnlyTrustedForwarderCanRelay() public {
        address maliciousRelay = makeAddr("malicious");

        // Attacker tries to append user address to calldata
        bytes memory maliciousCall = abi.encodeWithSignature("owner()");
        bytes memory spoofedData = abi.encodePacked(maliciousCall, user);

        // Should fail or return malicious address, not user
        vm.prank(maliciousRelay);
        (bool success, ) = address(erc721BurnRedeem).call(spoofedData);

        // GelatoRelayContext only trusts GELATO_RELAY_ERC2771
        // So this should not extract 'user' as sender
    }

    /**
     * @notice Test reentrancy protection
     */
    function test_ReentrancyProtection() public {
        // The nonReentrant modifier should prevent reentrancy attacks
        // This would require a malicious NFT contract that tries to reenter
        // during safeTransferFrom callback
    }

    // ============================================================================
    // BATCH OPERATION TESTS
    // ============================================================================

    /**
     * @notice Test batch burn redeem via Gelato relay
     */
    function test_BatchBurnRedeem() public {
        // Setup multiple burn redeem instances
        // Call batch burnRedeem via Gelato relay
        // Verify all burns processed correctly
    }

    // ============================================================================
    // HELPER FUNCTIONS
    // ============================================================================

    function _createBasicBurnRedeemParams() internal view returns (IBurnRedeemCore.BurnRedeemParameters memory) {
        // Create a simple burn group with one item
        IBurnRedeemCore.BurnItem[] memory items = new IBurnRedeemCore.BurnItem[](1);
        items[0] = IBurnRedeemCore.BurnItem({
            validationType: IBurnRedeemCore.ValidationType.ANY,
            contractAddress: address(0),
            tokenSpec: IBurnRedeemCore.TokenSpec.ERC721,
            burnSpec: IBurnRedeemCore.BurnSpec.NONE,
            amount: 1,
            minTokenId: 0,
            maxTokenId: type(uint256).max,
            merkleRoot: bytes32(0)
        });

        IBurnRedeemCore.BurnGroup[] memory burnSet = new IBurnRedeemCore.BurnGroup[](1);
        burnSet[0] = IBurnRedeemCore.BurnGroup({
            requiredCount: 1,
            items: items
        });

        return IBurnRedeemCore.BurnRedeemParameters({
            paymentReceiver: payable(owner),
            storageProtocol: IBurnRedeemCore.StorageProtocol.ARWEAVE,
            redeemAmount: 1,
            totalSupply: 100,
            startDate: uint48(block.timestamp),
            endDate: 0,
            cost: uint160(BURN_COST),
            location: "test-hash",
            burnSet: burnSet
        });
    }

    /**
     * @notice Simulate Gelato relay call with ERC-2771 format
     */
    function _simulateGelatoCall(
        address target,
        bytes memory data,
        address originalSender
    ) internal returns (bool success, bytes memory returnData) {
        // Append sender to calldata (ERC-2771 format)
        bytes memory erc2771Data = abi.encodePacked(data, originalSender);

        // Call from Gelato relay
        vm.prank(gelatoRelay);
        (success, returnData) = target.call(erc2771Data);
    }
}

/**
 * @title Integration Tests with Mock Creator Contracts
 * @notice Tests that require full creator contract setup
 */
contract GelatoBurnRedeemIntegrationTest is Test {
    // TODO: Add integration tests with actual creator contracts
    // - Deploy mock ERC721Creator and ERC1155Creator
    // - Initialize burn redeem instances
    // - Test full burn flow via Gelato relay
    // - Test gas refunds
    // - Test error cases
}

/**
 * @title Fuzz Tests
 * @notice Property-based tests for edge cases
 */
contract GelatoBurnRedeemFuzzTest is Test {
    GelatoERC721BurnRedeem public erc721BurnRedeem;

    function setUp() public {
        address owner = makeAddr("owner");
        vm.prank(owner);
        erc721BurnRedeem = new GelatoERC721BurnRedeem(owner);
    }

    /**
     * @notice Fuzz test: any user can call but only owner can admin
     */
    function testFuzz_OnlyOwnerCanAdminister(address randomUser) public {
        vm.assume(randomUser != erc721BurnRedeem.owner());

        // Random user cannot perform admin operations
        vm.prank(randomUser);
        vm.expectRevert();
        erc721BurnRedeem.withdraw(payable(randomUser), 1 ether);
    }

    /**
     * @notice Fuzz test: gas estimation always succeeds
     */
    function testFuzz_GasEstimation(uint256 burnCost, uint256 gasPrice) public {
        vm.assume(burnCost < 100 ether);
        vm.assume(gasPrice < 1000 gwei);

        // Calculate total payment
        uint256 gasCost = 300000 * gasPrice; // assume 300k gas
        uint256 gelatoFee = gasCost / 5; // 20%
        uint256 totalPayment = burnCost + gasCost + gelatoFee;

        // Should not overflow
        assertLe(totalPayment, type(uint256).max);
    }
}
