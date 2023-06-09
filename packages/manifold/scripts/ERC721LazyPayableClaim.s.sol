// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../contracts/lazyclaim/ERC721LazyPayableClaim.sol";

contract DeployERC721LazyPayableClaim is Script {
    address DELEGATION_REGISTRY = 0x00000000000076A84feF008CDAbe6409d2FE638B;

    function run() external {
        address initialOwner = vm.envAddress("INITIAL_OWNER");
        require(initialOwner != address(0), "Initial owner address not set.  Please configure INITIAL_OWNER.");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        // forge script script/ERC721LazyPayableClaim.s.sol --optimizer-runs 1000 --rpc-url <YOUR_NODE> --broadcast
        // forge verify-contract --compiler-version 0.8.17 --optimizer-runs 1000 --chain goerli <DEPLOYED_ADDRESS> contracts/lazyclaim/ERC721LazyPayableClaim.sol:ERC721LazyPayableClaim --constructor-args (cast abi-encode "constructor(address,address)" "<INITIAL_OWNER>", "0x00000000000076A84feF008CDAbe6409d2FE638B") --watch
        new ERC721LazyPayableClaim{salt: 0x4552433732314c617a7950617961626c65436c61696d4552433732314c617a79}(initialOwner, DELEGATION_REGISTRY);
        vm.stopBroadcast();
    }
}