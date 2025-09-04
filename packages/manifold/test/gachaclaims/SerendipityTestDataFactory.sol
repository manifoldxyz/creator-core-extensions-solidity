// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../contracts/gachaclaims/IERC1155Serendipity.sol";
import "../../contracts/gachaclaims/ISerendipity.sol";

/**
 * @title SerendipityTestDataFactory
 * @notice Factory contract for generating test data and fixtures
 * @dev Provides standardized test data for serendipity allowlist testing
 */
library SerendipityTestDataFactory {
    // ============ Test Constants ============
    uint256 public constant DEFAULT_COST = 0.01 ether;
    uint256 public constant HIGH_COST = 1 ether;
    uint256 public constant MINT_FEE = 500000000000000;
    
    uint48 public constant DEFAULT_DURATION = 1000;
    uint48 public constant SHORT_DURATION = 100;
    uint48 public constant LONG_DURATION = 10000;
    
    uint256 public constant SMALL_SUPPLY = 10;
    uint256 public constant MEDIUM_SUPPLY = 100;
    uint256 public constant LARGE_SUPPLY = 1000;
    uint256 public constant UNLIMITED_SUPPLY = 0;

    // ============ Test Addresses ============
    address public constant CREATOR = 0xc78Dc443c126af6E4f6Ed540c1e740C1b5be09cd;
    address public constant OWNER = 0x6140F00e4Ff3936702E68744f2b5978885464cbB;
    address public constant SIGNING_ADDRESS = 0xc78dC443c126Af6E4f6eD540C1E740c1B5be09CE;
    address public constant ALICE = 0x5174cD462b60c536eb51D4ceC1D561D3Ea31004F;
    address public constant BOB = 0x80AAC46bbd3C2FcE33681541a52CacBEd14bF425;
    address public constant CHARLIE = 0x1234567890123456789012345678901234567890;
    address public constant UNAUTHORIZED = 0x9876543210987654321098765432109876543210;

    /**
     * @notice Create basic claim parameters with reasonable defaults
     * @return ClaimParameters struct with default values
     */
    function createBasicClaimParameters() internal view returns (IERC1155Serendipity.ClaimParameters memory) {
        return IERC1155Serendipity.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: uint32(MEDIUM_SUPPLY),
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + DEFAULT_DURATION),
            tokenVariations: 5,
            location: "test-arweave-hash",
            paymentReceiver: payable(CREATOR),
            cost: uint96(DEFAULT_COST),
            erc20: address(0)
        });
    }

    /**
     * @notice Create claim parameters for testing expiry
     * @param isExpired Whether claim should be expired
     * @return ClaimParameters struct configured for expiry testing
     */
    function createExpiryTestClaimParameters(bool isExpired) 
        internal 
        view 
        returns (IERC1155Serendipity.ClaimParameters memory) 
    {
        uint48 startDate;
        uint48 endDate;
        
        if (isExpired) {
            startDate = uint48(block.timestamp - DEFAULT_DURATION * 2);
            endDate = uint48(block.timestamp - DEFAULT_DURATION);
        } else {
            startDate = uint48(block.timestamp - DEFAULT_DURATION);
            endDate = uint48(block.timestamp + DEFAULT_DURATION);
        }

        return IERC1155Serendipity.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: uint32(SMALL_SUPPLY),
            startDate: startDate,
            endDate: endDate,
            tokenVariations: 3,
            location: "expiry-test-hash",
            paymentReceiver: payable(CREATOR),
            cost: uint96(DEFAULT_COST),
            erc20: address(0)
        });
    }

    /**
     * @notice Create claim parameters for testing supply limits
     * @param supplyType Type of supply limit to test
     * @return ClaimParameters struct configured for supply testing
     */
    function createSupplyTestClaimParameters(SupplyType supplyType) 
        internal 
        view 
        returns (IERC1155Serendipity.ClaimParameters memory) 
    {
        uint256 totalMax;
        
        if (supplyType == SupplyType.UNLIMITED) {
            totalMax = UNLIMITED_SUPPLY;
        } else if (supplyType == SupplyType.SMALL) {
            totalMax = SMALL_SUPPLY;
        } else if (supplyType == SupplyType.MEDIUM) {
            totalMax = MEDIUM_SUPPLY;
        } else {
            totalMax = LARGE_SUPPLY;
        }

        return IERC1155Serendipity.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.ARWEAVE,
            totalMax: uint32(totalMax),
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + DEFAULT_DURATION),
            tokenVariations: 5,
            location: "supply-test-hash",
            paymentReceiver: payable(CREATOR),
            cost: uint96(DEFAULT_COST),
            erc20: address(0)
        });
    }

    /**
     * @notice Create claim parameters for ERC20 payment testing
     * @param erc20Token Address of ERC20 token
     * @param cost Cost in ERC20 tokens
     * @return ClaimParameters struct configured for ERC20 testing
     */
    function createERC20ClaimParameters(address erc20Token, uint256 cost) 
        internal 
        view 
        returns (IERC1155Serendipity.ClaimParameters memory) 
    {
        return IERC1155Serendipity.ClaimParameters({
            storageProtocol: ISerendipity.StorageProtocol.IPFS,
            totalMax: uint32(MEDIUM_SUPPLY),
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + DEFAULT_DURATION),
            tokenVariations: 5,
            location: "erc20-test-hash",
            paymentReceiver: payable(CREATOR),
            cost: uint96(cost),
            erc20: erc20Token
        });
    }

    /**
     * @notice Create claim parameters with custom storage protocol
     * @param protocol Storage protocol to use
     * @param location Storage location
     * @return ClaimParameters struct with custom storage
     */
    function createStorageTestClaimParameters(ISerendipity.StorageProtocol protocol, string memory location) 
        internal 
        view 
        returns (IERC1155Serendipity.ClaimParameters memory) 
    {
        return IERC1155Serendipity.ClaimParameters({
            storageProtocol: protocol,
            totalMax: uint32(MEDIUM_SUPPLY),
            startDate: uint48(block.timestamp),
            endDate: uint48(block.timestamp + DEFAULT_DURATION),
            tokenVariations: 5,
            location: location,
            paymentReceiver: payable(CREATOR),
            cost: uint96(DEFAULT_COST),
            erc20: address(0)
        });
    }

    /**
     * @notice Create variation mints for delivery testing
     * @param recipient Address to receive mints
     * @param variationCount Number of different variations
     * @param amountPerVariation Amount of each variation
     * @return Array of VariationMint structs
     */
    function createVariationMints(
        address recipient, 
        uint256 variationCount, 
        uint256 amountPerVariation
    ) internal pure returns (ISerendipity.VariationMint[] memory) {
        ISerendipity.VariationMint[] memory variations = new ISerendipity.VariationMint[](variationCount);
        
        for (uint256 i = 0; i < variationCount; i++) {
            variations[i] = ISerendipity.VariationMint({
                variationIndex: uint8(i + 1), // 1-based indexing
                amount: uint32(amountPerVariation),
                recipient: recipient
            });
        }
        
        return variations;
    }

    /**
     * @notice Create claim mint for delivery testing
     * @param creatorContract Creator contract address
     * @param instanceId Claim instance ID
     * @param variations Array of variation mints
     * @return ClaimMint struct for delivery
     */
    function createClaimMint(
        address creatorContract,
        uint256 instanceId,
        ISerendipity.VariationMint[] memory variations
    ) internal pure returns (ISerendipity.ClaimMint memory) {
        return ISerendipity.ClaimMint({
            creatorContractAddress: creatorContract,
            instanceId: instanceId,
            variationMints: variations
        });
    }

    /**
     * @notice Create batch delivery for multiple users
     * @param creatorContract Creator contract address
     * @param instanceId Claim instance ID
     * @param recipients Array of recipient addresses
     * @param amounts Array of amounts for each recipient
     * @return Array of ClaimMint structs for batch delivery
     */
    function createBatchDelivery(
        address creatorContract,
        uint256 instanceId,
        address[] memory recipients,
        uint256[] memory amounts
    ) internal pure returns (ISerendipity.ClaimMint[] memory) {
        require(recipients.length == amounts.length, "Mismatched arrays");
        
        ISerendipity.ClaimMint[] memory mints = new ISerendipity.ClaimMint[](recipients.length);
        
        for (uint256 i = 0; i < recipients.length; i++) {
            ISerendipity.VariationMint[] memory variations = new ISerendipity.VariationMint[](1);
            variations[0] = ISerendipity.VariationMint({
                variationIndex: uint8((i % 5) + 1), // Distribute across 5 variations
                amount: uint32(amounts[i]),
                recipient: recipients[i]
            });
            
            mints[i] = createClaimMint(creatorContract, instanceId, variations);
        }
        
        return mints;
    }

    /**
     * @notice Get test addresses array
     * @param includeUnauthorized Whether to include unauthorized address
     * @return Array of test addresses
     */
    function getTestAddresses(bool includeUnauthorized) internal pure returns (address[] memory) {
        uint256 length = includeUnauthorized ? 4 : 3;
        address[] memory addresses = new address[](length);
        
        addresses[0] = ALICE;
        addresses[1] = BOB;
        addresses[2] = CHARLIE;
        
        if (includeUnauthorized) {
            addresses[3] = UNAUTHORIZED;
        }
        
        return addresses;
    }

    /**
     * @notice Generate edge case parameters for stress testing
     * @param caseType Type of edge case to generate
     * @return ClaimParameters struct with edge case values
     */
    function createEdgeCaseClaimParameters(EdgeCaseType caseType) 
        internal 
        view 
        returns (IERC1155Serendipity.ClaimParameters memory) 
    {
        IERC1155Serendipity.ClaimParameters memory params = createBasicClaimParameters();
        
        if (caseType == EdgeCaseType.MAX_VALUES) {
            params.totalMax = type(uint32).max;
            params.tokenVariations = type(uint8).max;
            params.cost = type(uint96).max;
            params.endDate = type(uint48).max;
        } else if (caseType == EdgeCaseType.MIN_VALUES) {
            params.totalMax = 1;
            params.tokenVariations = 1;
            params.cost = 1;
            params.startDate = uint48(block.timestamp + 1);
        } else if (caseType == EdgeCaseType.ZERO_VALUES) {
            params.totalMax = 0;
            params.cost = 0;
            params.startDate = 0;
            params.endDate = 0;
        }
        
        return params;
    }

    // ============ Enums ============
    enum SupplyType {
        UNLIMITED,
        SMALL,
        MEDIUM,
        LARGE
    }

    enum EdgeCaseType {
        MAX_VALUES,
        MIN_VALUES,
        ZERO_VALUES
    }
}