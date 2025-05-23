// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../contracts/burnredeemUpdatableFee/ERC1155BurnRedeemV2.sol";

contract DeployERC1155BurnRedeemV2 is Script {
  function run() external {
    address initialOwner = vm.envAddress("INITIAL_OWNER");
    require(initialOwner != address(0), "Initial owner address not set.  Please configure INITIAL_OWNER.");

    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);
    // Need to deploy the BurnRedeemLibV2 first via BurnRedeemLibV2.s.sol
    // Deploy by specifying the linked library address and at 150 runs (identical to linked library)
    // e.g.
    //   forge script script/ERC1155BurnRedeemV2.s.sol --optimizer-runs 150 --rpc-url <YOUR_NODE> --libraries contracts/burnredeemUpdatableFee/BurnRedeemLibV2.sol:BurnRedeemLibV2:<BURN_REDEEM_LIB_ADDRESS> --broadcast
    //   forge verify-contract --compiler-version 0.8.17 --optimizer-runs 150 --chain goerli <DEPLOYED_ADDRESS> contracts/burnredeemUpdatableFee/ERC1155BurnRedeemV2.sol:ERC1155BurnRedeemV2 --libraries contracts/burnredeemUpdatableFee/BurnRedeemLibV2.sol:BurnRedeemLibV2:<BURN_REDEEM_LIB_ADDRESS> --constructor-args $(cast abi-encode "constructor(address)" "${INITIAL_OWNER}") --watch
    new ERC1155BurnRedeemV2{ salt: 0x455243313135354275726e52656465656d455243313135354275726e52656465 }(initialOwner);
    vm.stopBroadcast();
  }
}
