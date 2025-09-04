// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title MockRandomnessService
 * @notice Mock contract for testing randomness-based delivery mechanisms
 * @dev Provides deterministic "randomness" for testing serendipity delivery
 */
contract MockRandomnessService {
    mapping(bytes32 => uint256) private _randomNumbers;
    mapping(address => bool) private _authorizedCallers;
    
    address public owner;
    uint256 private _nonce;
    bool public deterministicMode = true;

    event RandomnessRequested(bytes32 indexed requestId, address indexed requester);
    event RandomnessDelivered(bytes32 indexed requestId, uint256 randomNumber);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier onlyAuthorized() {
        require(_authorizedCallers[msg.sender] || msg.sender == owner, "Not authorized");
        _;
    }

    constructor() {
        owner = msg.sender;
        _authorizedCallers[msg.sender] = true;
    }

    /**
     * @notice Set authorized caller for testing
     * @param caller Address to authorize
     * @param authorized Whether the caller is authorized
     */
    function setAuthorizedCaller(address caller, bool authorized) external onlyOwner {
        _authorizedCallers[caller] = authorized;
    }

    /**
     * @notice Toggle deterministic mode for testing
     * @param _deterministicMode Whether to use deterministic randomness
     */
    function setDeterministicMode(bool _deterministicMode) external onlyOwner {
        deterministicMode = _deterministicMode;
    }

    /**
     * @notice Request random number for delivery
     * @param seed Seed for randomness generation
     * @return requestId Unique identifier for the request
     */
    function requestRandomness(uint256 seed) external onlyAuthorized returns (bytes32) {
        bytes32 requestId = keccak256(abi.encode(msg.sender, seed, _nonce++));
        
        uint256 randomNumber;
        if (deterministicMode) {
            // Generate deterministic but varied numbers for testing
            randomNumber = uint256(keccak256(abi.encode(seed, block.timestamp, requestId))) % 1000;
        } else {
            // Use blockhash for pseudo-randomness in tests
            randomNumber = uint256(keccak256(abi.encode(blockhash(block.number - 1), requestId)));
        }

        _randomNumbers[requestId] = randomNumber;
        
        emit RandomnessRequested(requestId, msg.sender);
        emit RandomnessDelivered(requestId, randomNumber);
        
        return requestId;
    }

    /**
     * @notice Get random number for a request
     * @param requestId Request identifier
     * @return Random number generated for the request
     */
    function getRandomNumber(bytes32 requestId) external view returns (uint256) {
        return _randomNumbers[requestId];
    }

    /**
     * @notice Set specific random number for testing
     * @param requestId Request identifier
     * @param randomNumber Number to set
     */
    function setRandomNumber(bytes32 requestId, uint256 randomNumber) external onlyOwner {
        _randomNumbers[requestId] = randomNumber;
    }

    /**
     * @notice Generate multiple random numbers for batch testing
     * @param count Number of random numbers to generate
     * @param baseSeed Base seed for generation
     * @return Array of random numbers
     */
    function generateBatchRandomness(uint256 count, uint256 baseSeed) 
        external 
        onlyAuthorized 
        returns (uint256[] memory) 
    {
        uint256[] memory randomNumbers = new uint256[](count);
        
        for (uint256 i = 0; i < count; i++) {
            if (deterministicMode) {
                randomNumbers[i] = uint256(keccak256(abi.encode(baseSeed, i, _nonce++))) % 1000;
            } else {
                randomNumbers[i] = uint256(keccak256(abi.encode(blockhash(block.number - 1), baseSeed, i)));
            }
        }
        
        return randomNumbers;
    }

    /**
     * @notice Generate variation index based on random number and total variations
     * @param randomNumber Random number from service
     * @param totalVariations Total number of token variations
     * @return Variation index (1-based)
     */
    function getVariationIndex(uint256 randomNumber, uint256 totalVariations) 
        external 
        pure 
        returns (uint256) 
    {
        require(totalVariations > 0, "No variations available");
        return (randomNumber % totalVariations) + 1;
    }

    /**
     * @notice Simulate weighted random selection for rarity testing
     * @param randomNumber Random number from service
     * @param weights Array of weights for each variation
     * @return Selected variation index (0-based in weights array)
     */
    function getWeightedVariationIndex(uint256 randomNumber, uint256[] memory weights)
        external
        pure
        returns (uint256)
    {
        require(weights.length > 0, "No weights provided");
        
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < weights.length; i++) {
            totalWeight += weights[i];
        }
        require(totalWeight > 0, "Total weight must be positive");

        uint256 randomValue = randomNumber % totalWeight;
        uint256 cumulativeWeight = 0;

        for (uint256 i = 0; i < weights.length; i++) {
            cumulativeWeight += weights[i];
            if (randomValue < cumulativeWeight) {
                return i;
            }
        }

        // Fallback to last index (should not happen)
        return weights.length - 1;
    }

    /**
     * @notice Check if request exists
     * @param requestId Request identifier
     * @return True if request exists
     */
    function requestExists(bytes32 requestId) external view returns (bool) {
        return _randomNumbers[requestId] != 0;
    }
}