// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../contracts/operatorfilterer/OperatorFilterer.sol";

contract DeployOperatorFilterer is Script {
    address OPERATOR_FILTER_REGISTRY = 0x000000000000AAeB6D7670E522A718067333cd4E;

    function run() external {
        address subscription = vm.envAddress("SUBSCRIPTION");
        require(subscription != address(0), "Subscription address not set. Please configure SUBSCRIPTION.");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        // forge script scripts/OperatorFilterer.s.sol --optimizer-runs 1000 --rpc-url <YOUR_NODE> --broadcast
        // forge verify-contract --compiler-version 0.8.17 --optimizer-runs 1000 --chain goerli <DEPLOYED_ADDRESS> contracts/operatorfilterer/OperatorFilterer.sol:OperatorFilterer --constructor-args $(cast abi-encode "constructor(address,address)" "0x000000000000AAeB6D7670E522A718067333cd4E" "${SUBSCRIPTION}") --watch
        new OperatorFilterer{salt: 0x4f70657261746f7246696c74657265724f70657261746f7246696c7465726572}(OPERATOR_FILTER_REGISTRY, subscription);

        vm.stopBroadcast();
    }
}
