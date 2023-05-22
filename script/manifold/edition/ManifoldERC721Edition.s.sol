// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../../../contracts/manifold/edition/ManifoldERC721Edition.sol";

contract DeployManifoldERC721Edition is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new ManifoldERC721Edition{salt: 0x4d616e69666f6c6445524337323145646974696f6e4d616e69666f6c64455243}();
        vm.stopBroadcast();
    }
}
