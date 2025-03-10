// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../contracts/burnredeemUpdatableFee/ERC721BurnRedeemV2.sol";

contract DeployERC721BurnRedeemV2 is Script {
  function run() external {
    address initialOwner = vm.envAddress("INITIAL_OWNER");
    require(initialOwner != address(0), "Initial owner address not set.  Please configure INITIAL_OWNER.");

    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);
    // Need to deploy the BurnRedeemLibV2 first via BurnRedeemLibV2.s.sol
    // Deploy by specifying the linked library address and at 150 runs (identical to linked library)
    // e.g.
    //   forge script script/ERC721BurnRedeemV2.s.sol --optimizer-runs 150 --rpc-url <YOUR_NODE> --libraries contracts/burnredeemUpdatableFee/BurnRedeemLibV2.sol:BurnRedeemLibV2:<BURN_REDEEM_LIB_ADDRESS> --broadcast
    //   forge verify-contract --compiler-version 0.8.17 --optimizer-runs 150 --chain sepolia <DEPLOYED_ADDRESS> contracts/burnredeemUpdatableFee/ERC721BurnRedeemV2.sol:ERC721BurnRedeemV2 --libraries contracts/burnredeemUpdatableFee/BurnRedeemLibV2.sol:BurnRedeemLibV2:<BURN_REDEEM_LIB_ADDRESS> --constructor-args $(cast abi-encode "constructor(address)" "${INITIAL_OWNER}") --watch
    new ERC721BurnRedeemV2{ salt: 0x4552433732314275726e52656465656d4552433732314275726e52656465656d }(initialOwner);
    vm.stopBroadcast();
  }
}
