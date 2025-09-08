// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/**
 * @title AllowlistTestHelpers
 * @notice Helper contract for generating and validating merkle trees in allowlist tests
 * @dev Used by ERC1155SerendipityWithAllowlist tests for comprehensive coverage
 */
contract AllowlistTestHelpers {
    /**
     * @notice Generate merkle root from array of addresses
     * @param addresses Array of allowlisted addresses
     * @return Root hash of the merkle tree
     */
    function generateMerkleRoot(address[] memory addresses) public pure returns (bytes32) {
        if (addresses.length == 0) return bytes32(0);
        
        bytes32[] memory leaves = new bytes32[](addresses.length);
        for (uint256 i = 0; i < addresses.length; i++) {
            leaves[i] = keccak256(abi.encode(addresses[i]));
        }
        
        // Simple merkle tree implementation
        uint256 n = leaves.length;
        while (n > 1) {
            uint256 newN = (n + 1) / 2;
            for (uint256 i = 0; i < newN; i++) {
                if (2 * i + 1 < n) {
                    leaves[i] = _hashPair(leaves[2 * i], leaves[2 * i + 1]);
                } else {
                    leaves[i] = leaves[2 * i];
                }
            }
            n = newN;
        }
        
        return leaves[0];
    }

    /**
     * @notice Generate merkle proof for specific address
     * @param addresses Array of allowlisted addresses
     * @param targetAddress Address to generate proof for
     * @return Merkle proof as array of bytes32
     */
    function generateMerkleProof(address[] memory addresses, address targetAddress)
        public
        pure
        returns (bytes32[] memory)
    {
        if (addresses.length == 0) return new bytes32[](0);
        
        bytes32[] memory leaves = new bytes32[](addresses.length);
        uint256 targetIndex = type(uint256).max;

        for (uint256 i = 0; i < addresses.length; i++) {
            leaves[i] = keccak256(abi.encode(addresses[i]));
            if (addresses[i] == targetAddress) {
                targetIndex = i;
            }
        }

        require(targetIndex != type(uint256).max, "Target address not in allowlist");
        
        // Simple proof generation
        uint256 proofLength = 0;
        uint256 n = leaves.length;
        while (n > 1) {
            proofLength++;
            n = (n + 1) / 2;
        }
        
        bytes32[] memory proof = new bytes32[](proofLength);
        uint256 proofIndex = 0;
        uint256 currentIndex = targetIndex;
        n = leaves.length;
        
        bytes32[] memory currentLevel = new bytes32[](n);
        for (uint256 i = 0; i < n; i++) {
            currentLevel[i] = leaves[i];
        }
        
        while (n > 1) {
            uint256 siblingIndex = currentIndex % 2 == 0 ? currentIndex + 1 : currentIndex - 1;
            if (siblingIndex < n) {
                proof[proofIndex++] = currentLevel[siblingIndex];
            }
            
            uint256 newN = (n + 1) / 2;
            bytes32[] memory newLevel = new bytes32[](newN);
            for (uint256 i = 0; i < newN; i++) {
                if (2 * i + 1 < n) {
                    newLevel[i] = _hashPair(currentLevel[2 * i], currentLevel[2 * i + 1]);
                } else {
                    newLevel[i] = currentLevel[2 * i];
                }
            }
            
            currentIndex = currentIndex / 2;
            currentLevel = newLevel;
            n = newN;
        }
        
        // Trim proof array if needed
        bytes32[] memory finalProof = new bytes32[](proofIndex);
        for (uint256 i = 0; i < proofIndex; i++) {
            finalProof[i] = proof[i];
        }
        
        return finalProof;
    }

    /**
     * @notice Verify merkle proof for an address
     * @param proof Merkle proof to verify
     * @param root Merkle root to verify against
     * @param targetAddress Address being verified
     * @return True if proof is valid, false otherwise
     */
    function verifyMerkleProof(bytes32[] memory proof, bytes32 root, address targetAddress)
        public
        pure
        returns (bool)
    {
        bytes32 leaf = keccak256(abi.encode(targetAddress));
        bytes32 computedHash = leaf;
        
        for (uint256 i = 0; i < proof.length; i++) {
            computedHash = _hashPair(computedHash, proof[i]);
        }
        
        return computedHash == root;
    }

    /**
     * @notice Generate test allowlist with common test addresses
     * @param includeAlice Whether to include alice in allowlist
     * @param includeBob Whether to include bob in allowlist
     * @param includeCharlie Whether to include charlie in allowlist
     * @return Array of allowlisted addresses
     */
    function generateTestAllowlist(bool includeAlice, bool includeBob, bool includeCharlie)
        public
        pure
        returns (address[] memory)
    {
        uint256 count = 0;
        if (includeAlice) count++;
        if (includeBob) count++;
        if (includeCharlie) count++;

        address[] memory allowlist = new address[](count);
        uint256 index = 0;

        if (includeAlice) {
            allowlist[index++] = 0x5174cD462b60c536eb51D4ceC1D561D3Ea31004F; // alice
        }
        if (includeBob) {
            allowlist[index++] = 0x80AAC46bbd3C2FcE33681541a52CacBEd14bF425; // bob
        }
        if (includeCharlie) {
            allowlist[index++] = 0x1234567890123456789012345678901234567890; // charlie
        }

        return allowlist;
    }

    /**
     * @notice Generate large allowlist for stress testing
     * @param size Number of addresses to generate
     * @param seedOffset Offset for deterministic generation
     * @return Array of generated addresses
     */
    function generateLargeAllowlist(uint256 size, uint256 seedOffset)
        public
        pure
        returns (address[] memory)
    {
        address[] memory allowlist = new address[](size);
        for (uint256 i = 0; i < size; i++) {
            allowlist[i] = address(uint160(uint256(keccak256(abi.encode(i + seedOffset)))));
        }
        return allowlist;
    }

    /**
     * @notice Generate invalid proof for negative testing
     * @param validProof Valid proof to modify
     * @return Modified proof that should fail verification
     */
    function generateInvalidProof(bytes32[] memory validProof) 
        public 
        pure 
        returns (bytes32[] memory) 
    {
        if (validProof.length == 0) {
            bytes32[] memory emptyInvalidProof = new bytes32[](1);
            emptyInvalidProof[0] = keccak256("invalid");
            return emptyInvalidProof;
        }
        
        bytes32[] memory invalidProof = new bytes32[](validProof.length);
        for (uint256 i = 0; i < validProof.length; i++) {
            invalidProof[i] = validProof[i];
        }
        // Modify the first element to make proof invalid
        invalidProof[0] = keccak256(abi.encode("invalid", invalidProof[0]));
        return invalidProof;
    }
    
    /**
     * @notice Hash pair of nodes for merkle tree
     * @dev Sorts the pair before hashing to ensure consistency
     */
    function _hashPair(bytes32 a, bytes32 b) private pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }
}