// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../../../contracts/manifold/burnredeem/ERC721BurnRedeem.sol";

contract DeployERC721BurnRedeem is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new ERC721BurnRedeem{salt: 0x4552433732314c617a7950617961626c65436c61696d4552433732314c617a79}(0xa8863bf1c8933f649e7b03Eb72109E5E187505Ea);
        vm.stopBroadcast();
    }
}
