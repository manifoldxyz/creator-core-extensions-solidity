// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../contracts/single/ManifoldERC721Single.sol";

contract DeployManifoldERC721Single is Script {
    function run() external {
        // uint256 deployerPrivateKey = pk; // uncomment this when testing on goerli
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY"); // comment this out when testing on goerli
        vm.startBroadcast(deployerPrivateKey);
        // forge script script/ManifoldERC721Single.s.sol --optimizer-runs 1000 --rpc-url <YOUR_NODE> --broadcast
        // forge verify-contract --compiler-version 0.8.17 --optimizer-runs 1000 --chain sepolia <DEPLOYED_ADDRESS> contracts/single/ManifoldERC721Single.sol:ManifoldERC721Single --watch
        new ManifoldERC721Single{salt: 0x4d616e69666f6c6445524337323153696e676c654d616e69666f6c6445524337}();
        vm.stopBroadcast();
    }
}
