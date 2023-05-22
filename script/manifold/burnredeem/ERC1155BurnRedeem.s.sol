// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../../../contracts/manifold/burnredeem/ERC1155BurnRedeem.sol";

contract DeployERC1155BurnRedeem is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new ERC1155BurnRedeem{salt: 0x455243313135354275726e52656465656d455243313135354275726e52656465}(0xa8863bf1c8933f649e7b03Eb72109E5E187505Ea);
        vm.stopBroadcast();
    }
}
