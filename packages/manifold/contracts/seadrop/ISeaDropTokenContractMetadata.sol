// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

/// @author: manifold.xyz

import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";

/**
 * @notice Local mirror of stock SeaDrop's ISeaDropTokenContractMetadata.
 * @dev Used by the shim ONLY for interfaceId computation — the shim claims
 *      support for this interface in supportsInterface so OpenSea's drop-page
 *      indexer recognises the contract as a SeaDrop-compatible metadata
 *      source. Method signatures + struct layouts must mirror the canonical
 *      ProjectOpenSea/seadrop interface verbatim so type(...).interfaceId
 *      matches the value SeaDrop callers expect; pinning against the
 *      deployed bytecode is tracked under US-022.
 *
 *      The shim does NOT implement every method declared here:
 *        - setBaseURI / setProvenanceHash / setRoyaltyInfo / royaltyAddress /
 *          royaltyBasisPoints are intentionally not exposed (v1 non-goals:
 *          baseURI is a fixed empty string, provenanceHash is disabled,
 *          royalties live off-chain in the OpenSea creator-earnings UI).
 *      Calls to those selectors will revert at the Solidity dispatcher.
 */
interface ISeaDropTokenContractMetadata is IERC2981 {
    /// @dev Royalty record stored alongside the contract metadata.
    struct RoyaltyInfo {
        address royaltyAddress;
        uint96 royaltyBps;
    }

    function setBaseURI(string calldata tokenURI) external;

    function setContractURI(string calldata newContractURI) external;

    function setMaxSupply(uint256 newMaxSupply) external;

    function setProvenanceHash(bytes32 newProvenanceHash) external;

    function setRoyaltyInfo(RoyaltyInfo calldata newInfo) external;

    function baseURI() external view returns (string memory);

    function contractURI() external view returns (string memory);

    function maxSupply() external view returns (uint256);

    function provenanceHash() external view returns (bytes32);

    function royaltyAddress() external view returns (address);

    function royaltyBasisPoints() external view returns (uint256);
}
