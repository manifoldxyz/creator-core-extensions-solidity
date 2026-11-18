// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "@manifoldxyz/creator-core-extensions-solidity/contracts/lazyclaim/IERC721LazyPayableClaim.sol";

import "../contracts/ERC721ClaimParams.sol";

/**
 * Deploys ERC721ClaimParams for one existing ERC721 lazy claim instance.
 *
 * The claim must be on a lazy claim extension that supports StorageProtocol.ADDRESS, priced in ETH,
 * without a signing address, on a v3+ creator contract. The script checks these and stops before
 * sending anything if one fails.
 *
 * CLAIM=<claim extension> CREATOR_CONTRACT=<creator contract> INSTANCE_ID=<instance id> PARAMS_LENGTH=<bytes> \
 *   forge script script/DeployERC721ClaimParams.s.sol --rpc-url <rpc> --account <keystore> --broadcast
 *
 * After the deploy, a creator contract admin calls, in order:
 *   1. ERC721ClaimParams.setRenderer(...)
 *   2. CLAIM.updateTokenURIParams(creatorContract, instanceId, 4, false, location), where location is the
 *      20 raw bytes of the deployed address, not its "0x..." text. Block explorer forms and `cast send`
 *      with a string argument send the text, so send the calldata this script prints instead.
 *   3. ERC721ClaimParams.lockRenderer(), once the renderer is final
 */
contract DeployERC721ClaimParams is Script {
    function run() external returns (ERC721ClaimParams deployed) {
        address claim = vm.envAddress("CLAIM");
        address creatorContract = vm.envAddress("CREATOR_CONTRACT");
        uint256 instanceId = vm.envUint("INSTANCE_ID");
        uint256 paramsLength = vm.envUint("PARAMS_LENGTH");

        require(paramsLength > 0 && paramsLength <= type(uint16).max, "PARAMS_LENGTH out of range");
        IERC721LazyPayableClaim.Claim memory c = IERC721LazyPayableClaim(claim).getClaim(creatorContract, instanceId);
        require(c.contractVersion >= 3, "creator contract must be v3 or later");
        require(c.erc20 == address(0), "claim must be priced in ETH");
        require(c.signingAddress == address(0), "claim must not use signature minting");

        vm.startBroadcast();
        deployed = new ERC721ClaimParams(claim, creatorContract, instanceId, uint16(paramsLength));
        vm.stopBroadcast();

        console.log("ERC721ClaimParams deployed at", address(deployed));
        console.log("Calldata to send to CLAIM from a creator contract admin (updateTokenURIParams):");
        console.logBytes(
            abi.encodeWithSignature(
                "updateTokenURIParams(address,uint256,uint8,bool,string)",
                creatorContract,
                instanceId,
                uint8(4), // StorageProtocol.ADDRESS
                false,
                string(abi.encodePacked(address(deployed)))
            )
        );
    }
}
