// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../contracts/artistproof/ArtistProof.sol";

contract DeployArtistProof is Script {
    function run() external {
        address initialOwner = vm.envAddress("INITIAL_OWNER");
        require(initialOwner != address(0), "Initial owner address not set.  Please configure INITIAL_OWNER.");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        // Deploy by:
        //   forge script script/ArtistProof.s.sol --optimizer-runs 500 --rpc-url <YOUR_NODE> --broadcast
        //   forge verify-contract --compiler-version 0.8.17 --optimizer-runs 500 --chain goerli <DEPLOYED_ADDRESS> contracts/artistproof/ArtistProof.sol:ArtistProof --constructor-args $(cast abi-encode "constructor(address)" "${INITIAL_OWNER}") --watch
        new ArtistProofExtension{salt: 0x4d616e69666f6c6441727469737450726f6f664d616e69666f6c644172746973}(initialOwner);
        vm.stopBroadcast();
    }
}
