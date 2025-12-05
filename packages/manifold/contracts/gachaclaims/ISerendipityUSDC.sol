// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "./ISerendipityCore.sol";

/**
 * Serendipity USDC Lazy Claim interface (USDC payment)
 */
interface ISerendipityUSDC is ISerendipityCore {
    error InvalidUSDCAddress();

    /**
     * @notice Set the mint fee for claims
     * @param mintFee the mint fee
     */
    function setMintFee(uint256 mintFee) external;

    /**
     * @notice                          minting request (USDC - not payable)
     * @param creatorContractAddress    the creator contract address
     * @param instanceId                the claim instanceId for the creator contract
     * @param mintCount                 the number of claims to mint
     * @param mintFor                   the address to mint for
     */
    function mintReserve(address creatorContractAddress, uint256 instanceId, uint32 mintCount, address mintFor) external;
}
