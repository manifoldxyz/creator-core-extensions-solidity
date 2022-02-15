// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

/**
 * Manifold ERC721 LazyMint Controller interface
 */
interface IManifoldERC721LazyMint {

    event DropCreated(address caller, address creator, uint256 drop, uint256 maxSupply, uint256 mintPrice, uint256 premintPrice, uint256 maxTokensPerAddress);

    /**
     * @dev Create a new drop.  Returns the drop id.
     */
    function createDrop(address creator, string calldata baseURI, uint256 maxSupply, uint256 mintPrice, uint256 premintPrice, uint256 maxTokensPerAddress) external returns(uint256);
    /**
     * @dev Activate pre-mint phase
     */
    function activatePremintPhase(address creator, uint256 drop) external;

    /**
     * @dev Activate sale phase
     */
    function activateSalePhase(address creator, uint256 drop) external;

    /**
     * @dev Deactivate sales
     */
    function deactivateSales(address creator, uint256 drop) external;

    /**
     * @dev Sale phase
     */
    function salePhase(address creator, uint256 drop) external returns(uint8);

    /**
     * @dev Max supply to lazy mint
     */
    function maxSupply(address creator, uint256 drop) external view returns(uint256);

    /**
     * @dev Mint price for the drop
     */
    function mintPrice(address creator, uint256 drop) external view returns(uint256);

    /**
     * @dev Premint price for the drop
     */
    function premintPrice(address creator, uint256 drop) external view returns(uint256);

    /**
     * @dev Max tokens per address
     */
    function maxTokensPerAddress(address creator, uint256 drop) external view returns(uint256);

    /**
     * @dev See if wallet is in allow list
     */
    function isInAllowList(address creator, uint256 drop, address wallet) external view returns(bool);

    /**
     * @dev Set list of addresses that can premint
     */
    function setAllowList(address creator, uint256 drop, address[] calldata allowList) external;

    /**
     * @dev Total supply already minted
     */
    function totalSupply(address creator, uint256 drop) external view returns(uint256);

    /**
     * @dev Premint NFTs to a single recipient
     */
    function premint(address creator, uint256 drop, uint16 count) external payable;

    /**
     * @dev Mint NFTs to a single recipient
     */
    function mint(address creator, uint256 drop, uint16 count) external payable;

    /**
     * @dev Withdraw
     */
    function withdraw(address creator, uint256 drop, address payable to) external payable;

    /**
     * @dev Total ether to withdraw
     */
    function totalToWithdraw(address creator, uint256 drop) external view returns(uint256);

    /**
     * @dev Set the base token URI
     */
    function reveal(address creator, uint256 drop, string calldata baseURI) external;
}
