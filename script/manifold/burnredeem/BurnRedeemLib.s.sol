// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../../../contracts/manifold/burnredeem/BurnRedeemLib.sol";

contract DeployBurnRedeemLib is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        // Deploy using the create2 proxy @ 0x4e59b44847b379578588920cA78FbF26c0B4956C
        // With the calldata being the salt + bytecode
        // Deploy with 150 runs
        // e.g.
        //   forge script script/manifold/burnredeem/BurnRedeemLib.s.sol --optimizer-runs 150 --rpc-url <YOUR_NODE> --broadcast
        //   forge verify-contract --compiler-version 0.8.17 --optimizer-runs 150 --chain goerli <DEPLOYED_ADDRESS> contracts/manifold/burnredeem/BurnRedeemLib.sol:BurnRedeemLib --watch
        0x4e59b44847b379578588920cA78FbF26c0B4956C.call(abi.encodePacked(bytes32(0x4275726e52656465656d4c69624275726e52656465656d4c69624275726e5265), vm.getCode("BurnRedeemLib.sol:BurnRedeemLib")));
        vm.stopBroadcast();
    }
}
