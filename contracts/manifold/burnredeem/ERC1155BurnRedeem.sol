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
    using Strings for uint256;

    string private constant ARWEAVE_PREFIX = "https://arweave.net/";
    string private constant IPFS_PREFIX = "ipfs://";

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
        require(ERC165Checker.supportsInterface(burnRedeemParameters.burnableTokenAddress, type(IERC1155CreatorCore).interfaceId), "burnableTokenAddress must be a ERC1155Creator contract");
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
            burnableTokenAddress: burnRedeemParameters.burnableTokenAddress,
            burnableTokenId: burnRedeemParameters.burnableTokenId,
            burnAmount: burnRedeemParameters.burnAmount,
            redeemableTokenId: tokenIds[0],
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
        require(ERC165Checker.supportsInterface(burnRedeemParameters.burnableTokenAddress, type(IERC1155).interfaceId), "burnableTokenAddress must support ERC1155 interface");
        require(_burnRedeems[creatorContractAddress][index].burnableTokenAddress != address(0), "Burn redeem not initialized");
        require(_burnRedeems[creatorContractAddress][index].totalSupply == 0 ||  _burnRedeems[creatorContractAddress][index].totalSupply <= burnRedeemParameters.totalSupply, "Cannot decrease totalSupply");
        require(burnRedeemParameters.endDate == 0 || burnRedeemParameters.startDate < burnRedeemParameters.endDate, "Cannot have startDate greater than or equal to endDate");

        // Overwrite the existing burnRedeem
        _burnRedeems[creatorContractAddress][index] = BurnRedeem({
            burnableTokenAddress: burnRedeemParameters.burnableTokenAddress,
            burnableTokenId: burnRedeemParameters.burnableTokenId,
            burnAmount: burnRedeemParameters.burnAmount,
            redeemableTokenId: _burnRedeems[creatorContractAddress][index].redeemableTokenId,
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
        require(_burnRedeems[creatorContractAddress][index].burnableTokenAddress != address(0), "Burn redeem not initialized");
        return _burnRedeems[creatorContractAddress][index];
    }

    /**
     * See {IERC1155BurnRedeem-mint}.
     */
    function mint(address creatorContractAddress, uint256 index, uint32 amount) external override {
        BurnRedeem storage burnRedeem = _burnRedeems[creatorContractAddress][index];
        // Safely retrieve the burn redeem
        require(burnRedeem.burnableTokenAddress != address(0), "Burn redeem not initialized");

        // Check timestamps
        require(burnRedeem.startDate == 0 || burnRedeem.startDate < block.timestamp, "Transaction before start date");
        require(burnRedeem.endDate == 0 || burnRedeem.endDate >= block.timestamp, "Transaction after end date");

        uint256 amountToBurn = burnRedeem.burnAmount * amount;
        uint256 amountToRedeem = burnRedeem.redeemAmount * amount;

        // Check totalSupply
        require(burnRedeem.totalSupply == 0 || burnRedeem.redeemedCount + amountToRedeem <= burnRedeem.totalSupply, "Maximum tokens already minted for this burn redeem");

        // Do burn
        uint256[] memory burnTokenIds = new uint256[](1);
        burnTokenIds[0] = burnRedeem.redeemableTokenId;
        uint256[] memory burnAmount = new uint256[](1);
        burnAmount[0] = amountToBurn;
        IERC1155CreatorCore(burnRedeem.burnableTokenAddress).burn(msg.sender, burnTokenIds, burnAmount);

        unchecked{ burnRedeem.redeemedCount++; }

        address[] memory minterAddress = new address[](1);
        minterAddress[0] = msg.sender;
        uint256[] memory redeemAmount = new uint[](1);
        redeemAmount[0] = burnRedeem.redeemAmount * amount;
        uint256[] memory redeemTokenIds = new uint[](1);
        redeemTokenIds[0] = burnRedeem.redeemableTokenId;

        // Do mint
        IERC1155CreatorCore(creatorContractAddress).mintExtensionExisting(minterAddress, redeemTokenIds, redeemAmount);

        emit BurnRedeemMint(creatorContractAddress, _redeemTokenIds[creatorContractAddress][index], redeemAmount[0]);
    }

    /**
     * See {IERC1155BurnRedeem-isEligible}.
     */
    function isEligible(address wallet, address creatorContractAddress, uint256 index) external override view returns(uint256) {
        BurnRedeem memory burnRedeem = _burnRedeems[creatorContractAddress][index];
        uint256 burnableNumberOwned = IERC1155(burnRedeem.burnableTokenAddress).balanceOf(wallet, burnRedeem.burnableTokenId);
        return (burnRedeem.burnAmount / burnableNumberOwned) * burnRedeem.redeemAmount;
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
}
