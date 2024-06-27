// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../contracts/gachaclaims/ERC1155SerendipityLazyClaim.sol";

/**
    Pro tip for testing! The private key can be whatever. This is what I did to test.

    1. Uncomment the lines below and follow the instructions there to change the code.
    2. Run the script, like `forge script script/ERC1155SerendipityLazyClaim.s.sol:DeployERC1155SerendipityLazyClaim --rpc-url https://eth-sepolia.g.alchemy.com/v2/xxx --broadcast`
    3. It will print out the address, but give you an out of eth error.
    4. Now you have the address, use your real wallet and send it some sepolia eth.
    5. Now, run the script again. It will deploy and transfer the contract to your wallet.

    In the end, you just basically used a random pk in the moment to deploy. You never had
    to expose your personal pk to your mac's environment variable or anything.
 */
contract DeployERC1155SerendipityLazyClaim is Script {
    function run() external {
        // address initialOwner = <your wallet address>; // uncomment this and put in your desired owner address
        address initialOwner = vm.envAddress("INITIAL_OWNER"); // comment this out on sepolia

        // uint pk = some combo of 6s and 9s;
        // address addr = vm.addr(pk);
        // console.log(addr);

        require(initialOwner != address(0), "Initial owner address not set.  Please configure INITIAL_OWNER.");

        // uint256 deployerPrivateKey = pk; // uncomment this when testing on goerli
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY"); // comment this out when testing on goerli
        vm.startBroadcast(deployerPrivateKey);

        //  forge script script/ERC1155SerendipityLazyClaim.s.sol:DeployERC1155SerendipityLazyClaim --optimizer-runs 1000 --rpc-url <YOUR_NODE> --broadcast
        // forge verify-contract --compiler-version 0.8.17 --optimizer-runs 1000 --chain sepolia <DEPLOYED_ADDRESS>  contracts/gachaclaims/ERC1155SerendipityLazyClaim.sol:ERC1155SerendipityLazyClaim --constructor-args $(cast abi-encode "constructor(address)" "${INITIAL_OWNER}") --watch
        new ERC1155SerendipityLazyClaim{salt: 0x16091cc3cd908d7d973f650f59bd476ac79090f0358f87c50a7f5caee0835a84}(initialOwner);
        vm.stopBroadcast();
    }
}