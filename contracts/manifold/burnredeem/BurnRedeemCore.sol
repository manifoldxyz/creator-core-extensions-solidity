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

import "@manifoldxyz/creator-core-solidity/contracts/extensions/ICreatorExtensionTokenURI.sol";
import "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";
import "@manifoldxyz/libraries-solidity/contracts/access/IAdminControl.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import "../../libraries/manifold-membership/IManifoldMembership.sol";
import "./BurnRedeemLib.sol";
import "./IBurnRedeemCore.sol";
import "./Interfaces.sol";

/**
 * @title Burn Redeem Core
 * @author manifold.xyz
 * @notice Core logic for Burn Redeem shared extensions.
 */
abstract contract BurnRedeemCore is ERC165, AdminControl, ReentrancyGuard, IBurnRedeemCore, ICreatorExtensionTokenURI {
    using Strings for uint256;

    uint256 public constant BURN_FEE = 690000000000000;
    uint256 public constant MULTI_BURN_FEE = 990000000000000;

    string internal constant ARWEAVE_PREFIX = "https://arweave.net/";
    string internal constant IPFS_PREFIX = "ipfs://";

    uint256 internal constant MAX_UINT_16 = 0xffff;
    uint256 internal constant MAX_UINT_24 = 0xffffff;
    uint256 internal constant MAX_UINT_32 = 0xffffffff;
    uint256 internal constant MAX_UINT_56 = 0xffffffffffffff;
    uint256 internal constant MAX_UINT_256 = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    // { creatorContractAddress => { instanceId => BurnRedeem } }
    mapping(address => mapping(uint256 => BurnRedeem)) internal _burnRedeems;

    address public manifoldMembershipContract;

    constructor(address initialOwner) {
        _transferOwnership(initialOwner);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, ERC165, AdminControl) returns (bool) {
        return interfaceId == type(IBurnRedeemCore).interfaceId ||
            interfaceId == type(IERC721Receiver).interfaceId ||
            interfaceId == type(IERC1155Receiver).interfaceId ||
            interfaceId == type(ICreatorExtensionTokenURI).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @notice This extension is shared, not single-creator. So we must ensure
     * that a burn redeems's initializer is an admin on the creator contract
     * @param creatorContractAddress    the address of the creator contract to check the admin against
     */
    modifier creatorAdminRequired(address creatorContractAddress) {
        require(IAdminControl(creatorContractAddress).isAdmin(msg.sender), "Wallet is not an admin");
        _;
    }

    /**
     * Initialiazes a burn redeem with base parameters
     */
    function _initialize(
        address creatorContractAddress,
        uint8 creatorContractVersion,
        uint256 instanceId,
        BurnRedeemParameters calldata burnRedeemParameters
    ) internal {
        BurnRedeemLib.initialize(creatorContractAddress, creatorContractVersion, instanceId, _burnRedeems[creatorContractAddress][instanceId], burnRedeemParameters);
    }

    /**
     * Updates a burn redeem with base parameters
     */
    function _update(
        address creatorContractAddress,
        uint256 instanceId,
        BurnRedeemParameters calldata burnRedeemParameters
    ) internal {
        BurnRedeemLib.update(creatorContractAddress, instanceId, _getBurnRedeem(creatorContractAddress, instanceId), burnRedeemParameters);
    }

    /**
     * See {IBurnRedeemCore-getBurnRedeem}.
     */
    function getBurnRedeem(address creatorContractAddress, uint256 instanceId) external override view returns(BurnRedeem memory) {
        return _getBurnRedeem(creatorContractAddress, instanceId);
    }

    /**
     * Helper to get burn redeem instance
     */
    function _getBurnRedeem(address creatorContractAddress, uint256 instanceId) internal view returns(BurnRedeem storage burnRedeemInstance) {
        burnRedeemInstance = _burnRedeems[creatorContractAddress][instanceId];
        require(burnRedeemInstance.storageProtocol != StorageProtocol.INVALID, "Burn redeem not initialized");
    }

    /**
     * Helper to get active burn redeem instance
     */
    function _getActiveBurnRedeem(address creatorContractAddress, uint256 instanceId) private view returns(BurnRedeem storage burnRedeemInstance) {
        burnRedeemInstance = _burnRedeems[creatorContractAddress][instanceId];
        require(burnRedeemInstance.storageProtocol != StorageProtocol.INVALID, "Burn redeem not initialized");
        require(
            burnRedeemInstance.startDate <= block.timestamp && 
            (block.timestamp < burnRedeemInstance.endDate || burnRedeemInstance.endDate == 0),
            "Burn redeem not active"
        );
    }

    /**
     * See {IBurnRedeemCore-burnRedeem}.
     */
    function burnRedeem(address creatorContractAddress, uint256 instanceId, uint32 burnRedeemCount, BurnToken[] calldata burnTokens) external payable override nonReentrant {
        uint256 payableCost = _burnRedeem(msg.value, creatorContractAddress, instanceId, burnRedeemCount, burnTokens, _isActiveMember(msg.sender), true);
        if (msg.value > payableCost) {
            _forwardValue(payable(msg.sender), msg.value - payableCost);
        }
    }

    /**
     * (Batch overload) see {IBurnRedeemCore-burnRedeem}.
     */
    function burnRedeem(address[] calldata creatorContractAddresses, uint256[] calldata instanceIds, uint32[] calldata burnRedeemCounts, BurnToken[][] calldata burnTokens) external payable override nonReentrant {
        require(
            creatorContractAddresses.length == instanceIds.length &&
            creatorContractAddresses.length == burnRedeemCounts.length &&
            creatorContractAddresses.length == burnTokens.length,
            "Invalid calldata"
        );

        bool isActiveMember = _isActiveMember(msg.sender);
        uint256 msgValueRemaining = msg.value;
        for (uint256 i; i < creatorContractAddresses.length;) {
            msgValueRemaining -= _burnRedeem(msgValueRemaining, creatorContractAddresses[i], instanceIds[i], burnRedeemCounts[i], burnTokens[i], isActiveMember, false);
            unchecked { ++i; }
        }

        if (msgValueRemaining != 0) {
            _forwardValue(payable(msg.sender), msgValueRemaining);
        }
    }

    /**
     * See {IBurnRedeemCore-airdrop}.
     */
    function airdrop(address creatorContractAddress, uint256 instanceId, address[] calldata recipients, uint32[] calldata amounts) external override creatorAdminRequired(creatorContractAddress) {
        require(recipients.length == amounts.length, "Invalid calldata");
        BurnRedeem storage burnRedeemInstance = _getBurnRedeem(creatorContractAddress, instanceId);

        uint256 totalAmount;
        for (uint256 i; i < amounts.length;) {
            totalAmount += amounts[i] * burnRedeemInstance.redeemAmount;
            unchecked{ ++i; }
        }
        require(
            totalAmount + burnRedeemInstance.redeemedCount <= MAX_UINT_32,
            "Invalid amount"
        );

        // Airdrop the tokens
        for (uint256 i; i < recipients.length;) {
            _redeem(creatorContractAddress, instanceId, burnRedeemInstance, recipients[i], amounts[i]);
            unchecked{ ++i; }
        }

        BurnRedeemLib.syncTotalSupply(burnRedeemInstance);
    }

    function _burnRedeem(uint256 msgValue, address creatorContractAddress, uint256 instanceId, uint32 burnRedeemCount, BurnToken[] calldata burnTokens, bool isActiveMember, bool revertNoneRemaining) private returns (uint256) {
        BurnRedeem storage burnRedeemInstance = _getActiveBurnRedeem(creatorContractAddress, instanceId);

        // Get the amount that can be burned
        burnRedeemCount = _getAvailableBurnRedeemCount(burnRedeemInstance.totalSupply, burnRedeemInstance.redeemedCount, burnRedeemInstance.redeemAmount, burnRedeemCount);
        if (burnRedeemCount == 0) {
            if (revertNoneRemaining) revert("No tokens available");
            return 0;
        }

        uint256 payableCost = burnRedeemInstance.cost;
        uint256 cost = burnRedeemInstance.cost;
        if (!isActiveMember) {
            payableCost += _getManifoldFee(burnTokens.length);
        }
        if (burnRedeemCount > 1) {
            payableCost *= burnRedeemCount;
            cost *= burnRedeemCount;
        }
        require(msgValue >= payableCost, "Invalid amount");
        if (cost > 0) {
            _forwardValue(burnRedeemInstance.paymentReceiver, cost);
        }

        // Do burn redeem
        _burnTokens(burnRedeemInstance, burnTokens, burnRedeemCount, msg.sender);
        _redeem(creatorContractAddress, instanceId, burnRedeemInstance, msg.sender, burnRedeemCount);

        return payableCost;
    }

    /**
     * @dev See {IBurnRedeemCore-recoverERC721}.
     */
    function recoverERC721(address tokenAddress, uint256 tokenId, address destination) external override adminRequired {
        IERC721(tokenAddress).transferFrom(address(this), destination, tokenId);
    }

    /**
     * @dev See {IBurnRedeemCore-withdraw}.
     */
    function withdraw(address payable recipient, uint256 amount) external override adminRequired {
        (bool sent, ) = recipient.call{value: amount}("");
        require(sent, "Failed to transfer to recipient");
    }

    /**
     * @dev See {IBurnRedeemCore-setManifoldMembership}.
     */
    function setMembershipAddress(address addr) external override adminRequired {
        manifoldMembershipContract = addr;
    }

    /**
     * @dev See {IERC721Receiver-onERC721Received}.
     */
    function onERC721Received(
        address,
        address from,
        uint256 id,
        bytes calldata data
    ) external override nonReentrant returns(bytes4) {
        _onERC721Received(from, id, data);
        return this.onERC721Received.selector;
    }

    /**
     * @dev See {IERC1155Receiver-onERC1155Received}.
     */
    function onERC1155Received(
        address,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external override nonReentrant returns(bytes4) {
        // Check calldata is valid
        require(data.length % 32 == 0, "Invalid data");

        address creatorContractAddress;
        uint256 instanceId;
        uint32 burnRedeemCount;
        uint256 burnItemIndex;
        bytes32[] memory merkleProof;
        (creatorContractAddress, instanceId, burnRedeemCount, burnItemIndex, merkleProof) = abi.decode(data, (address, uint256, uint32, uint256, bytes32[]));

        // Do burn redeem
        _onERC1155Received(from, id, value, creatorContractAddress, instanceId, burnRedeemCount, burnItemIndex, merkleProof);

        return this.onERC1155Received.selector;
    }

    /**
     * @dev See {IERC1155Receiver-onERC1155BatchReceived}.
     */
    function onERC1155BatchReceived(
        address,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external override nonReentrant returns(bytes4) {
        // Check calldata is valid
        require(data.length % 32 == 0, "Invalid data");

        address creatorContractAddress;
        uint256 instanceId;
        uint32 burnRedeemCount;
        BurnToken[] memory burnTokens;
        (creatorContractAddress, instanceId, burnRedeemCount, burnTokens) = abi.decode(data, (address, uint256, uint32, BurnToken[]));

        // Do burn redeem
        _onERC1155BatchReceived(from, ids, values, creatorContractAddress, instanceId, burnRedeemCount, burnTokens);

        return this.onERC1155BatchReceived.selector;
    }

    /**
     * @notice ERC721 token transfer callback
     * @param from      the person sending the tokens
     * @param id        the token id of the burn token
     * @param data      bytes indicating the target burnRedeem and, optionally, a merkle proof that the token is valid
     */
    function _onERC721Received(
        address from,
        uint256 id,
        bytes calldata data
    ) private {
        // Check calldata is valid
        require(data.length % 32 == 0, "Invalid data");

        address creatorContractAddress;
        uint256 instanceId;
        uint256 burnItemIndex;
        bytes32[] memory merkleProof;
        (creatorContractAddress, instanceId, burnItemIndex, merkleProof) = abi.decode(data, (address, uint256, uint256, bytes32[]));

        BurnRedeem storage burnRedeemInstance = _getActiveBurnRedeem(creatorContractAddress, instanceId);

        // A single ERC721 can only be sent in directly for a burn if:
        // 1. There is no cost to the burn (because no payment can be sent with a transfer)
        // 2. The burn only requires one NFT (one burnSet element and one count)
        // 3. They are an active member (because no fee payment can be sent with a transfer)
        require(
            burnRedeemInstance.cost == 0 &&
            burnRedeemInstance.burnSet.length == 1 &&
            burnRedeemInstance.burnSet[0].requiredCount == 1 &&
            _isActiveMember(from),
            "Invalid input"
        );

        uint256 burnRedeemCount = _getAvailableBurnRedeemCount(burnRedeemInstance.totalSupply, burnRedeemInstance.redeemedCount, burnRedeemInstance.redeemAmount, 1);
        require(burnRedeemCount != 0, "No tokens available");

        // Check that the burn token is valid
        BurnItem memory burnItem = burnRedeemInstance.burnSet[0].items[burnItemIndex];

        // Can only take in one burn item
        require(burnItem.tokenSpec == TokenSpec.ERC721, "Invalid input");
        BurnRedeemLib.validateBurnItem(burnItem, msg.sender, id, merkleProof);

        // Do burn and redeem
        _burn(burnItem, address(this), msg.sender, id, 1);
        _redeem(creatorContractAddress, instanceId, burnRedeemInstance, from, 1);
    }

    /**
     * Execute onERC1155Received burn/redeem
     */
    function _onERC1155Received(address from, uint256 tokenId, uint256 value, address creatorContractAddress, uint256 instanceId, uint32 burnRedeemCount, uint256 burnItemIndex, bytes32[] memory merkleProof) private {
        BurnRedeem storage burnRedeemInstance = _getActiveBurnRedeem(creatorContractAddress, instanceId);

        // A single 1155 can only be sent in directly for a burn if:
        // 1. There is no cost to the burn (because no payment can be sent with a transfer)
        // 2. The burn only requires one NFT (one burn set element and one required count in the set)
        // 3. They are an active member (because no fee payment can be sent with a transfer)
        require(
            burnRedeemInstance.cost == 0 &&
            burnRedeemInstance.burnSet.length == 1 &&
            burnRedeemInstance.burnSet[0].requiredCount == 1 &&
            _isActiveMember(from),
            "Invalid input"
        );

        uint32 availableBurnRedeemCount = _getAvailableBurnRedeemCount(burnRedeemInstance.totalSupply, burnRedeemInstance.redeemedCount, burnRedeemInstance.redeemAmount, burnRedeemCount);
        require(availableBurnRedeemCount != 0, "No tokens available");

        // Check that the burn token is valid
        BurnItem memory burnItem = burnRedeemInstance.burnSet[0].items[burnItemIndex];
        require(value == burnItem.amount * burnRedeemCount, "Invalid input");
        BurnRedeemLib.validateBurnItem(burnItem, msg.sender, tokenId, merkleProof);

        _burn(burnItem, address(this), msg.sender, tokenId, availableBurnRedeemCount);
        _redeem(creatorContractAddress, instanceId, burnRedeemInstance, from, availableBurnRedeemCount);

        // Return excess amount
        if (availableBurnRedeemCount != burnRedeemCount) {
            IERC1155(msg.sender).safeTransferFrom(address(this), from, tokenId, (burnRedeemCount - availableBurnRedeemCount) * burnItem.amount, "");
        }
    }

    /**
     * Execute onERC1155BatchReceived burn/redeem
     */
    function _onERC1155BatchReceived(address from, uint256[] memory tokenIds, uint256[] memory values, address creatorContractAddress, uint256 instanceId, uint32 burnRedeemCount, BurnToken[] memory burnTokens) private {
        BurnRedeem storage burnRedeemInstance = _getActiveBurnRedeem(creatorContractAddress, instanceId);

        // A single 1155 can only be sent in directly for a burn if:
        // 1. There is no cost to the burn (because no payment can be sent with a transfer)
        // 2. We have the right data length
        // 3. They are an active member (because no fee payment can be sent with a transfer)
        require(
            burnRedeemInstance.cost == 0 &&
            burnTokens.length == tokenIds.length &&
            _isActiveMember(from),
            "Invalid input"
        );
        uint32 availableBurnRedeemCount = _getAvailableBurnRedeemCount(burnRedeemInstance.totalSupply, burnRedeemInstance.redeemedCount, burnRedeemInstance.redeemAmount, burnRedeemCount);
        require(availableBurnRedeemCount != 0, "No tokens available");

        // Verify the values match what is needed
        uint256[] memory returnValues = new uint256[](tokenIds.length);
        for (uint256 i; i < burnTokens.length;) {
            BurnToken memory burnToken = burnTokens[i];
            BurnItem memory burnItem = burnRedeemInstance.burnSet[burnToken.groupIndex].items[burnToken.itemIndex];
            require(burnToken.id == tokenIds[i], "Invalid token");
            require(burnItem.amount * burnRedeemCount == values[i], "Invalid amount");
            if (availableBurnRedeemCount != burnRedeemCount) {
                returnValues[i] = values[i] - burnItem.amount * availableBurnRedeemCount;
            }
            unchecked { ++i; }
        }

        // Do burn redeem
        _burnTokens(burnRedeemInstance, burnTokens, availableBurnRedeemCount, address(this));
        _redeem(creatorContractAddress, instanceId, burnRedeemInstance, from, availableBurnRedeemCount);

        // Return excess amount
        if (availableBurnRedeemCount != burnRedeemCount) {
            IERC1155(msg.sender).safeBatchTransferFrom(address(this), from, tokenIds, returnValues, "");
        }
    }

    /**
     * Send funds to receiver
     */
    function _forwardValue(address payable receiver, uint256 amount) private {
        (bool sent, ) = receiver.call{value: amount}("");
        require(sent, "Failed to transfer to recipient");
    }

    /**
     * Burn all listed tokens and check that the burn set is satisfied
     */
    function _burnTokens(BurnRedeem storage burnRedeemInstance, BurnToken[] memory burnTokens, uint256 burnRedeemCount, address owner) private {
        // Check that each group in the burn set is satisfied
        uint256[] memory groupCounts = new uint256[](burnRedeemInstance.burnSet.length);

        for (uint256 i; i < burnTokens.length;) {
            BurnToken memory burnToken = burnTokens[i];
            BurnItem memory burnItem = burnRedeemInstance.burnSet[burnToken.groupIndex].items[burnToken.itemIndex];

            BurnRedeemLib.validateBurnItem(burnItem, burnToken.contractAddress, burnToken.id, burnToken.merkleProof);

            _burn(burnItem, owner, burnToken.contractAddress, burnToken.id, burnRedeemCount);
            groupCounts[burnToken.groupIndex] += burnRedeemCount;

            unchecked { ++i; }
        }

        for (uint256 i; i < groupCounts.length;) {
            require(groupCounts[i] == burnRedeemInstance.burnSet[i].requiredCount * burnRedeemCount, "Invalid number of tokens");
            unchecked { ++i; }
        }
    }


    /**
     * Helper to get the Manifold fee for the sender
     */
    function _getManifoldFee(uint256 burnTokenCount) private pure returns(uint256 fee) {
        fee = burnTokenCount <= 1 ? BURN_FEE : MULTI_BURN_FEE;
    }

    /**
     * Helper to check if the sender holds an active Manifold membership
     */
    function _isActiveMember(address sender) private view returns(bool) {
        return manifoldMembershipContract != address(0) &&
            IManifoldMembership(manifoldMembershipContract).isActiveMember(sender);
    }

    /**
     * Helper to get the number of burn redeems the person can accomplish
     */
    function _getAvailableBurnRedeemCount(uint32 totalSupply, uint32 redeemedCount, uint32 redeemAmount, uint32 desiredCount) internal pure returns(uint32 burnRedeemCount) {
        if (totalSupply == 0) {
            burnRedeemCount = desiredCount;
        } else {
            uint32 remainingCount = (totalSupply - redeemedCount) / redeemAmount;
            if (remainingCount > desiredCount) {
                burnRedeemCount = desiredCount;
            } else {
                burnRedeemCount = remainingCount;
            }
        }
    }

    /** 
     * Abstract helper to mint multiple redeem tokens. To be implemented by inheriting contracts.
     */
    function _redeem(address creatorContractAddress, uint256 instanceId, BurnRedeem storage burnRedeemInstance, address to, uint32 count) internal virtual;

    /**
     * Helper to burn token
     */
    function _burn(BurnItem memory burnItem, address from, address contractAddress, uint256 tokenId, uint256 burnRedeemCount) private {
        if (burnItem.tokenSpec == TokenSpec.ERC1155) {
            uint256 amount = burnItem.amount * burnRedeemCount;

            if (burnItem.burnSpec == BurnSpec.NONE) {
                // Send to 0xdEaD to burn if contract doesn't have burn function
                IERC1155(contractAddress).safeTransferFrom(from, address(0xdEaD), tokenId, amount, "");

            } else if (burnItem.burnSpec == BurnSpec.MANIFOLD) {
                // Burn using the creator core's burn function
                uint256[] memory tokenIds = new uint256[](1);
                tokenIds[0] = tokenId;
                uint256[] memory amounts = new uint256[](1);
                amounts[0] = amount;
                Manifold1155(contractAddress).burn(from, tokenIds, amounts);

            } else if (burnItem.burnSpec == BurnSpec.OPENZEPPELIN) {
                // Burn using OpenZeppelin's burn function
                OZBurnable1155(contractAddress).burn(from, tokenId, amount);

            } else {
                revert("Invalid burn spec");
            }
        } else if (burnItem.tokenSpec == TokenSpec.ERC721) {
            require(burnRedeemCount == 1, "Invalid burn count");
            if (burnItem.burnSpec == BurnSpec.NONE) {
                // Send to 0xdEaD to burn if contract doesn't have burn function
                IERC721(contractAddress).safeTransferFrom(from, address(0xdEaD), tokenId, "");

            } else if (burnItem.burnSpec == BurnSpec.MANIFOLD || burnItem.burnSpec == BurnSpec.OPENZEPPELIN) {
                if (from != address(this)) {
                    // 721 `burn` functions do not have a `from` parameter, so we must verify the owner
                    require(IERC721(contractAddress).ownerOf(tokenId) == from, "Sender is not owner");
                }
                // Burn using the contract's burn function
                Burnable721(contractAddress).burn(tokenId);

            } else {
                revert("Invalid burn spec");
            }
        } else {
            revert("Invalid token spec");
        }
    }
}
