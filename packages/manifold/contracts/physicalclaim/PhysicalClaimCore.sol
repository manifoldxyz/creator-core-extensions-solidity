// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";
import "@manifoldxyz/libraries-solidity/contracts/access/IAdminControl.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import "./PhysicalClaimLib.sol";
import "./IPhysicalClaimCore.sol";
import "./Interfaces.sol";

/**
 * @title Physical Claim Core
 * @author manifold.xyz
 * @notice Core logic for Physical Claim shared extensions.
 */
abstract contract PhysicalClaimCore is ERC165, AdminControl, ReentrancyGuard, IPhysicalClaimCore {
    using Strings for uint256;

    uint256 internal constant MAX_UINT_16 = 0xffff;
    uint256 internal constant MAX_UINT_56 = 0xffffffffffffff;

    // { instanceId => PhysicalClaim }
    mapping(uint256 => PhysicalClaim) internal _physicalClaims;

    // { instanceId => creator } -> TODO: make it so multiple people can administer a physical claim
    mapping(uint256 => address) internal _physicalClaimCreator;

    // { instanceId => { redeemer => Redemption } }
    mapping(uint256 => mapping(address => Redemption[])) internal _redemptions;

    constructor(address initialOwner) {
        _transferOwnership(initialOwner);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, ERC165, AdminControl) returns (bool) {
        return interfaceId == type(IPhysicalClaimCore).interfaceId ||
            interfaceId == type(IERC721Receiver).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * Initialiazes a physical claim with base parameters
     */
    function _initialize(
        uint256 instanceId,
        PhysicalClaimParameters calldata physicalClaimParameters
    ) internal {
        _physicalClaimCreator[instanceId] = msg.sender;
        PhysicalClaimLib.initialize(instanceId, _physicalClaims[instanceId], physicalClaimParameters);
    }

    /**
     * Updates a physical claim with base parameters
     */
    function _update(
        uint256 instanceId,
        PhysicalClaimParameters calldata physicalClaimParameters
    ) internal {
        PhysicalClaimLib.update(instanceId, _getPhysicalClaim(instanceId), physicalClaimParameters);
    }

    /**
     * Validates that this physical claim is managed by the user
     */
     function _validateAdmin(
        uint256 instanceId
     ) internal view {
        require(_physicalClaimCreator[instanceId] == msg.sender, "Must be admin");
     }

    /**
     * See {IPhysicalClaimCore-getPhysicalClaim}.
     */
    function getPhysicalClaim(uint256 instanceId) external override view returns(PhysicalClaim memory) {
        return _getPhysicalClaim(instanceId);
    }

    /**
     * Helper to get physical claim instance
     */
    function _getPhysicalClaim(uint256 instanceId) internal view returns(PhysicalClaim storage physicalClaimInstance) {
        physicalClaimInstance = _physicalClaims[instanceId];
        if (physicalClaimInstance.paymentReceiver == address(0)) {
            revert InvalidInstance();
        }
    }

    /**
     * (Batch overload) see {IPhysicalClaimCore-burnRedeem}.
     */
    function burnRedeem(PhysicalClaimSubmission[] calldata submissions) external payable override nonReentrant {
        uint256 msgValueRemaining = msg.value;
        for (uint256 i; i < submissions.length;) {
            msgValueRemaining -= _burnRedeem(msgValueRemaining, submissions[i].instanceId, submissions[i].physicalClaimCount, submissions[i].burnTokens, submissions[i].variation, submissions[i].data);
            unchecked { ++i; }
        }

        if (msgValueRemaining != 0) {
            _forwardValue(payable(msg.sender), msgValueRemaining);
        }
    }

    function _burnRedeem(uint256 msgValue, uint256 instanceId, uint32 physicalClaimCount, BurnToken[] calldata burnTokens, uint8 variation, bytes memory data) private returns (uint256) {
        PhysicalClaim storage physicalClaimInstance = _getPhysicalClaim(instanceId);

        // Get the amount that can be burned
        physicalClaimCount = _getAvailablePhysicalClaimCount(physicalClaimInstance.totalSupply, physicalClaimInstance.redeemedCount, physicalClaimCount);

        uint256 payableCost = physicalClaimInstance.cost;
        uint256 cost = physicalClaimInstance.cost;

        if (physicalClaimCount > 1) {
            payableCost *= physicalClaimCount;
            cost *= physicalClaimCount;
        }
        if (payableCost > msgValue) {
            revert InvalidPaymentAmount();
        }
        if (cost > 0) {
            _forwardValue(physicalClaimInstance.paymentReceiver, cost);
        }

        // Do physical claim
        _burnTokens(physicalClaimInstance, burnTokens, physicalClaimCount, msg.sender, data);
        _redeem(instanceId, physicalClaimInstance, msg.sender, physicalClaimCount, variation, data);

        return payableCost;
    }

    /**
     * @dev See {IPhysicalClaimCore-recover}.
     */
    function recover(address tokenAddress, uint256 tokenId, address destination) external override adminRequired {
        IERC721(tokenAddress).transferFrom(address(this), destination, tokenId);
    }

    /**
     * @dev See {IERC721Receiver-onReceived}.
     */
    function onERC721Received(
        address,
        address from,
        uint256 id,
        bytes calldata data
    ) external override nonReentrant returns(bytes4) {
        _onReceived(from, id, data);
        return this.onERC721Received.selector;
    }

    /**
     * @notice  token transfer callback
     * @param from      the person sending the tokens
     * @param id        the token id of the burn token
     * @param data      bytes indicating the target burnRedeem and, optionally, a merkle proof that the token is valid
     */
    function _onReceived(
        address from,
        uint256 id,
        bytes calldata data
    ) private {
        // Check calldata is valid
        if (data.length % 32 != 0) {
            revert InvalidData();
        }

        uint256 instanceId;
        uint256 burnItemIndex;
        bytes32[] memory merkleProof;
        uint8 variation;
        (instanceId, burnItemIndex, merkleProof, variation) = abi.decode(data, (uint256, uint256, bytes32[], uint8));

        PhysicalClaim storage physicalClaimInstance = _getPhysicalClaim(instanceId);

        // A single  can only be sent in directly for a burn if:
        // 1. There is no cost to the burn (because no payment can be sent with a transfer)
        // 2. The burn only requires one NFT (one burnSet element and one count)
        _validateReceivedInput(physicalClaimInstance.cost, physicalClaimInstance.burnSet.length, physicalClaimInstance.burnSet[0].requiredCount, from);

        _getAvailablePhysicalClaimCount(physicalClaimInstance.totalSupply, physicalClaimInstance.redeemedCount, 1);

        // Check that the burn token is valid
        BurnItem memory burnItem = physicalClaimInstance.burnSet[0].items[burnItemIndex];

        // Can only take in one burn item
        if (burnItem.tokenSpec != TokenSpec.ERC721) {
            revert InvalidInput();
        }
        PhysicalClaimLib.validateBurnItem(burnItem, msg.sender, id, merkleProof);

        // Do burn and redeem
        _burn(burnItem, address(this), msg.sender, id, 1, "");
        _redeem(instanceId, physicalClaimInstance, from, 1, variation, "");
    }

    function _validateReceivedInput(uint256 cost, uint256 length, uint256 requiredCount, address from) private view {
        if (cost != 0 || length != 1 || requiredCount != 1) {
            revert InvalidInput();
        }
    }

    /**
     * Send funds to receiver
     */
    function _forwardValue(address payable receiver, uint256 amount) private {
        (bool sent, ) = receiver.call{value: amount}("");
        if (!sent) {
            revert TransferFailure();
        }
    }

    /**
     * Burn all listed tokens and check that the burn set is satisfied
     */
    function _burnTokens(PhysicalClaim storage burnRedeemInstance, BurnToken[] memory burnTokens, uint256 burnRedeemCount, address owner, bytes memory data) private {
        // Check that each group in the burn set is satisfied
        uint256[] memory groupCounts = new uint256[](burnRedeemInstance.burnSet.length);

        for (uint256 i; i < burnTokens.length;) {
            BurnToken memory burnToken = burnTokens[i];
            BurnItem memory burnItem = burnRedeemInstance.burnSet[burnToken.groupIndex].items[burnToken.itemIndex];

            PhysicalClaimLib.validateBurnItem(burnItem, burnToken.contractAddress, burnToken.id, burnToken.merkleProof);

            _burn(burnItem, owner, burnToken.contractAddress, burnToken.id, burnRedeemCount, data);
            groupCounts[burnToken.groupIndex] += burnRedeemCount;

            unchecked { ++i; }
        }

        for (uint256 i; i < groupCounts.length;) {
            if (groupCounts[i] != burnRedeemInstance.burnSet[i].requiredCount * burnRedeemCount) {
                revert InvalidBurnAmount2();
            }
            unchecked { ++i; }
        }
    }

    /**
     * Helper to get the number of burn redeems the person can accomplish
     */
    function _getAvailablePhysicalClaimCount(uint32 totalSupply, uint32 redeemedCount, uint32 desiredCount) internal pure returns(uint32 burnRedeemCount) {
        if (totalSupply == 0) {
            burnRedeemCount = desiredCount;
        } else {
            uint32 remainingCount = (totalSupply - redeemedCount);
            if (remainingCount > desiredCount) {
                burnRedeemCount = desiredCount;
            } else {
                burnRedeemCount = remainingCount;
            }
        }

        if (burnRedeemCount == 0) {
            revert InvalidRedeemAmount();
        }
    }

    /**
     * Helper to burn token
     */
    function _burn(BurnItem memory burnItem, address from, address contractAddress, uint256 tokenId, uint256 burnRedeemCount, bytes memory data) private {
        if (burnItem.tokenSpec == TokenSpec.ERC721) {
            if (burnRedeemCount != 1) {
                revert InvalidBurnAmount();
            } 
            if (burnItem.burnSpec == BurnSpec.NONE) {
                // Send to 0xdEaD to burn if contract doesn't have burn function
                IERC721(contractAddress).safeTransferFrom(from, address(0xdEaD), tokenId, data);

            } else if (burnItem.burnSpec == BurnSpec.MANIFOLD || burnItem.burnSpec == BurnSpec.OPENZEPPELIN) {
                if (from != address(this)) {
                    // 721 `burn` functions do not have a `from` parameter, so we must verify the owner
                    if (IERC721(contractAddress).ownerOf(tokenId) != from) {
                        revert TransferFailure();
                    }
                }
                // Burn using the contract's burn function
                Burnable721(contractAddress).burn(tokenId);

            } else {
                revert InvalidBurnSpec();
            }
        } else {
            revert InvalidTokenSpec();
        }
    }

    /** 
     * Helper to redeem multiple rede
     */
    function _redeem(uint256 instanceId, PhysicalClaim storage physicalClaimInstance, address to, uint32 count, uint8 variation, bytes memory data) internal {
        uint256 totalCount = count;
        if (totalCount > MAX_UINT_16) {
            revert InvalidInput();
        }
        uint256 startingCount = physicalClaimInstance.redeemedCount + 1;
        physicalClaimInstance.redeemedCount += uint32(totalCount);
            
        Redemption[] memory redemptions = new Redemption[](1);
        redemptions[0] = Redemption({
            timestamp: block.timestamp,
            redeemedCount: count,
            variation: variation
        });

        _redemptions[instanceId][to].push(redemptions[0]);
        emit PhysicalClaimLib.PhysicalClaimRedemption(instanceId, count, variation, data);
    }
}