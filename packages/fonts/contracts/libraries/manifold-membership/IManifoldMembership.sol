
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

/**
 * Manifold Membership interface
 */
interface IManifoldMembership {
   function isActiveMember(address sender) external view returns (bool);
}