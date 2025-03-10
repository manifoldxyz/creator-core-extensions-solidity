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
import "./IBurnRedeemCoreV2.sol";

/**
 * @title Burn Redeem Lib V2
 * @author manifold.xyz
 * @notice Library for Burn Redeem shared extensions.
 */
library BurnRedeemLibV2 {

    event BurnRedeemInitialized(address indexed creatorContract, uint256 indexed instanceId, address initializer);
    event BurnRedeemUpdated(address indexed creatorContract, uint256 indexed instanceId);
    event BurnRedeemMint(address indexed creatorContract, uint256 indexed instanceId, uint256 indexed tokenId, uint32 redeemedCount, bytes data);

    error BurnRedeemAlreadyInitialized();
    error InvalidBurnItem();
    error InvalidBurnToken();
    error InvalidMerkleProof();
    error InvalidStorageProtocol();
    error InvalidPaymentReceiver();
    error InvalidDates();
    error InvalidInput();

    /**
     * Initialiazes a burn redeem with base parameters
     */
    function initialize(
        address creatorContractAddress,
        uint8 creatorContractVersion,
        uint256 instanceId,
        IBurnRedeemCoreV2.BurnRedeem storage burnRedeemInstance,
        IBurnRedeemCoreV2.BurnRedeemParameters calldata burnRedeemParameters
    ) public {
        // Sanity checks
        if (burnRedeemInstance.storageProtocol != IBurnRedeemCoreV2.StorageProtocol.INVALID) {
            revert BurnRedeemAlreadyInitialized();
        }
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
        IBurnRedeemCoreV2.BurnRedeem storage burnRedeemInstance,
        IBurnRedeemCoreV2.BurnRedeemParameters calldata burnRedeemParameters
    ) public {
        // Sanity checks
        if (burnRedeemInstance.storageProtocol == IBurnRedeemCoreV2.StorageProtocol.INVALID) {
            revert IBurnRedeemCoreV2.BurnRedeemDoesNotExist(instanceId);
        }
        _validateParameters(burnRedeemParameters);
        // The current redeemedCount must be divisible by redeemAmount
        if (burnRedeemInstance.redeemedCount % burnRedeemParameters.redeemAmount != 0) {
            revert IBurnRedeemCoreV2.InvalidRedeemAmount();
        }

        // Overwrite the existing burnRedeem
        _setParameters(burnRedeemInstance, burnRedeemParameters);
        _setBurnGroups(burnRedeemInstance, burnRedeemParameters.burnSet);
        syncTotalSupply(burnRedeemInstance);
        emit BurnRedeemUpdated(creatorContractAddress, instanceId);
    }

    /**
     * Helper to update total supply if redeemedCount exceeds totalSupply after airdrop or instance update.
     */
    function syncTotalSupply(IBurnRedeemCoreV2.BurnRedeem storage burnRedeemInstance) public {
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
    function validateBurnItem(IBurnRedeemCoreV2.BurnItem memory burnItem, address contractAddress, uint256 tokenId, bytes32[] memory merkleProof) public pure {
        if (burnItem.validationType == IBurnRedeemCoreV2.ValidationType.ANY) {
            return;
        }
        if (contractAddress != burnItem.contractAddress) {
            revert InvalidBurnToken();
        }
        if (burnItem.validationType == IBurnRedeemCoreV2.ValidationType.CONTRACT) {
            return;
        } else if (burnItem.validationType == IBurnRedeemCoreV2.ValidationType.RANGE) {
            if (tokenId < burnItem.minTokenId || tokenId > burnItem.maxTokenId) {
                revert IBurnRedeemCoreV2.InvalidToken(tokenId);
            }
            return;
        } else if (burnItem.validationType == IBurnRedeemCoreV2.ValidationType.MERKLE_TREE) {
            bytes32 leaf = keccak256(abi.encodePacked(tokenId));
            if (!MerkleProof.verify(merkleProof, burnItem.merkleRoot, leaf)) {
                revert InvalidMerkleProof();
            }
            return;
        }
        revert InvalidBurnItem();
    }

    /**
     * Helper to validate the parameters for a burn redeem
     */
    function _validateParameters(IBurnRedeemCoreV2.BurnRedeemParameters calldata burnRedeemParameters) internal pure {
        if (burnRedeemParameters.storageProtocol == IBurnRedeemCoreV2.StorageProtocol.INVALID) {
            revert InvalidStorageProtocol();
        }
        if (burnRedeemParameters.paymentReceiver == address(0)) {
            revert InvalidPaymentReceiver();
        }
        if (burnRedeemParameters.endDate != 0 && burnRedeemParameters.startDate >= burnRedeemParameters.endDate) {
            revert InvalidDates();
        }
        if (burnRedeemParameters.totalSupply % burnRedeemParameters.redeemAmount != 0) {
            revert IBurnRedeemCoreV2.InvalidRedeemAmount();
        }
    }

    /**
     * Helper to set top level properties for a burn redeem
     */
    function _setParameters(IBurnRedeemCoreV2.BurnRedeem storage burnRedeemInstance, IBurnRedeemCoreV2.BurnRedeemParameters calldata burnRedeemParameters) private {
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
    function _setBurnGroups(IBurnRedeemCoreV2.BurnRedeem storage burnRedeemInstance, IBurnRedeemCoreV2.BurnGroup[] calldata burnGroups) private {
        delete burnRedeemInstance.burnSet;
        for (uint256 i; i < burnGroups.length;) {
            burnRedeemInstance.burnSet.push();
            IBurnRedeemCoreV2.BurnGroup storage burnGroup = burnRedeemInstance.burnSet[i];
            if (burnGroups[i].requiredCount == 0 || burnGroups[i].requiredCount > burnGroups[i].items.length) {
                revert InvalidInput();
            }
            burnGroup.requiredCount = burnGroups[i].requiredCount;
            for (uint256 j; j < burnGroups[i].items.length;) {
                IBurnRedeemCoreV2.BurnItem memory burnItem = burnGroups[i].items[j];
                IBurnRedeemCoreV2.TokenSpec tokenSpec = burnItem.tokenSpec;
                uint256 amount = burnItem.amount;
                if (
                    !(
                        (tokenSpec == IBurnRedeemCoreV2.TokenSpec.ERC1155 && amount > 0) ||
                        (tokenSpec == IBurnRedeemCoreV2.TokenSpec.ERC721 && amount == 0)
                    ) || 
                    burnItem.validationType == IBurnRedeemCoreV2.ValidationType.INVALID
                ) {
                    revert InvalidInput();
                }
                burnGroup.items.push(burnGroups[i].items[j]);
                unchecked { ++j; }
            }
            unchecked { ++i; }
        }
    }

}