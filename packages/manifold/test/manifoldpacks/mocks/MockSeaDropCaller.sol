// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @notice Minimal interface for the ERC721SeaDrop mint entrypoint gated by
 *         `_onlyAllowedSeaDrop(msg.sender)`. Matches the real signature in
 *         seadrop/src/ERC721SeaDrop.sol:
 *             function mintSeaDrop(address minter, uint256 quantity) external;
 */
interface IMintSeaDrop {
    function mintSeaDrop(address minter, uint256 quantity) external;
}

/**
 * @title  MockSeaDropCaller
 * @notice A stand-in for a real SeaDrop contract in tests. ManifoldPacksSeaDropShim gates
 *         `mintSeaDrop` on `_allowedSeaDrop[msg.sender] == true`, so an instance
 *         of this mock must be passed in the `allowedSeaDrop_` constructor array
 *         (or added later via `updateAllowedSeaDrop`). Because this contract IS
 *         the message sender when it forwards the call, it satisfies the
 *         allowed-caller gate and can drive pack minting directly.
 */
contract MockSeaDropCaller {
    /**
     * @notice Drive the pack collection's SeaDrop mint entrypoint.
     *
     * @param token    The ManifoldPacksSeaDropShim (ERC721SeaDrop) collection to mint on.
     * @param minter   The address to receive the minted packs.
     * @param quantity The number of packs to mint.
     */
    function mint(address token, address minter, uint256 quantity) external {
        IMintSeaDrop(token).mintSeaDrop(minter, quantity);
    }
}
