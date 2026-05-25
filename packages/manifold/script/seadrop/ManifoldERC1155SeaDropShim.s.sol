// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "../../contracts/seadrop/ManifoldERC1155SeaDropShim.sol";

/**
 * @title DeployManifoldERC1155SeaDropShim
 * @notice Parameterized Forge deploy script for the per-drop SeaDrop shim.
 *
 * Env vars:
 *   - PRIVATE_KEY      (uint256) — deployer EOA. Pays for gas. Does NOT
 *                                   become the shim owner — INITIAL_OWNER
 *                                   does.
 *   - INITIAL_OWNER    (address) — wallet to set as the shim owner via the
 *                                   constructor's `_transferOwnership`.
 *                                   Required because CREATE2 + a factory
 *                                   means `msg.sender` in the constructor
 *                                   is the factory, not the intended drop
 *                                   admin. Must be non-zero.
 *   - SHIM_NAME        (string)  — ERC721 name (used by ERC721A).
 *   - SHIM_SYMBOL      (string)  — ERC721 symbol (used by ERC721A).
 *   - CREATOR_CONTRACT (address) — Manifold Creator Core ERC1155 to bind to.
 *   - SEADROP_ADDRESS  (address) — SeaDrop deployment authorized to mint
 *                                   (0x00005EA00Ac477B1030CE78506496e8C2dE24bf5
 *                                   on mainnet/Sepolia).
 *
 * Does NOT call registerExtension or initialize — those are manual runbook
 * steps. After deploy:
 *   1. From a creator-admin wallet on the target Manifold Creator Core:
 *      `creator.registerExtension(shim, "")`
 *   2. From the shim owner (INITIAL_OWNER):
 *      `shim.initialize()`           — seeds the ERC1155 tokenId
 *   3. From the shim owner:
 *      `shim.setMaxSupply(N)` and/or `shim.multiConfigure(cfg)` to push
 *      drop config to SeaDrop.
 *
 * Example:
 *   forge script script/seadrop/ManifoldERC1155SeaDropShim.s.sol \
 *     --optimizer-runs 500 \
 *     --rpc-url $SEPOLIA_RPC_URL \
 *     --broadcast
 *
 *   forge verify-contract --compiler-version 0.8.17 --optimizer-runs 500 \
 *     --chain sepolia <DEPLOYED_ADDRESS> \
 *     contracts/seadrop/ManifoldERC1155SeaDropShim.sol:ManifoldERC1155SeaDropShim \
 *     --constructor-args $(cast abi-encode \
 *       "constructor(string,string,address[],address,address)" \
 *       "${SHIM_NAME}" "${SHIM_SYMBOL}" "[${SEADROP_ADDRESS}]" \
 *       "${CREATOR_CONTRACT}" "${INITIAL_OWNER}") \
 *     --watch
 */
contract DeployManifoldERC1155SeaDropShim is Script {
    function run() external {
        address creatorContract = vm.envAddress("CREATOR_CONTRACT");
        address seaDropAddress = vm.envAddress("SEADROP_ADDRESS");
        address initialOwner = vm.envAddress("INITIAL_OWNER");
        string memory shimName = vm.envString("SHIM_NAME");
        string memory shimSymbol = vm.envString("SHIM_SYMBOL");

        require(creatorContract != address(0), "CREATOR_CONTRACT not set");
        require(seaDropAddress != address(0), "SEADROP_ADDRESS not set");
        require(initialOwner != address(0), "INITIAL_OWNER not set");

        address[] memory initialAllowedSeaDrop = new address[](1);
        initialAllowedSeaDrop[0] = seaDropAddress;

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // CREATE2 with a fixed salt: a second deploy with identical
        // constructor args on the same network reverts on address collision.
        ManifoldERC1155SeaDropShim shim = new ManifoldERC1155SeaDropShim{
            salt: 0x7a4d8e2b9c6f1a3d5e8b4c7f2a9d6e1b3c5f8a4d7e2b9c6f1a3d5e8b4c7f2a9d
        }(
            shimName,
            shimSymbol,
            initialAllowedSeaDrop,
            creatorContract,
            initialOwner
        );

        vm.stopBroadcast();

        console.log("ManifoldERC1155SeaDropShim deployed at:", address(shim));
        console.log("  name:           ", shimName);
        console.log("  symbol:         ", shimSymbol);
        console.log("  owner:          ", shim.owner());
        console.log("  creatorContract:", creatorContract);
        console.log("  allowedSeaDrop:", seaDropAddress);
    }
}
