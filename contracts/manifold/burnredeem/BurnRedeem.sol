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

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC721CreatorCore.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/ICreatorExtensionTokenURI.sol";
import "@manifoldxyz/libraries-solidity/contracts/access/IAdminControl.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import "./IBurnRedeem.sol";
import "./BurnInterfaces.sol";

/**
 * @title Burn Redeem
 * @author manifold.xyz
 * @notice Burn Redeem shared extension.
 */
abstract contract BurnRedeem is IERC165, IBurnRedeem, ICreatorExtensionTokenURI {
    using Strings for uint256;

    string internal constant ARWEAVE_PREFIX = "https://arweave.net/";
    string internal constant IPFS_PREFIX = "ipfs://";

    // { creatorContractAddress => { index => BurnRedeem } }
    mapping(address => mapping(uint256 => BurnRedeem)) internal _burnRedeems;

    // { contractAddress => { tokenId => { redeemIndex } }
    mapping(address => mapping(uint256 => RedeemToken)) internal _redeemTokens;

    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165) returns (bool) {
        return interfaceId == type(IBurnRedeem).interfaceId ||
            interfaceId == type(IERC721Receiver).interfaceId ||
            interfaceId == type(IERC1155Receiver).interfaceId ||
            interfaceId == type(ICreatorExtensionTokenURI).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
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
        uint256 index,
        BurnRedeemParameters calldata burnRedeemParameters
    ) internal {
        BurnRedeem storage _burnRedeem = _burnRedeems[creatorContractAddress][index];
        // Revert if burnRedeem at index already exists
        require(_burnRedeem.storageProtocol == StorageProtocol.INVALID, "Burn redeem already initialized");

        // Sanity check
        require(burnRedeemParameters.endDate == 0 || burnRedeemParameters.startDate < burnRedeemParameters.endDate, "startDate after endDate");

        // Create the burn redeem
        _setParameters(_burnRedeem, burnRedeemParameters);
        _setBurnGroups(_burnRedeem, burnRedeemParameters.burnSet);

        emit BurnRedeemInitialized(creatorContractAddress, index, msg.sender);
    }

    /**
     * Updates a burn redeem with base parameters
     */
    function _update(
        address creatorContractAddress,
        uint256 index,
        BurnRedeemParameters calldata burnRedeemParameters
    ) internal {
        BurnRedeem storage _burnRedeem = _burnRedeems[creatorContractAddress][index];

        // Sanity checks
        require(_burnRedeem.storageProtocol != StorageProtocol.INVALID, "Burn redeem not initialized");
        require(burnRedeemParameters.endDate == 0 || burnRedeemParameters.startDate < burnRedeemParameters.endDate, "startDate after endDate");

        // Overwrite the existing burnRedeem
        _setParameters(_burnRedeem, burnRedeemParameters);
        _setBurnGroups(_burnRedeem, burnRedeemParameters.burnSet);
    }

    /**
     * See {IBurnRedeem-getBurnRedeem}.
     */
    function getBurnRedeem(address creatorContractAddress, uint256 index) external override view returns(BurnRedeem memory) {
        require(_burnRedeems[creatorContractAddress][index].storageProtocol != StorageProtocol.INVALID, "Burn redeem not initialized");
        return _burnRedeems[creatorContractAddress][index];
    }

    /**
     * See {IBurnRedeem-burnRedeem}.
     */
    function burnRedeem(address creatorContractAddress, uint256 index, BurnToken[] calldata burnTokens) external payable override {
        BurnRedeem storage _burnRedeem = _burnRedeems[creatorContractAddress][index];
        _validateBurnRedeem(_burnRedeem);

        // Do burn redeem
        _burnTokens(_burnRedeem, burnTokens, msg.sender);
        _mint(creatorContractAddress, index, _burnRedeem, msg.sender);
    }

    /**
     * Burn all listed tokens and check that the burn set is satisfied
     */
    function _burnTokens(BurnRedeem storage _burnRedeem, BurnToken[] memory burnTokens, address account) private {
        // Check that each group in the burn set is satisfied
        uint256[] memory groupCounts = new uint256[](_burnRedeem.burnSet.length);

        for (uint256 i = 0; i < burnTokens.length; i++) {
            BurnToken memory burnToken = burnTokens[i];
            BurnItem memory burnItem = _burnRedeem.burnSet[burnToken.groupIndex].items[burnToken.itemIndex];

            _validateBurnItem(burnItem, burnToken.contractAddress, burnToken.id, burnToken.merkleProof);
            _burn(burnItem, account, burnToken.contractAddress, burnToken.id);

            groupCounts[burnToken.groupIndex] += 1;
        }

        for (uint256 i = 0; i < groupCounts.length; i++) {
            require(groupCounts[i] == _burnRedeem.burnSet[i].requiredCount, "Invalid number of tokens");
        }
    }

    /**
     * @dev See {IERC721Receiver-onERC721Received}.
     */
    function onERC721Received(
        address,
        address from,
        uint256 id,
        bytes calldata data
    ) external override returns(bytes4) {
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
    ) external override returns(bytes4) {
        _onERC1155Received(from, id, value, data);
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
    ) external override returns(bytes4) {
        _onERC1155BatchReceived(from, ids, values, data);
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
        uint256 burnRedeemIndex;
        uint256 burnItemIndex;
        bytes32[] memory merkleProof;
        (creatorContractAddress, burnRedeemIndex, burnItemIndex, merkleProof) = abi.decode(data, (address, uint256, uint256, bytes32[]));

        BurnRedeem storage _burnRedeem = _burnRedeems[creatorContractAddress][burnRedeemIndex];

        _validateBurnRedeem(_burnRedeem);
        require(
            _burnRedeem.burnSet.length == 1 &&
            _burnRedeem.burnSet[0].requiredCount == 1,
            "Not a 1:1 burn redeem"
        );

        // Check that the burn token is valid
        BurnItem memory burnItem = _burnRedeem.burnSet[0].items[burnItemIndex];
        _validateBurnItem(burnItem, msg.sender, id, merkleProof);

        // Do burn redeem
        _burn(burnItem, address(this), msg.sender, id);
        _mint(creatorContractAddress, burnRedeemIndex, _burnRedeem, from);
    }

    /**
     * @notice ERC1155 token transfer callback
     * @param from      the person sending the tokens
     * @param id        the token id of the burn token
     * @param value     the amount of tokens being sent
     * @param data      bytes indicating the target burnRedeem and, optionally, a merkle proof that the token is valid
     */
    function _onERC1155Received(
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) private {
        // Check calldata is valid
        require(data.length % 32 == 0, "Invalid data");

        address creatorContractAddress;
        uint256 burnRedeemIndex;
        uint256 burnItemIndex;
        bytes32[] memory merkleProof;
        (creatorContractAddress, burnRedeemIndex, burnItemIndex, merkleProof) = abi.decode(data, (address, uint256, uint256, bytes32[]));

        BurnRedeem storage _burnRedeem = _burnRedeems[creatorContractAddress][burnRedeemIndex];

        _validateBurnRedeem(_burnRedeem);
        require(
            _burnRedeem.burnSet.length == 1 &&
            _burnRedeem.burnSet[0].requiredCount == 1,
            "Not a 1:1 burn redeem"
        );

        // Check that the burn token is valid
        BurnItem memory burnItem = _burnRedeem.burnSet[0].items[burnItemIndex];
        require(value == burnItem.amount, "Invalid amount");
        _validateBurnItem(burnItem, msg.sender, id, merkleProof);

        // Do burn redeem
        _burn(burnItem, address(this), msg.sender, id);
        _mint(creatorContractAddress, burnRedeemIndex, _burnRedeem, from);
    }

    /**
     * @notice ERC1155 batch token transfer callbackx
     * @param ids       a list of the token ids of the burn token
     * @param values    a list of the number of tokens to burn for each id
     * @param data      bytes indicating the target burnRedeem and BurnTokens to burn
     */
    function _onERC1155BatchReceived(
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) private {
        // Check calldata is valid
        require(data.length % 32 == 0, "Invalid data");

        address creatorContractAddress;
        uint256 burnRedeemIndex;
        BurnToken[] memory burnTokens;
        (creatorContractAddress, burnRedeemIndex, burnTokens) = abi.decode(data, (address, uint256, BurnToken[]));

        BurnRedeem storage _burnRedeem = _burnRedeems[creatorContractAddress][burnRedeemIndex];

        _validateBurnRedeem(_burnRedeem);

        for (uint256 i = 0; i < burnTokens.length; i++) {
            BurnToken memory burnToken = burnTokens[i];
            BurnItem memory burnItem = _burnRedeem.burnSet[burnToken.groupIndex].items[burnToken.itemIndex];
            require(burnToken.id == ids[i], "Invalid token");
            require(burnItem.amount == values[i], "Invalid amount");
        }

        // Do burn redeem
        _burnTokens(_burnRedeem, burnTokens, address(this));
        _mint(creatorContractAddress, burnRedeemIndex, _burnRedeem, from);
    }

    /**
     * Helper to set top level properties for a burn redeem
     */
    function _setParameters(BurnRedeem storage _burnRedeem, BurnRedeemParameters calldata burnRedeemParameters) private {
        _burnRedeem.startDate = burnRedeemParameters.startDate;
        _burnRedeem.endDate = burnRedeemParameters.endDate;
        _burnRedeem.totalSupply = burnRedeemParameters.totalSupply;
        _burnRedeem.storageProtocol = burnRedeemParameters.storageProtocol;
        _burnRedeem.location = burnRedeemParameters.location;
        _burnRedeem.cost = burnRedeemParameters.cost;
    }

    /**
     * Helper to set the burn groups for a burn redeem
     */
    function _setBurnGroups(BurnRedeem storage _burnRedeem, BurnGroup[] calldata burnGroups) private {
        delete _burnRedeem.burnSet;
        for (uint256 i = 0; i < burnGroups.length; i++) {
            _burnRedeem.burnSet.push();
            BurnGroup storage burnGroup = _burnRedeem.burnSet[i];
            burnGroup.requiredCount = burnGroups[i].requiredCount;
            for (uint256 j = 0; j < burnGroups[i].items.length; j++) {
                burnGroup.items.push(burnGroups[i].items[j]);
            }
        }
    }

    /**
     * Helper to validate target burn redeem
     */
    function _validateBurnRedeem(BurnRedeem storage _burnRedeem) private {
        require(_burnRedeem.storageProtocol != StorageProtocol.INVALID, "Burn redeem not initialized");
        require(msg.value == _burnRedeem.cost, "Invalid value sent");
        require(
            _burnRedeem.startDate <= block.timestamp && 
            (block.timestamp < _burnRedeem.endDate || _burnRedeem.endDate == 0),
            "Burn redeem not active"
        );
        require(
            _burnRedeem.totalSupply == 0 ||
            _burnRedeem.redeemedCount < _burnRedeem.totalSupply,
            "No tokens available"
        );
    }

    /**
     * Helper to validate burn item
     */
    function _validateBurnItem(BurnItem memory burnItem, address contractAddress, uint256 tokenId, bytes32[] memory merkleProof) private pure {
        require(contractAddress == burnItem.contractAddress, "Invalid burn token");
        if (burnItem.validationType == ValidationType.CONTRACT) {
            return;
        } else if (burnItem.validationType == ValidationType.RANGE) {
            require(tokenId >= burnItem.minTokenId && tokenId <= burnItem.maxTokenId, "Invalid token ID");
            return;
        } else if (burnItem.validationType == ValidationType.MERKLE_TREE) {
            bytes32 leaf = keccak256(abi.encodePacked(tokenId));
            require(MerkleProof.verify(merkleProof, burnItem.merkleRoot, leaf), "Invalid merkle proof");
            return;
        }
        revert("Invalid burn item");
    }

    /** 
     * Abstract helper to mint redeem token. To be implemented by inheriting contracts.
     */
    function _mint(address creatorContractAddress, uint256 index, BurnRedeem storage _burnRedeem, address to) internal virtual;

    /**
     * Helper to burn token
     */
    function _burn(BurnItem memory burnItem, address from, address contractAddress, uint256 tokenId) private {
        if (burnItem.tokenSpec == TokenSpec.ERC1155) {
            uint256 amount = burnItem.amount;

            if (burnItem.burnSpec == BurnSpec.NONE) {
                // Send to 0xdEaD to burn if contract doesn't have burn function
                ERC1155(contractAddress).safeTransferFrom(from, address(0xdEaD), tokenId, amount, "");

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
            if (burnItem.burnSpec == BurnSpec.NONE) {
                // Send to 0xdEaD to burn if contract doesn't have burn function
                ERC721(contractAddress).safeTransferFrom(from, address(0xdEaD), tokenId, "");

            } else if (burnItem.burnSpec == BurnSpec.MANIFOLD || burnItem.burnSpec == BurnSpec.OPENZEPPELIN) {
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
