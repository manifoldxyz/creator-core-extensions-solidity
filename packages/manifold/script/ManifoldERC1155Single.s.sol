// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../contracts/single/ManifoldERC1155Single.sol";

contract DeployManifoldERC1155Single is Script {
    function run() external {
        // uint256 deployerPrivateKey = pk; // uncomment this when testing on goerli
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY"); // comment this out when testing on goerli
        vm.startBroadcast(deployerPrivateKey);
        // forge script script/ManifoldERC1155Single.s.sol --optimizer-runs 1000 --rpc-url <YOUR_NODE> --broadcast
        // forge verify-contract --compiler-version 0.8.17 --optimizer-runs 1000 --chain sepolia <DEPLOYED_ADDRESS> contracts/single/ManifoldERC1155Single.sol:ManifoldERC1155Single --watch
        new ManifoldERC1155Single{salt: 0x4d616e69666f6c644552433131353553696e676c654d616e69666f6c64455243}();
        vm.stopBroadcast();
    }
}
