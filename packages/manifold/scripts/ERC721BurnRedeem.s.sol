// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../contracts/burnredeem/ERC721BurnRedeem.sol";

contract DeployERC721BurnRedeem is Script {
    function run() external {
        address initialOwner = vm.envAddress("INITIAL_OWNER");
        require(initialOwner != address(0), "Initial owner address not set.  Please configure INITIAL_OWNER.");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        // Need to deploy the BurnRedeemLib first via BurnRedeemLib.s.sol
        // Deploy by specifying the linked library address and at 150 runs (identical to linked library)
        // e.g.
        //   forge script script/ERC721BurnRedeem.s.sol --optimizer-runs 150 --rpc-url <YOUR_NODE> --libraries contracts/burnredeem/BurnRedeemLib.sol:BurnRedeemLib:<BURN_REDEEM_LIB_ADDRESS> --broadcast
        //   forge verify-contract --compiler-version 0.8.17 --optimizer-runs 150 --chain goerli <DEPLOYED_ADDRESS> contracts/burnredeem/ERC721BurnRedeem.sol:ERC721BurnRedeem --libraries contracts/burnredeem/BurnRedeemLib.sol:BurnRedeemLib:<BURN_REDEEM_LIB_ADDRESS> --constructor-args (cast abi-encode "constructor(address)", "<INITIAL_OWNER>") --watch
        new ERC721BurnRedeem{salt: 0x4552433732314275726e52656465656d4552433732314275726e52656465656d}(initialOwner);
        vm.stopBroadcast();
    }
}
