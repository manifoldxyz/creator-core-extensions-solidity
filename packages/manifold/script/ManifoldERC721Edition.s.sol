// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../contracts/edition/ManifoldERC721Edition.sol";

contract DeployManifoldERC721Edition is Script {
    function run() external {
        // uint256 deployerPrivateKey = pk; // uncomment this when testing on goerli
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY"); // comment this out when testing on goerli
        vm.startBroadcast(deployerPrivateKey);
        // forge script scripts/ManifoldERC721Edition.s.sol --optimizer-runs 1000 --rpc-url <YOUR_NODE> --broadcast
        // forge verify-contract --compiler-version 0.8.17 --optimizer-runs 1000 --chain sepolia <DEPLOYED_ADDRESS> contracts/edition/ManifoldERC721Edition.sol:ManifoldERC721Edition --constructor-args $(cast abi-encode "constructor(address)" "${INITIAL_OWNER}") --watch
        new ManifoldERC721Edition{salt: 0x4d616e69666f6c6445524337323145646974696f6e4d616e69666f6c64455243}();
        vm.stopBroadcast();
    }
}
