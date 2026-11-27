// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import "../contracts/ERC721ClaimSecretReveal.sol";

/**
 * Deploys ERC721ClaimSecretReveal for one creator contract.
 *
 * CREATOR_CONTRACT=<creator contract> COMMIT=<sha256 of the secret, 0x + 64 hex> SUPPLY=<editions> \
 * KEY_PREFIX=<key message prefix> NAME=<token name> DESCRIPTION=<description> \
 * IMAGE_URI=<cover image> ANIMATION_URI=<renderer> \
 *   forge script script/DeployERC721ClaimSecretReveal.s.sol --rpc-url <rpc> --account <keystore> --broadcast
 *
 * The strings go into the token JSON unescaped, so the script stops before sending anything if one
 * contains '"' or '\'.
 *
 * Then point an ERC721 claim on a lazy claim extension that supports StorageProtocol.ADDRESS at the
 * deployed address: either create it that way (initializeClaim with StorageProtocol.ADDRESS and the
 * address as location), or switch an existing claim with updateTokenURIParams. For the second, also
 * set CLAIM=<claim extension> and INSTANCE_ID=<instance id> and the script prints the calldata to send
 * from a creator contract admin. `location` must be the 20 raw bytes of the address, not its "0x..."
 * text; block explorer forms and `cast send` with a string argument send the text.
 *
 * After the claim closes, a creator contract admin calls reveal(secret).
 */
contract DeployERC721ClaimSecretReveal is Script {
    function run() external returns (ERC721ClaimSecretReveal deployed) {
        address creatorContract = vm.envAddress("CREATOR_CONTRACT");
        bytes32 commit = vm.envBytes32("COMMIT");
        uint256 supply = vm.envUint("SUPPLY");
        string memory keyPrefix = vm.envString("KEY_PREFIX");
        IERC721ClaimSecretReveal.Renderer memory renderer = IERC721ClaimSecretReveal.Renderer({
            name: vm.envString("NAME"),
            description: vm.envString("DESCRIPTION"),
            imageURI: vm.envString("IMAGE_URI"),
            animationURI: vm.envString("ANIMATION_URI")
        });

        require(supply > 0 && supply <= type(uint24).max, "SUPPLY out of range");
        require(commit != bytes32(0), "COMMIT missing");
        _requireJsonSafe(renderer.name, "NAME");
        _requireJsonSafe(renderer.description, "DESCRIPTION");
        _requireJsonSafe(renderer.imageURI, "IMAGE_URI");
        _requireJsonSafe(renderer.animationURI, "ANIMATION_URI");

        vm.startBroadcast();
        deployed = new ERC721ClaimSecretReveal(creatorContract, commit, uint24(supply), keyPrefix, renderer);
        vm.stopBroadcast();

        console.log("ERC721ClaimSecretReveal deployed at", address(deployed));

        address claim = vm.envOr("CLAIM", address(0));
        if (claim != address(0)) {
            uint256 instanceId = vm.envUint("INSTANCE_ID");
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

    function _requireJsonSafe(string memory value, string memory name) private pure {
        bytes memory b = bytes(value);
        for (uint256 i; i < b.length; i++) {
            require(
                b[i] != '"' && b[i] != "\\" && uint8(b[i]) >= 0x20,
                string(abi.encodePacked(name, " contains a quote, backslash or control character"))
            );
        }
    }
}
