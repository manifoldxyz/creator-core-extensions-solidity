// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../contracts/lazyclaim/ERC721LazyPayableClaim.sol";

contract DeployERC721LazyPayableClaim is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new ERC721LazyPayableClaim{salt: 0x4552433732314c617a7950617961626c65436c61696d4552433732314c617a79}(0xa8863bf1c8933f649e7b03Eb72109E5E187505Ea, 0x00000000000076A84feF008CDAbe6409d2FE638B);
        vm.stopBroadcast();
    }
}