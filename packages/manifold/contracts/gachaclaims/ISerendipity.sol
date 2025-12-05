// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "./ISerendipityCore.sol";

/**
 * Serendipity Lazy Claim interface (ETH payment)
 */
interface ISerendipity is ISerendipityCore {
  /**
   * @notice                          minting request
   * @param creatorContractAddress    the creator contract address
   * @param instanceId                the claim instanceId for the creator contract
   * @param mintCount                 the number of claims to mint
   */
  function mintReserve(address creatorContractAddress, uint256 instanceId, uint32 mintCount) external payable;
}
