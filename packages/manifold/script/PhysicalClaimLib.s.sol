// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../contracts/physicalclaim/PhysicalClaimLib.sol";

contract DeployPhysicalClaimLib is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        // Deploy using the create2 proxy @ 0x4e59b44847b379578588920cA78FbF26c0B4956C
        // With the calldata being the salt + bytecode
        // Deploy with 150 runs
        // e.g.
        //   forge script script/PhysicalClaimLib.s.sol --optimizer-runs 1000 --rpc-url <YOUR_NODE> --broadcast
        //   forge verify-contract --compiler-version 0.8.17 --optimizer-runs 1000 --chain goerli <DEPLOYED_ADDRESS> contracts/physicalclaim/PhysicalClaimLib.sol:PhysicalClaimLib --watch
        0x4e59b44847b379578588920cA78FbF26c0B4956C.call(abi.encodePacked(bytes32(0x4c657427732067657420506879736963616c2000000000000000000000000000), vm.getCode("PhysicalClaimLib.sol:PhysicalClaimLib")));
        vm.stopBroadcast();
    }
}
