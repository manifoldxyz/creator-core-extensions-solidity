// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@manifoldxyz/creator-core-solidity/contracts/core/IERC1155CreatorCore.sol";
import "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";
import "@manifoldxyz/creator-core-solidity/contracts/extensions/ICreatorExtensionTokenURI.sol";

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
contract ERC1155BurnRedeem is IERC165, IERC1155BurnRedeem, ICreatorExtensionTokenURI, ReentrancyGuard {
    // stores the number of burn redeem instances made by a given creator contract
    // used to determine the next burnRedeemIndex for a creator contract
    // { creatorContractAddress => burnRedeemCount }
    mapping(address => uint224) private _burnRedeemCounts;

    // stores mapping from tokenId to the burn redeem it represents
    // { creatorContractAddress => { tokenId => BurnRedeem } }
    mapping(address => mapping(uint256 => BurnRedeem)) private _burnRedeems;

    // { contractAddress => { tokenId => { redeemIndex } }
    mapping(address => mapping(uint256 => uint256)) private _redeemTokenIds;

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
        BurnRedeemParameters calldata burnRedeemParameters
    ) external override creatorAdminRequired(creatorContractAddress) returns (uint256) {
        // Sanity checks
        require(ERC165Checker.supportsInterface(burnRedeemParameters.burnTokenAddress, type(IERC1155CreatorCore).interfaceId), "burnTokenAddress must be a ERC1155Creator contract");
        require(burnRedeemParameters.endDate == 0 || burnRedeemParameters.startDate < burnRedeemParameters.endDate, "Cannot have startDate greater than or equal to endDate");
    
        // Get the index for the new burn redeem
        _burnRedeemCounts[creatorContractAddress]++;
        uint224 newIndex = _burnRedeemCounts[creatorContractAddress];

        // Mint one copy of token to self
        address[] memory minterAddress = new address[](1);
        minterAddress[0] = msg.sender;
        uint[] memory amount = new uint[](1);
        amount[0] = 1;
        string[] memory uris = new string[](1);
        uris[0] = "";

        // Mint new token on base contract, save which token that is for given burn redeem.
        uint[] memory tokenIds = IERC1155CreatorCore(creatorContractAddress).mintExtensionNew(minterAddress, amount, uris);
        _redeemTokenIds[creatorContractAddress][tokenIds[0]] = newIndex;

         // Create the burn redeem
        _burnRedeems[creatorContractAddress][newIndex] = BurnRedeem({
            burnTokenAddress: burnRedeemParameters.burnTokenAddress,
            burnTokenId: burnRedeemParameters.burnTokenId,
            burnAmount: burnRedeemParameters.burnAmount,
            redeemTokenId: tokenIds[0],
            redeemAmount: burnRedeemParameters.redeemAmount,
            redeemedCount: 0,
            totalSupply: burnRedeemParameters.totalSupply,
            startDate: burnRedeemParameters.startDate,
            endDate: burnRedeemParameters.endDate,
            uri: burnRedeemParameters.uri
        });
        
        emit BurnRedeemInitialized(creatorContractAddress, newIndex, msg.sender);
        return newIndex;
    }

    /**
     * See {IERC1155BurnRedeem-updateBurnRedeem}.
     */
    function updateBurnRedeem(
        address creatorContractAddress,
        uint256 index,
        BurnRedeemParameters calldata burnRedeemParameters
    ) external override creatorAdminRequired(creatorContractAddress) {
        // Sanity checks
        require(ERC165Checker.supportsInterface(burnRedeemParameters.burnTokenAddress, type(IERC1155).interfaceId), "burnTokenAddress must support ERC1155 interface");
        require(_burnRedeems[creatorContractAddress][index].burnTokenAddress != address(0), "Burn redeem not initialized");
        require(_burnRedeems[creatorContractAddress][index].totalSupply == 0 ||  _burnRedeems[creatorContractAddress][index].totalSupply <= burnRedeemParameters.totalSupply, "Cannot decrease totalSupply");
        require(burnRedeemParameters.endDate == 0 || burnRedeemParameters.startDate < burnRedeemParameters.endDate, "Cannot have startDate greater than or equal to endDate");

        // Overwrite the existing burnRedeem
        _burnRedeems[creatorContractAddress][index] = BurnRedeem({
            burnTokenAddress: burnRedeemParameters.burnTokenAddress,
            burnTokenId: burnRedeemParameters.burnTokenId,
            burnAmount: burnRedeemParameters.burnAmount,
            redeemTokenId: _burnRedeems[creatorContractAddress][index].redeemTokenId,
            redeemAmount: burnRedeemParameters.redeemAmount,
            redeemedCount: _burnRedeems[creatorContractAddress][index].redeemedCount,
            totalSupply: burnRedeemParameters.totalSupply,
            startDate: burnRedeemParameters.startDate,
            endDate: burnRedeemParameters.endDate,
            uri: burnRedeemParameters.uri
        });
    }

    /**
     * See {IERC1155BurnRedeem-getBurnRedeemCount}.
     */
    function getBurnRedeemCount(address creatorContractAddress) external override view returns(uint256) {
        return _burnRedeemCounts[creatorContractAddress];
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
        uint224 tokenBurnRedeem = uint224(_redeemTokenIds[creatorContractAddress][tokenId]);
        require(tokenBurnRedeem > 0, "Token does not exist");
        BurnRedeem memory burnRedeem = _burnRedeems[creatorContractAddress][tokenBurnRedeem];
        uri = burnRedeem.uri;
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
    ) external override nonReentrant returns(bytes4) {
        _onERC1155BatchReceived(from, ids, values, data);
        return this.onERC1155BatchReceived.selector;
    }

    /**
     * @notice ERC1155 token transfer callback
     * @param from      Burn/redeemer address
     * @param id        the token id of the burn token
     * @param value     the number of tokens to burn
     * @param data      bytes corresponding to the targeted burn redeem action(s), formatted [address creatorContractAddress, uint256 index, uint256 amount, ...]
     */
    function _onERC1155Received(
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) private {
        // Check calldata is valid
        require(data.length % 96 == 0, "Invalid data");
        uint256 amountRequired = 0;

         // Iterate over calldata
        for (uint i = 0; i * 96 < data.length; i++) {
            // Read calldata
            BurnRedeemCallData memory current;
            (current.creatorContractAddress, current.index, current.amount) = abi.decode(data[i*96:(i+1)*96], (address, uint256, uint256));

            BurnRedeem storage burnRedeem = _burnRedeems[current.creatorContractAddress][current.index];

            require(burnRedeem.startDate == 0 || burnRedeem.startDate < block.timestamp, "Transaction before start date");
            require(burnRedeem.endDate == 0 || burnRedeem.endDate >= block.timestamp, "Transaction after end date");

            uint256 amountToRedeem = burnRedeem.redeemAmount * current.amount;

            require(burnRedeem.totalSupply == 0 || burnRedeem.redeemedCount + amountToRedeem <= burnRedeem.totalSupply, "Maximum tokens already minted for this burn redeem");

            // Check if received token is eligible
            require(burnRedeem.burnTokenAddress == msg.sender && burnRedeem.burnTokenId == id, "Token not eligible");

            amountRequired += burnRedeem.burnAmount * current.amount;

            address[] memory minterAddress = new address[](1);
            minterAddress[0] = from;
            uint256[] memory redeemAmounts = new uint[](1);
            redeemAmounts[0] = amountToRedeem;
            uint256[] memory redeemTokenIds = new uint[](1);
            redeemTokenIds[0] = burnRedeem.redeemTokenId;

            unchecked{ burnRedeem.redeemedCount += uint32(amountToRedeem); }

            // Do mint
            IERC1155CreatorCore(current.creatorContractAddress).mintExtensionExisting(minterAddress, redeemTokenIds, redeemAmounts);

            emit BurnRedeemMint(current.creatorContractAddress, redeemTokenIds[0], redeemAmounts[0]);
        }

        require(amountRequired == value, "Invalid value sent");

        // Do burn
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = id;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = value;
        IERC1155CreatorCore(msg.sender).burn(address(this), tokenIds, amounts);
    }
    
    /**
     * @notice ERC1155 batch token transfer callback
     * @param from      Burn/redeemer address
     * @param ids       a list of the token ids of the burn token
     * @param values    a list of the number of tokens to burn for each id
     * @param data      bytes corresponding to the targeted burn redeem action(s), formatted [address creatorContractAddress, uint256 index, uint256 amount, ...]
     *                  note: the data parameter must be in the same order as the ids and values parameters
     */
    function _onERC1155BatchReceived(
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) private {
        // Check calldata is valid
        require(data.length % 96 == 0, "Invalid data");

        // Used to iterate over ids and values
        uint256 currentIndex = 0;

        uint256 remainingValue = values[0];

        // Iterate over calldata
        for (uint i = 0; i * 96 < data.length; i++) {
            // Read calldata
            BurnRedeemCallData memory current;
            (current.creatorContractAddress, current.index, current.amount) = abi.decode(data[i*96:(i+1)*96], (address, uint256, uint256));

            BurnRedeem storage burnRedeem = _burnRedeems[current.creatorContractAddress][current.index];

            require(burnRedeem.startDate == 0 || burnRedeem.startDate < block.timestamp, "Transaction before start date");
            require(burnRedeem.endDate == 0 || burnRedeem.endDate >= block.timestamp, "Transaction after end date");

            uint256 amountRequired = burnRedeem.burnAmount * current.amount;
            uint256 amountToRedeem = burnRedeem.redeemAmount * current.amount;

            if (ids[currentIndex] != burnRedeem.burnTokenId) {
                require(remainingValue == 0, "Invalid values");
                unchecked{
                    currentIndex++;
                    remainingValue = values[currentIndex];
                }
            }

            require(burnRedeem.totalSupply == 0 || burnRedeem.redeemedCount + amountToRedeem <= burnRedeem.totalSupply, "Maximum tokens already minted for this burn redeem");

            // Check if the token has been received
            require(
                burnRedeem.burnTokenAddress == msg.sender &&
                ids[currentIndex] == burnRedeem.burnTokenId &&
                remainingValue - amountRequired < remainingValue,
                "Token not eligible");

            remainingValue = remainingValue - amountRequired;

            address[] memory minterAddress = new address[](1);
            minterAddress[0] = from;
            uint256[] memory redeemAmounts = new uint[](1);
            redeemAmounts[0] = amountToRedeem;
            uint256[] memory redeemTokenIds = new uint[](1);
            redeemTokenIds[0] = burnRedeem.redeemTokenId;

            unchecked{ burnRedeem.redeemedCount += uint32(amountToRedeem); }

            // Do mint
            IERC1155CreatorCore(current.creatorContractAddress).mintExtensionExisting(minterAddress, redeemTokenIds, redeemAmounts);

            emit BurnRedeemMint(current.creatorContractAddress, redeemTokenIds[0], redeemAmounts[0]);
        }
        require(remainingValue == 0, "Invalid values");

        // Do burn
        IERC1155CreatorCore(msg.sender).burn(address(this), ids, values);
    }
}
