// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/////////////////////////////////////////////////////////////////////////////////////
//                                                                                 //
//                                                                                 //
//                                     .%(#.                                       //
//                                      #(((#%,                                    //
//                                      (#(((((#%*                                 //
//                                      /#((((((((##*                              //
//                                      (#((((((((((##%.                           //
//                                     ,##(/*/(////((((#%*                         //
//                                   .###(//****/////(((##%,                       //
//                  (,          ,%#((((((///******/////((##%(                      //
//                *((,         ,##(///////*********////((###%*                     //
//              /((((         ,##(//////************/(((((###%                     //
//             /((((         ,##((////***************/((((###%                     //
//             (((          .###((///*****************((((####                     //
//             .            (##((//*******************((((##%*                     //
//               (#.       .###((/********************((((##%.      %.             //
//             ,%(#.       .###(/********,,,,,,,*****/(((###%#     ((%,            //
//            /%#/(/       /###(//****,,,,,,,,,,,****/((((((##%%%%#((#%.           //
//           /##(//(#.    ,###((/****,,,,,,,,,,,,,***/((/(((((((((#####%           //
//          *%##(/////((###((((/***,,,,,,,,,,,,,,,***//((((((((((####%%%/          //
//          ####(((//////(//////**,,,,,,.....,,,,,,****/(((((//((####%%%%          //
//         .####(((/((((((/////**,,,,,.......,,,,,,,,*****/////(#####%%%%          //
//         .#%###((////(((//***,,,,,,..........,,,,,,,,*****//((#####%%%%          //
//          /%%%###/////*****,,,,,,,..............,,,,,,,****/(((####%%%%          //
//           /%%###(////****,,,,,,.....        ......,,,,,,**(((####%%%%           //
//            ,#%###(///****,,,,,....            .....,,,,,***/(/(##%%(            //
//              (####(//****,,....                 ....,,,,,***/(####              //
//                (###(/***,,,...                    ...,,,,***(##/                //
//             #.   (#((/**,,,,..                    ...,,,,*((#,                  //
//               ,#(##(((//,,,,..                   ...,,,*/(((#((/                //
//                  *#(((///*,,....                ....,*//((((                    //
//                      *(///***,....            ...,***//,                        //
//                           ,//***,...       ..,,*,                               //
//                                                                                 //
//                                                                                 //
/////////////////////////////////////////////////////////////////////////////////////

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "./IBurnRedeemCore.sol";

/**
 * @title Burn Redeem Lib
 * @author manifold.xyz
 * @notice Library for Burn Redeem shared extensions.
 */
