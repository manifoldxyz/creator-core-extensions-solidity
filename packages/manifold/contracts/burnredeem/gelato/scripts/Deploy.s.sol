// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../GelatoERC721BurnRedeem.sol";
import "../GelatoERC1155BurnRedeem.sol";

/**
 * @title Deploy Gelato Burn Redeem Contracts
 * @notice Deployment script for Gelato-enabled burn redeem contracts
 *
 * Usage:
 *   forge script scripts/Deploy.s.sol:DeployGelatoBurnRedeem \
 *     --rpc-url $RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast \
 *     --verify
 *
 * Or using environment variables:
 *   source .env
 *   forge script scripts/Deploy.s.sol:DeployGelatoBurnRedeem \
 *     --rpc-url $RPC_URL \
 *     --broadcast \
 *     --verify
 */
contract DeployGelatoBurnRedeem is Script {

    function run() external {
        // Get deployer from private key
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying contracts with account:", deployer);
        console.log("Account balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy ERC721 Gelato Burn Redeem
        console.log("\nDeploying GelatoERC721BurnRedeem...");
        GelatoERC721BurnRedeem erc721BurnRedeem = new GelatoERC721BurnRedeem(deployer);
        console.log("GelatoERC721BurnRedeem deployed at:", address(erc721BurnRedeem));

        // Deploy ERC1155 Gelato Burn Redeem
        console.log("\nDeploying GelatoERC1155BurnRedeem...");
        GelatoERC1155BurnRedeem erc1155BurnRedeem = new GelatoERC1155BurnRedeem(deployer);
        console.log("GelatoERC1155BurnRedeem deployed at:", address(erc1155BurnRedeem));

        vm.stopBroadcast();

        // Log deployment summary
        console.log("\n=== Deployment Summary ===");
        console.log("Network:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("GelatoERC721BurnRedeem:", address(erc721BurnRedeem));
        console.log("GelatoERC1155BurnRedeem:", address(erc1155BurnRedeem));
        console.log("\nGelato Trusted Forwarder: 0xaBcC9b596420A9E9172FD5938620E265a0f9Df92");
        console.log("\n=== Next Steps ===");
        console.log("1. Verify contracts on block explorer");
        console.log("2. Update frontend with deployed addresses");
        console.log("3. Test with Gelato relay on testnet");
        console.log("4. Configure Manifold Membership contract (if desired)");
    }
}

/**
 * @title Deploy to Multiple Networks
 * @notice Script to deploy to all major networks
 *
 * Usage:
 *   forge script scripts/Deploy.s.sol:DeployToAllNetworks \
 *     --broadcast \
 *     --verify
 */
contract DeployToAllNetworks is Script {

    struct NetworkConfig {
        string name;
        uint256 chainId;
        string rpcUrl;
    }

    function run() external {
        NetworkConfig[] memory networks = new NetworkConfig[](5);

        // Mainnet
        networks[0] = NetworkConfig({
            name: "Ethereum Mainnet",
            chainId: 1,
            rpcUrl: vm.envString("MAINNET_RPC_URL")
        });

        // Polygon
        networks[1] = NetworkConfig({
            name: "Polygon",
            chainId: 137,
            rpcUrl: vm.envString("POLYGON_RPC_URL")
        });

        // Base
        networks[2] = NetworkConfig({
            name: "Base",
            chainId: 8453,
            rpcUrl: vm.envString("BASE_RPC_URL")
        });

        // Sepolia (testnet)
        networks[3] = NetworkConfig({
            name: "Sepolia",
            chainId: 11155111,
            rpcUrl: vm.envString("SEPOLIA_RPC_URL")
        });

        // Base Sepolia (testnet)
        networks[4] = NetworkConfig({
            name: "Base Sepolia",
            chainId: 84532,
            rpcUrl: vm.envString("BASE_SEPOLIA_RPC_URL")
        });

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== Deploying to Multiple Networks ===");
        console.log("Deployer address:", deployer);
        console.log("\n");

        for (uint256 i = 0; i < networks.length; i++) {
            deployToNetwork(networks[i], deployerPrivateKey, deployer);
        }
    }

    function deployToNetwork(
        NetworkConfig memory network,
        uint256 deployerPrivateKey,
        address deployer
    ) internal {
        console.log("--- Deploying to", network.name, "---");

        vm.createSelectFork(network.rpcUrl);

        vm.startBroadcast(deployerPrivateKey);

        GelatoERC721BurnRedeem erc721 = new GelatoERC721BurnRedeem(deployer);
        GelatoERC1155BurnRedeem erc1155 = new GelatoERC1155BurnRedeem(deployer);

        vm.stopBroadcast();

        console.log("Network:", network.name);
        console.log("Chain ID:", network.chainId);
        console.log("GelatoERC721BurnRedeem:", address(erc721));
        console.log("GelatoERC1155BurnRedeem:", address(erc1155));
        console.log("\n");
    }
}

/**
 * @title Upgrade Existing Deployment
 * @notice Script to deploy new versions alongside existing contracts
 *
 * Usage:
 *   forge script scripts/Deploy.s.sol:UpgradeDeployment \
 *     --rpc-url $RPC_URL \
 *     --broadcast \
 *     --verify
 */
contract UpgradeDeployment is Script {

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Get existing contract addresses
        address existingERC721 = vm.envAddress("EXISTING_ERC721_BURN_REDEEM");
        address existingERC1155 = vm.envAddress("EXISTING_ERC1155_BURN_REDEEM");

        console.log("=== Upgrade Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Existing ERC721:", existingERC721);
        console.log("Existing ERC1155:", existingERC1155);
        console.log("\n");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy new Gelato versions
        console.log("Deploying new Gelato-enabled versions...");
        GelatoERC721BurnRedeem newERC721 = new GelatoERC721BurnRedeem(deployer);
        GelatoERC1155BurnRedeem newERC1155 = new GelatoERC1155BurnRedeem(deployer);

        vm.stopBroadcast();

        console.log("\n=== Deployment Complete ===");
        console.log("New GelatoERC721BurnRedeem:", address(newERC721));
        console.log("New GelatoERC1155BurnRedeem:", address(newERC1155));
        console.log("\n=== Migration Steps ===");
        console.log("1. The old contracts remain functional");
        console.log("2. Update frontend to use new addresses for new burns");
        console.log("3. Existing burns continue using old contracts");
        console.log("4. Gradually migrate users to Gelato-enabled contracts");
    }
}
