// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

/// @author: manifold.xyz

/**
 * @notice Local mirror of stock SeaDrop's ISeaDropTokenContractMetadata.
 * @dev Aligned with the deployed SeaDrop — 8 functions, no IERC2981
 *      inheritance. Used by the shim ONLY for interfaceId computation: the
 *      shim claims this interface in supportsInterface so OpenSea's drop-page
 *      indexer recognises the contract as a SeaDrop-compatible metadata
 *      source. Method signatures + struct layouts must mirror the canonical
 *      deployed interface verbatim so type(...).interfaceId resolves to
 *      0x37c62e4e — the value SeaDrop / OpenSea consumers expect. The unit
 *      test `testInterfaceIdsMatchUpstreamSeaDrop` pins this bytes4 against
 *      the local mirror to catch any future drift.
 */
interface ISeaDropTokenContractMetadata {
    /// @dev Thrown by setProvenanceHash after a mint has occurred.
    error ProvenanceHashCannotBeSetAfterMintStarted();

    /// @dev Emitted when the max token supply cap changes.
    event MaxSupplyUpdated(uint256 newMaxSupply);

    /// @dev Emitted when the provenance hash is set (single write allowed).
    event ProvenanceHashUpdated(bytes32 previousHash, bytes32 newHash);

    /// @dev Emitted when the collection-level metadata URI changes. Carries
    ///      the new URI so indexers can avoid a follow-up read.
    event ContractURIUpdated(string newContractURI);

    /// @dev Indexed metadata refresh range — emitted by stock SeaDrop metadata
    ///      setters and this shim's single-token metadata setters for OpenSea
    ///      / EIP-4906 cache invalidation.
    event BatchMetadataUpdate(uint256 fromTokenId, uint256 toTokenId);

    /// @dev Emitted when the token URI changes in the deployed SeaDrop
    ///      metadata interface. Declared here for canonical-interface fidelity.
    event TokenURIUpdated(uint256 indexed startTokenId, uint256 indexed endTokenId);

    /// @dev Emitted when the base URI changes in the deployed SeaDrop
    ///      metadata interface. Declared here for canonical-interface fidelity.
    event BaseURIUpdated(string baseURI);

    function contractURI() external view returns (string memory);

    function setContractURI(string calldata newContractURI) external;

    function baseURI() external view returns (string memory);

    function setBaseURI(string calldata tokenURI) external;

    function maxSupply() external view returns (uint256);

    function setMaxSupply(uint256 newMaxSupply) external;

    function provenanceHash() external view returns (bytes32);

    function setProvenanceHash(bytes32 newProvenanceHash) external;
}
