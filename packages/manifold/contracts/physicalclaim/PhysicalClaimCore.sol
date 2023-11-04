// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";
import "@manifoldxyz/libraries-solidity/contracts/access/IAdminControl.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

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
    using ECDSA for bytes32;

    uint256 internal constant MAX_UINT_16 = 0xffff;
    uint256 internal constant MAX_UINT_56 = 0xffffffffffffff;

    bool public deprecated;

    // { instanceId => PhysicalClaim }
    mapping(uint256 => PhysicalClaim) internal _physicalClaims;

    // { instanceId => creator } -> TODO: make it so multiple people can administer a physical claim
    mapping(uint256 => address) internal _physicalClaimCreator;

    // { instanceId => { redeemer => uint256 } }
    mapping(uint256 => mapping(address => uint256)) internal _redemptionCounts;

    // { instanceId => nonce => t/f  }
    mapping(uint256 => mapping(bytes32 => bool)) internal _usedMessages;

    constructor(address initialOwner) {
        _transferOwnership(initialOwner);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, ERC165, AdminControl) returns (bool) {
        return interfaceId == type(IPhysicalClaimCore).interfaceId ||
            interfaceId == type(IERC721Receiver).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * Admin function to deprecate the contract
     */
    function deprecate(bool _deprecated) external adminRequired {
        deprecated = _deprecated;
    }

    /**
     * Initialiazes a physical claim with base parameters
     */
    function _initialize(
        uint256 instanceId,
        PhysicalClaimParameters calldata physicalClaimParameters
    ) internal {
        if (deprecated) {
            revert ContractDeprecated();
        }
        if (_physicalClaimCreator[instanceId] != address(0)) {
            revert InvalidInstance();
        }
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
    function getPhysicalClaim(uint256 instanceId) external override view returns(PhysicalClaimView memory) {
        PhysicalClaim storage physicalClaimInstance = _getPhysicalClaim(instanceId);
        VariationState[] memory variationStates = new VariationState[](physicalClaimInstance.variationIds.length);
        for (uint256 i; i < physicalClaimInstance.variationIds.length;) {
            variationStates[i] = physicalClaimInstance.variations[physicalClaimInstance.variationIds[i]];
            unchecked { ++i; }
        }
        return PhysicalClaimView({
            paymentReceiver: physicalClaimInstance.paymentReceiver,
            redeemedCount: physicalClaimInstance.redeemedCount,
            totalSupply: physicalClaimInstance.totalSupply,
            startDate: physicalClaimInstance.startDate,
            endDate: physicalClaimInstance.endDate,
            signer: physicalClaimInstance.signer,
            burnSet: physicalClaimInstance.burnSet,
            variationStates: variationStates
        });
    }

    /**
     * See {IPhysicalClaimCore-getPhysicalClaim}.
     */
    function getRedemptions(uint256 instanceId, address redeemer) external override view returns(uint256) {
        return _redemptionCounts[instanceId][redeemer];
    }

    /**
     * See {IPhysicalClaimCore-getVariationState}.
     */
    function getVariationState(uint256 instanceId, uint8 variation) external override view returns(VariationState memory) {
        return _getPhysicalClaim(instanceId).variations[variation];
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
        if (submissions.length == 0) revert InvalidInput();

        uint256 msgValueRemaining = msg.value;
        for (uint256 i; i < submissions.length;) {
            PhysicalClaimSubmission memory currentSub = submissions[i];
            uint256 instanceId = currentSub.instanceId;

            // The expectedCount must match the user's current redemption count to enforce idempotency
            if (currentSub.currentClaimCount != _redemptionCounts[instanceId][msg.sender]) revert InvalidInput();

            uint256 totalCost = currentSub.totalCost;

            // Check that we have enough funds for the redemption
            if (totalCost > 0) {
                if (msgValueRemaining < totalCost) {
                    revert InvalidPaymentAmount();
                }
                msgValueRemaining -= totalCost;
            }
            _burnRedeem(currentSub);
            unchecked { ++i; }
        }
    }

    function _burnRedeem(PhysicalClaimSubmission memory submission) private {
        PhysicalClaim storage physicalClaimInstance = _getPhysicalClaim(submission.instanceId);

        // Get the amount that can be burned
        uint16 physicalClaimCount = _getAvailablePhysicalClaimCount(physicalClaimInstance, submission.variation, submission.count);

        // Signer being set means that the physical claim is a paid claim
        if (physicalClaimInstance.signer != address(0)) {
            // Check that the message value is what was signed...
            _checkPriceSignature(submission.instanceId, submission.signature, submission.message, submission.nonce, physicalClaimInstance.signer, submission.totalCost);
            _forwardValue(physicalClaimInstance.paymentReceiver, submission.totalCost);
        }

        // Do physical claim
        _burnTokens(physicalClaimInstance, submission.burnTokens, physicalClaimCount, msg.sender, submission.data);
        _redeem(submission.instanceId, physicalClaimInstance, msg.sender, submission.variation, physicalClaimCount, submission.data);
    }

    function _checkPriceSignature(uint56 instanceId, bytes memory signature, bytes32 message, bytes32 nonce, address signingAddress, uint256 cost) internal {
        // Verify valid message based on input variables
        bytes32 expectedMessage = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", instanceId, cost));
        // Verify nonce usage/re-use
        require(!_usedMessages[instanceId][nonce], "Cannot replay transaction");
        address signer = message.recover(signature);
        if (message != expectedMessage || signer != signingAddress) revert InvalidSignature();
        _usedMessages[instanceId][nonce] = true;
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
        _onERC721Received(from, id, data);
        return this.onERC721Received.selector;
    }

    /**
     * @notice  token transfer callback
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
        if (data.length % 32 != 0) {
            revert InvalidData();
        }

        uint56 instanceId;
        uint256 burnItemIndex;
        bytes32[] memory merkleProof;
        uint8 variation;
        (instanceId, burnItemIndex, merkleProof, variation) = abi.decode(data, (uint56, uint256, bytes32[], uint8));

        PhysicalClaim storage physicalClaimInstance = _getPhysicalClaim(instanceId);

        // A single  can only be sent in directly for a burn if:
        // 1. There is no cost to the burn (because no payment can be sent with a transfer)
        // 2. The burn only requires one NFT (one burnSet element and one count)
        _validateReceivedInput(physicalClaimInstance.burnSet.length, physicalClaimInstance.burnSet[0].requiredCount);

        // Validate we have remaining amounts available (will revert if not)
        _getAvailablePhysicalClaimCount(physicalClaimInstance, variation, 1);

        // Check that the burn token is valid
        BurnItem memory burnItem = physicalClaimInstance.burnSet[0].items[burnItemIndex];

        // Can only take in one burn item
        if (burnItem.tokenSpec != TokenSpec.ERC721) {
            revert InvalidInput();
        }
        PhysicalClaimLib.validateBurnItem(burnItem, msg.sender, id, merkleProof);

        // Do burn and redeem
        _burn(burnItem, address(this), msg.sender, id, 1, "");
        _redeem(instanceId, physicalClaimInstance, from, variation, 1, "");
    }

    function _validateReceivedInput(uint256 length, uint256 requiredCount) private pure {
        if (length != 1 || requiredCount != 1) {
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
                revert InvalidBurnAmount();
            }
            unchecked { ++i; }
        }
    }

    /**
     * Helper to get the number of burn redeems the person can accomplish
     */
    function _getAvailablePhysicalClaimCount(PhysicalClaim storage instance, uint8 variation, uint16 count) internal view returns(uint16 burnRedeemCount) {
        uint16 remainingTotalCount;
        if (instance.totalSupply == 0) {
            // If totalSupply is 0, it means unlimited redemptions
            remainingTotalCount = count;
        } else {
            // Get the remaining total redemptions
            remainingTotalCount = (instance.totalSupply - instance.redeemedCount);
        }

        // Get the max redemptions for this variation
        VariationState memory variationState = instance.variations[variation];
        if (!variationState.active) revert InvalidVariation();

        uint16 variationRemainingCount;
        if (variationState.totalSupply == 0) {
            // If totalSupply of variation is 0, it means unlimited available
            variationRemainingCount = count;
        } else {
            // Get the remaining variation redemptions
            variationRemainingCount = (variationState.totalSupply - variationState.redeemedCount);
        }
        
        // Use whichever is lesser...
        uint16 comparator = remainingTotalCount > variationRemainingCount ? variationRemainingCount : remainingTotalCount;

        // Use the lesser of what's available or the desired count
        if (comparator > count) {
            burnRedeemCount = count;
        } else {
            burnRedeemCount = comparator;
        }

        // No more remaining
        if (burnRedeemCount == 0) revert InvalidRedeemAmount();
    }

    /**
     * Helper to burn token
     */
    function _burn(BurnItem memory burnItem, address from, address contractAddress, uint256 tokenId, uint256 burnRedeemCount, bytes memory data) private {
        if (burnItem.tokenSpec == TokenSpec.ERC1155) {
            uint256 amount = burnItem.amount * burnRedeemCount;

            if (burnItem.burnSpec == BurnSpec.NONE) {
                // Send to 0xdEaD to burn if contract doesn't have burn function
                IERC1155(contractAddress).safeTransferFrom(from, address(0xdEaD), tokenId, amount, data);

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
                revert InvalidBurnSpec();
            }
        } else if (burnItem.tokenSpec == TokenSpec.ERC721) {
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
     * Helper to redeem multiple redeem
     */
    function _redeem(uint256 instanceId, PhysicalClaim storage physicalClaimInstance, address to, uint8 variation, uint16 count, bytes memory data) internal {
        uint256 totalCount = count;
        if (totalCount > MAX_UINT_16) {
            revert InvalidInput();
        }
        physicalClaimInstance.redeemedCount += uint16(totalCount);
        physicalClaimInstance.variations[variation].redeemedCount += count;
        _redemptionCounts[instanceId][to] += count;
        emit PhysicalClaimLib.PhysicalClaimRedemption(instanceId, variation, count, data);
    }
}