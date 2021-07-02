// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

/**
 * Font interface
 */
interface IFontWOFF {
    function woff() external view returns(string memory);
}