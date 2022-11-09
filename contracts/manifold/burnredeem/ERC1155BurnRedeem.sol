// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC1155CreatorCore.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/ICreatorExtensionTokenURI.sol";
import "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";

import "@openzeppelin/contracts/interfaces/IERC165.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import "./IERC1155BurnRedeem.sol";

/**
 * @title Burn Redeem
 * @author manifold.xyz
 * @notice Burn Redeem shared extension for Manifold Studio.
 */
contract ERC1155BurnRedeem is IERC165, IERC1155BurnRedeem, ICreatorExtensionTokenURI {
    using Strings for uint256;

    string private constant ARWEAVE_PREFIX = "https://arweave.net/";
    string private constant IPFS_PREFIX = "ipfs://";
    uint256 private constant MAX_UINT_256 = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    uint256[] private MAX_TOKEN_ID;
    string[] private EMPTY_URI;

    // stores mapping from tokenId to the burn redeem it represents
    // { creatorContractAddress => { tokenId => BurnRedeem } }
    mapping(address => mapping(uint256 => BurnRedeem)) private _burnRedeems;

    // { contractAddress => { tokenId => { redeemIndex } }
    mapping(address => mapping(uint256 => uint256)) private _redeemTokenIds;

    constructor() {
        MAX_TOKEN_ID = [MAX_UINT_256];
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165) returns (bool) {
        return interfaceId == type(IERC1155BurnRedeem).interfaceId ||
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
        AdminControl creatorCoreContract = AdminControl(creatorContractAddress);
        require(creatorCoreContract.isAdmin(msg.sender), "Wallet is not an administrator for contract");
        _;
    }

    /**
     * See {IERC1155BurnRedeem-initializeBurnRedeem}.
     */
    function initializeBurnRedeem(
        address creatorContractAddress,
        uint256 index,
        BurnRedeemParameters calldata burnRedeemParameters
    ) external override creatorAdminRequired(creatorContractAddress) {
        // Revert if burnRedeem at index already exists
        require(_burnRedeems[creatorContractAddress][index].burnTokenAddress == address(0), "Burn redeem already initialized");

        // Sanity checks
        require(ERC165Checker.supportsInterface(burnRedeemParameters.burnTokenAddress, type(IERC1155CreatorCore).interfaceId), "burnTokenAddress must be a ERC1155Creator contract");
        require(burnRedeemParameters.endDate == 0 || burnRedeemParameters.startDate < burnRedeemParameters.endDate, "Cannot have startDate greater than or equal to endDate");

         // Create the burn redeem
        _burnRedeems[creatorContractAddress][index] = BurnRedeem({
            redeemTokenId: MAX_TOKEN_ID,
            burnTokenId: burnRedeemParameters.burnTokenId,
            burnTokenAddress: burnRedeemParameters.burnTokenAddress,
            startDate: burnRedeemParameters.startDate,
            endDate: burnRedeemParameters.endDate,
            burnAmount: burnRedeemParameters.burnAmount,
            redeemAmount: burnRedeemParameters.redeemAmount,
            redeemedCount: 0,
            totalSupply: burnRedeemParameters.totalSupply,
            storageProtocol: burnRedeemParameters.storageProtocol,
            location: burnRedeemParameters.location
        });
        
        emit BurnRedeemInitialized(creatorContractAddress, index, msg.sender);
    }

    /**
     * See {IERC1155BurnRedeem-updateBurnRedeem}.
     */
    function updateBurnRedeem(
        address creatorContractAddress,
        uint256 index,
        BurnRedeemParameters calldata burnRedeemParameters
    ) external override creatorAdminRequired(creatorContractAddress) {
        BurnRedeem memory burnRedeem = _burnRedeems[creatorContractAddress][index];
        // Sanity checks
        require(ERC165Checker.supportsInterface(burnRedeemParameters.burnTokenAddress, type(IERC1155).interfaceId), "burnTokenAddress must support ERC1155 interface");
        require(burnRedeem.burnTokenAddress != address(0), "Burn redeem not initialized");
        require(burnRedeem.totalSupply == 0 ||  burnRedeem.totalSupply <= burnRedeemParameters.totalSupply, "Cannot decrease totalSupply");
        require(burnRedeemParameters.endDate == 0 || burnRedeemParameters.startDate < burnRedeemParameters.endDate, "Cannot have startDate greater than or equal to endDate");

        // Overwrite the existing burnRedeem
        _burnRedeems[creatorContractAddress][index] = BurnRedeem({
            redeemTokenId:burnRedeem.redeemTokenId,
            burnTokenId: burnRedeemParameters.burnTokenId,
            burnTokenAddress: burnRedeemParameters.burnTokenAddress,
            startDate: burnRedeemParameters.startDate,
            endDate: burnRedeemParameters.endDate,
            burnAmount: burnRedeemParameters.burnAmount,
            redeemAmount: burnRedeemParameters.redeemAmount,
            redeemedCount: burnRedeem.redeemedCount,
            totalSupply: burnRedeemParameters.totalSupply,
            storageProtocol: burnRedeemParameters.storageProtocol,
            location: burnRedeemParameters.location
        });
    }

    /**
     * See {IERC1155BurnRedeem-getBurnRedeem}.
     */
    function getBurnRedeem(address creatorContractAddress, uint256 index) external override view returns(BurnRedeem memory) {
        require(_burnRedeems[creatorContractAddress][index].burnTokenAddress != address(0), "Burn redeem not initialized");
        return _burnRedeems[creatorContractAddress][index];
    }

    /**
     * See {IERC1155BurnRedeem-isEligible}.
     */
    function isEligible(address wallet, address creatorContractAddress, uint256 index) external override view returns(uint256) {
        BurnRedeem memory burnRedeem = _burnRedeems[creatorContractAddress][index];
        uint256 burnNumberOwned = IERC1155(burnRedeem.burnTokenAddress).balanceOf(wallet, burnRedeem.burnTokenId);
        return (burnRedeem.burnAmount / burnNumberOwned) * burnRedeem.redeemAmount;
    }

    /**
     * See {ICreatorExtensionTokenURI-tokenURI}.
     */
    function tokenURI(address creatorContractAddress, uint256 tokenId) external override view returns(string memory uri) {
        uint256 tokenBurnRedeem = _redeemTokenIds[creatorContractAddress][tokenId];
        require(tokenBurnRedeem > 0, "Token does not exist");
        BurnRedeem memory burnRedeem = _burnRedeems[creatorContractAddress][tokenBurnRedeem];

        string memory prefix = "";
        if (burnRedeem.storageProtocol == StorageProtocol.ARWEAVE) {
            prefix = ARWEAVE_PREFIX;
        } else if (burnRedeem.storageProtocol == StorageProtocol.IPFS) {
            prefix = IPFS_PREFIX;
        }
        uri = string(abi.encodePacked(prefix, burnRedeem.location));
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
     * @notice ERC1155 token transfer callback
     * @param from      the person sending the tokens
     * @param id        the token id of the burn token
     * @param value     the number of tokens to burn
     * @param data      bytes corresponding to the targeted burn redeem action(s), formatted [address mintTo (does not repeat), address creatorContractAddress, uint256 index, uint256 amount, ...]
     */
    function _onERC1155Received(
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) private {
        // Check calldata is valid
        require(data.length % 96 == 32, "Invalid data");
        uint256 redemptionCount = (data.length - 32)/96;

        address[] memory minterAddress = new address[](1);
        minterAddress[0] = abi.decode(data[0:32], (address));
        uint256[] memory redemptionAmount = new uint256[](1);

         // Iterate over calldata and validate
        uint256 amountRequired = 0;
        for (uint256 i = 0; i < redemptionCount;) {
            // Read calldata
            (address creatorContractAddress, uint256 index, uint32 amount) = abi.decode(data[32+i*96:32+(i+1)*96], (address, uint256, uint32));

            (BurnRedeem storage burnRedeem, uint256 burnAmount, uint256 amountToRedeem) = _retrieveActiveBurnRedeem(creatorContractAddress, index, id, amount);

            // Do mint if needed
            if (amountToRedeem > 0) {
                amountRequired += burnAmount;
                redemptionAmount[0] = amountToRedeem;
                _mintRedeem(creatorContractAddress, index, burnRedeem, minterAddress, redemptionAmount);
                emit BurnRedeemMint(creatorContractAddress, burnRedeem.redeemTokenId[0],amountToRedeem, msg.sender, id);
            }
            unchecked { ++i; }
        }
        require(amountRequired <= value, "Invalid value sent");
        require(amountRequired > 0, "None available");

        // Do burn
        if (amountRequired > 0) {
            uint256[] memory tokenIds = new uint256[](1);
            tokenIds[0] = id;
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = amountRequired;
            IERC1155CreatorCore(msg.sender).burn(address(this), tokenIds, amounts);
        }

        // Return remaining tokens
        if (amountRequired < value) {
            IERC1155(msg.sender).safeTransferFrom(address(this), from, id, value-amountRequired, "");
        }
    }

    /**
     * @notice ERC1155 batch token transfer callbackx
     * @param ids       a list of the token ids of the burn token
     * @param values    a list of the number of tokens to burn for each id
     * @param data      bytes corresponding to the targeted burn redeem action(s), formatted [address mintTo (does not repeat), address creatorContractAddress, uint256 index, uint256 amount, ...]
     *                  note: the data parameter must be in the same order as the ids and values parameters
     */
    function _onERC1155BatchReceived(
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) private {
        // Check calldata is valid
        require(data.length % 96 == 32, "Invalid data");
        uint256 redemptionCount = (data.length - 32)/96;
        require(redemptionCount == ids.length, "Invalid data");

        address[] memory minterAddress = new address[](1);
        minterAddress[0] = abi.decode(data[0:32], (address));
        uint256[] memory redemptionAmount = new uint256[](1);

        // Track excess values
        uint256[] memory consumedValues = new uint256[](redemptionCount);
        uint256[] memory remainingValues = new uint256[](redemptionCount);

        // Track if tokens were redeemed
        bool tokensRedeemed = false;
        bool excessValues = false;

        // Iterate over calldata
        for (uint256 i = 0; i < redemptionCount;) {
            // Read calldata
            (address creatorContractAddress, uint256 index, uint32 amount) = abi.decode(data[32+i*96:32+(i+1)*96], (address, uint256, uint32));

            (BurnRedeem storage burnRedeem, uint256 burnAmount, uint256 amountToRedeem) = _retrieveActiveBurnRedeem(creatorContractAddress, index, ids[i], amount);

            // Do mint if needed
            if (amountToRedeem > 0) {
                // Store consumed and excess values
                consumedValues[i] = burnAmount;
                if (burnAmount != values[i]) {
                    remainingValues[i] = values[i] - burnAmount;
                    excessValues = true;
                }
                // Store values for mint
                redemptionAmount[0] = amountToRedeem;
                tokensRedeemed = true;
                _mintRedeem(creatorContractAddress, index, burnRedeem, minterAddress, redemptionAmount);
                emit BurnRedeemMint(creatorContractAddress, burnRedeem.redeemTokenId[0], amountToRedeem, msg.sender, ids[i]);
            }
            unchecked { ++i; }
        }

        require(tokensRedeemed, "None available");

        if (excessValues) {
            for (uint256 i = 0; i < redemptionCount; i++) {
                if (remainingValues[i] > 0) {
                    IERC1155(msg.sender).safeTransferFrom(address(this), from, ids[i], remainingValues[i], "");
                }
            }
        }

        // Do burn
        IERC1155CreatorCore(msg.sender).burn(address(this), ids, consumedValues);
    }

    /**
     * Mint a redemption
     */
    function _mintRedeem(address creatorContractAddress, uint256 index, BurnRedeem storage burnRedeem, address[] memory minterAddress, uint256[] memory redeemAmounts) private {
        if (burnRedeem.redeemTokenId[0] == MAX_UINT_256) {
            // No token minted yet, mint new token
            burnRedeem.redeemTokenId = IERC1155CreatorCore(creatorContractAddress).mintExtensionNew(minterAddress, redeemAmounts, EMPTY_URI);
            _redeemTokenIds[creatorContractAddress][burnRedeem.redeemTokenId[0]] = index;
        } else {
            IERC1155CreatorCore(creatorContractAddress).mintExtensionExisting(minterAddress, burnRedeem.redeemTokenId, redeemAmounts);
        }
    }

    /**
     * Returns active burn redeem, amount to burn and amount of redemptions that can occur
     */
    function _retrieveActiveBurnRedeem(address creatorContractAddress, uint256 index, uint256 burnTokenId, uint256 amount) private returns(BurnRedeem storage burnRedeem, uint256 burnAmount, uint256 amountToRedeem) {
        burnRedeem = _burnRedeems[creatorContractAddress][index];
        require(burnRedeem.startDate == 0 || burnRedeem.startDate < block.timestamp, "Transaction before start date");
        require(burnRedeem.endDate == 0 || burnRedeem.endDate >= block.timestamp, "Transaction after end date");
        require(burnRedeem.burnTokenAddress == msg.sender && burnRedeem.burnTokenId == burnTokenId, "Token not eligible");
        if (burnRedeem.totalSupply > 0 && burnRedeem.redeemedCount < burnRedeem.totalSupply) {
            amountToRedeem = burnRedeem.redeemAmount * amount;
            burnAmount = burnRedeem.burnAmount * amount;
            // Too many requested, consume the remaining
            if (burnRedeem.redeemedCount + amountToRedeem > burnRedeem.totalSupply) {
                amountToRedeem = burnRedeem.totalSupply - burnRedeem.redeemedCount;
                burnAmount = amountToRedeem/burnRedeem.burnAmount;
            }
            unchecked{ burnRedeem.redeemedCount += uint32(amountToRedeem); }
        }
    }
}
