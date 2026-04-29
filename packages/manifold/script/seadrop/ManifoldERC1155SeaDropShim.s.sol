// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "../../contracts/seadrop/ManifoldERC1155SeaDropShim.sol";

/**
 * @title DeployManifoldERC1155SeaDropShim
 * @notice Parameterized Forge deploy script for the per-drop SeaDrop shim.
 *
 * Env vars:
 *   - PRIVATE_KEY      (uint256) — deployer EOA
 *   - INITIAL_OWNER    (address) — wallet to set as the shim's Ownable owner
 *                                   (constructor's msg.sender is the CREATE2
 *                                   proxy when salt is used, so an explicit
 *                                   owner arg is required)
 *   - CREATOR_CONTRACT (address) — Manifold Creator Core ERC1155 to bind to
 *   - INSTANCE_ID      (uint256) — Manifold drop instanceId (must be non-zero)
 *   - SEADROP_ADDRESS  (address) — SeaDrop deployment authorized to mint
 *                                   (0x00005EA00Ac477B1030CE78506496e8C2dE24bf5 on mainnet/Sepolia)
 *
 * Does NOT call registerExtension or initialize — those are manual runbook
 * steps from the creator admin wallet (see contracts/seadrop/docs/lifecycle-and-deployment.md).
 * The Manifold drop instanceId is bound at deploy time as a constructor immutable.
 *
 * Example:
 *   forge script script/seadrop/ManifoldERC1155SeaDropShim.s.sol \
 *     --optimizer-runs 200 \
 *     --rpc-url $SEPOLIA_RPC_URL \
 *     --broadcast
 *
 *   forge verify-contract --compiler-version 0.8.17 --optimizer-runs 200 \
 *     --chain sepolia <DEPLOYED_ADDRESS> \
 *     contracts/seadrop/ManifoldERC1155SeaDropShim.sol:ManifoldERC1155SeaDropShim \
 *     --constructor-args $(cast abi-encode "constructor(address,address,uint256,address[])" \
 *       "${INITIAL_OWNER}" "${CREATOR_CONTRACT}" "${INSTANCE_ID}" "[${SEADROP_ADDRESS}]") \
 *     --watch
 */
contract DeployManifoldERC1155SeaDropShim is Script {
    function run() external {
        address initialOwner = vm.envAddress("INITIAL_OWNER");
        address creatorContract = vm.envAddress("CREATOR_CONTRACT");
        uint256 instanceId = vm.envUint("INSTANCE_ID");
        address seaDropAddress = vm.envAddress("SEADROP_ADDRESS");

        require(initialOwner != address(0), "INITIAL_OWNER not set");
        require(creatorContract != address(0), "CREATOR_CONTRACT not set");
        require(instanceId != 0, "INSTANCE_ID not set");
        require(seaDropAddress != address(0), "SEADROP_ADDRESS not set");

        address[] memory initialAllowedSeaDrop = new address[](1);
        initialAllowedSeaDrop[0] = seaDropAddress;

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // CREATE2 with a fixed salt: a second deploy with identical
        // constructor args on the same network reverts on address collision.
        ManifoldERC1155SeaDropShim shim = new ManifoldERC1155SeaDropShim{
            salt: 0x7a4d8e2b9c6f1a3d5e8b4c7f2a9d6e1b3c5f8a4d7e2b9c6f1a3d5e8b4c7f2a9d
        }(
            initialOwner,
            creatorContract,
            instanceId,
            initialAllowedSeaDrop
        );

        vm.stopBroadcast();

        console.log("ManifoldERC1155SeaDropShim deployed at:", address(shim));
        console.log("  initialOwner:  ", initialOwner);
        console.log("  creatorContract:", creatorContract);
        console.log("  instanceId:    ", instanceId);
        console.log("  allowedSeaDrop:", seaDropAddress);
    }
}