library BurnRedeemLib {

    event BurnRedeemInitialized(address indexed creatorContract, uint256 indexed instanceId, address initializer);
    event BurnRedeemUpdated(address indexed creatorContract, uint256 indexed instanceId);
    event BurnRedeemMint(address indexed creatorContract, uint256 indexed instanceId, uint256 indexed tokenId, uint32 redeemedCount);

    /**
     * Initialiazes a burn redeem with base parameters
     */
    function initialize(
        address creatorContractAddress,
        uint8 creatorContractVersion,
        uint256 instanceId,
        IBurnRedeemCore.BurnRedeem storage burnRedeemInstance,
        IBurnRedeemCore.BurnRedeemParameters calldata burnRedeemParameters
    ) public {
        // Sanity checks
        require(burnRedeemInstance.storageProtocol == IBurnRedeemCore.StorageProtocol.INVALID, "Burn redeem already initialized");
        _validateParameters(burnRedeemParameters);

        // Create the burn redeem
        burnRedeemInstance.contractVersion = creatorContractVersion;
        _setParameters(burnRedeemInstance, burnRedeemParameters);
        _setBurnGroups(burnRedeemInstance, burnRedeemParameters.burnSet);

        emit BurnRedeemInitialized(creatorContractAddress, instanceId, msg.sender);
    }

    /**
     * Updates a burn redeem with base parameters
     */
    function update(
        address creatorContractAddress,
        uint256 instanceId,
        IBurnRedeemCore.BurnRedeem storage burnRedeemInstance,
        IBurnRedeemCore.BurnRedeemParameters calldata burnRedeemParameters
    ) public {
        // Sanity checks
        require(burnRedeemInstance.storageProtocol != IBurnRedeemCore.StorageProtocol.INVALID, "Burn redeem not initialized");
        _validateParameters(burnRedeemParameters);
        // The current redeemedCount must be divisible by redeemAmount
        require(burnRedeemInstance.redeemedCount % burnRedeemParameters.redeemAmount == 0, "Invalid amount");

        // Overwrite the existing burnRedeem
        _setParameters(burnRedeemInstance, burnRedeemParameters);
        _setBurnGroups(burnRedeemInstance, burnRedeemParameters.burnSet);
        syncTotalSupply(burnRedeemInstance);
        emit BurnRedeemUpdated(creatorContractAddress, instanceId);
    }

    /**
     * Helper to update total supply if redeemedCount exceeds totalSupply after airdrop or instance update.
     */
    function syncTotalSupply(IBurnRedeemCore.BurnRedeem storage burnRedeemInstance) public {
        if (
            burnRedeemInstance.totalSupply != 0 &&
            burnRedeemInstance.redeemedCount > burnRedeemInstance.totalSupply
        ) {
            burnRedeemInstance.totalSupply = burnRedeemInstance.redeemedCount;
        }
    }

    /*
     * Helper to validate burn item
     */
    function validateBurnItem(IBurnRedeemCore.BurnItem memory burnItem, address contractAddress, uint256 tokenId, bytes32[] memory merkleProof) public pure {
        require(contractAddress == burnItem.contractAddress, "Invalid burn token");
        if (burnItem.validationType == IBurnRedeemCore.ValidationType.CONTRACT) {
            return;
        } else if (burnItem.validationType == IBurnRedeemCore.ValidationType.RANGE) {
            require(tokenId >= burnItem.minTokenId && tokenId <= burnItem.maxTokenId, "Invalid token ID");
            return;
        } else if (burnItem.validationType == IBurnRedeemCore.ValidationType.MERKLE_TREE) {
            bytes32 leaf = keccak256(abi.encodePacked(tokenId));
            require(MerkleProof.verify(merkleProof, burnItem.merkleRoot, leaf), "Invalid merkle proof");
            return;
        }
        revert("Invalid burn item");
    }

        /**
     * Helper to validate the parameters for a burn redeem
     */
    function _validateParameters(IBurnRedeemCore.BurnRedeemParameters calldata burnRedeemParameters) internal pure {
        require(burnRedeemParameters.storageProtocol != IBurnRedeemCore.StorageProtocol.INVALID, "Storage protocol invalid");
        require(burnRedeemParameters.paymentReceiver != address(0), "Payment receiver required");
        require(burnRedeemParameters.endDate == 0 || burnRedeemParameters.startDate < burnRedeemParameters.endDate, "startDate after endDate");
        require(burnRedeemParameters.totalSupply % burnRedeemParameters.redeemAmount == 0, "Remainder left from totalSupply");
    }

    /**
     * Helper to set top level properties for a burn redeem
     */
    function _setParameters(IBurnRedeemCore.BurnRedeem storage burnRedeemInstance, IBurnRedeemCore.BurnRedeemParameters calldata burnRedeemParameters) private {
        burnRedeemInstance.startDate = burnRedeemParameters.startDate;
        burnRedeemInstance.endDate = burnRedeemParameters.endDate;
        burnRedeemInstance.redeemAmount = burnRedeemParameters.redeemAmount;
        burnRedeemInstance.totalSupply = burnRedeemParameters.totalSupply;
        burnRedeemInstance.storageProtocol = burnRedeemParameters.storageProtocol;
        burnRedeemInstance.location = burnRedeemParameters.location;
        burnRedeemInstance.cost = burnRedeemParameters.cost;
        burnRedeemInstance.paymentReceiver = burnRedeemParameters.paymentReceiver;
    }

    /**
     * Helper to set the burn groups for a burn redeem
     */
    function _setBurnGroups(IBurnRedeemCore.BurnRedeem storage burnRedeemInstance, IBurnRedeemCore.BurnGroup[] calldata burnGroups) private {
        delete burnRedeemInstance.burnSet;
        for (uint256 i; i < burnGroups.length;) {
            burnRedeemInstance.burnSet.push();
            IBurnRedeemCore.BurnGroup storage burnGroup = burnRedeemInstance.burnSet[i];
            require(
                burnGroups[i].requiredCount > 0 &&
                burnGroups[i].requiredCount <= burnGroups[i].items.length,
                "Invalid input"
            );
            burnGroup.requiredCount = burnGroups[i].requiredCount;
            for (uint256 j; j < burnGroups[i].items.length;) {
                IBurnRedeemCore.BurnItem memory burnItem = burnGroups[i].items[j];
                require(
                    (
                        (burnItem.tokenSpec == IBurnRedeemCore.TokenSpec.ERC1155 && burnItem.amount > 0) ||
                        (burnItem.tokenSpec == IBurnRedeemCore.TokenSpec.ERC721 && burnItem.amount == 0)
                    ) &&
                    burnItem.validationType != IBurnRedeemCore.ValidationType.INVALID,
                    "Invalid input");
                burnGroup.items.push(burnGroups[i].items[j]);
                unchecked { ++j; }
            }
            unchecked { ++i; }
        }
    }

}