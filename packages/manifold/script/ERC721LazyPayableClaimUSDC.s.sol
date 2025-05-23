// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../contracts/lazyclaim/ERC721LazyPayableClaimUSDC.sol";

/**
 * Pro tip for testing! The private key can be whatever. This is what I did to test.
 *
 *     1. Uncomment the lines below and follow the instructions there to change the code.
 *     2. Run the script, like `forge script scripts/ERC721LazyPayableClaim.s.sol --rpc-url https://eth-goerli.g.alchemy.com/v2/xxx --broadcast`
 *     3. It will print out the address, but give you an out of eth error.
 *     4. Now you have the address, use your real wallet and send it some goerli eth.
 *     5. Now, run the script again. It will deploy and transfer the contract to your wallet.
 *
 *     In the end, you just basically used a random pk in the moment to deploy. You never had
 *     to expose your personal pk to your mac's environment variable or anything.
 */
contract DeployERC721LazyPayableClaimUSDC is Script {
    address DELEGATION_REGISTRY = 0x00000000000076A84feF008CDAbe6409d2FE638B;
    address DELEGATION_REGISTRY_V2 = 0x00000000000000447e69651d841bD8D104Bed493;

    function run() external {
        // address initialOwner = <your wallet address>; // uncomment this and put in your wallet on goerli
        address initialOwner = vm.envAddress("INITIAL_OWNER"); // comment this out on goerli
        address usdcAddress = vm.envAddress("USDC_ADDRESS");

        // uint pk = some combo of 6s and 9s;
        // address addr = vm.addr(pk);
        // console.log(addr);

        require(initialOwner != address(0), "Initial owner address not set.  Please configure INITIAL_OWNER.");
        require(usdcAddress != address(0), "USDC address not set.  Please configure USDC_ADDRESS.");
        // uint256 deployerPrivateKey = pk; // uncomment this when testing on goerli
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY"); // comment this out when testing on goerli
        vm.startBroadcast(deployerPrivateKey);
        // forge script script/ERC721LazyPayableClaimUSDC.s.sol --optimizer-runs 500 --rpc-url <YOUR_NODE> --broadcast
        // forge verify-contract --compiler-version 0.8.17 --optimizer-runs 500 --chain sepolia <DEPLOYED_ADDRESS> contracts/lazyclaim/ERC721LazyPayableClaimUSDC.sol:ERC721LazyPayableClaimUSDC --constructor-args $(cast abi-encode "constructor(address,address,address)" "${INITIAL_OWNER}" "0x00000000000076A84feF008CDAbe6409d2FE638B" "0x00000000000000447e69651d841bD8D104Bed493") --watch
        new ERC721LazyPayableClaimUSDC{salt: 0x4552433732314c617a7950617961626c65436c61696d55534443455243373231}(
            initialOwner, usdcAddress, DELEGATION_REGISTRY, DELEGATION_REGISTRY_V2
        );
        vm.stopBroadcast();
    }
}
