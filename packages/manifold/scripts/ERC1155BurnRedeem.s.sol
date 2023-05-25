// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../contracts/burnredeem/ERC1155BurnRedeem.sol";

contract DeployERC1155BurnRedeem is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        // Need to deploy the BurnRedeemLib first via BurnRedeemLib.s.sol
        // Deploy by specifying the linked library address and at 150 runs (identical to linked library)
        // e.g.
        //   forge script script/manifold/burnredeem/ERC1155BurnRedeem.s.sol --optimizer-runs 150 --rpc-url <YOUR_NODE> --libraries contracts/manifold/burnredeem/BurnRedeemLib.sol:BurnRedeemLib:<BURN_REDEEM_LIB_ADDRESS> --broadcast
        //   forge verify-contract --compiler-version 0.8.17 --optimizer-runs 150 --chain goerli <DEPLOYED_ADDRESS> contracts/manifold/burnredeem/ERC1155BurnRedeem.sol:ERC1155BurnRedeem --libraries contracts/manifold/burnredeem/BurnRedeemLib.sol:BurnRedeemLib:<BURN_REDEEM_LIB_ADDRESS> --constructor-args 000000000000000000000000a8863bf1c8933f649e7b03eb72109e5e187505ea --watch
        new ERC1155BurnRedeem{salt: 0x455243313135354275726e52656465656d455243313135354275726e52656465}(0xa8863bf1c8933f649e7b03Eb72109E5E187505Ea);
        vm.stopBroadcast();
    }
}
