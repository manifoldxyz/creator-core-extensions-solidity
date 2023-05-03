// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../../../contracts/manifold/lazyclaim/ERC721LazyPayableClaim.sol";

contract DeployERC721LazyPayableClaim is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        new ERC721LazyPayableClaim{salt: 0x8841697264726f7056657269666965720041697264726f705665726966696572}(0x00000000000076A84feF008CDAbe6409d2FE638B);

        vm.stopBroadcast();
    }
}