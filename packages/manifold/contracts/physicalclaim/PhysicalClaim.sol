// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @author: manifold.xyz

import "@manifoldxyz/libraries-solidity/contracts/access/AdminControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import ".././libraries/manifold-membership/IManifoldMembership.sol";
import "./IPhysicalClaim.sol";
import "./Interfaces.sol";

// Let's get Physical 💋
contract PhysicalClaim is IPhysicalClaim, ReentrancyGuard, AdminControl {
    using ECDSA for bytes32;

    uint256 public constant BURN_FEE = 690000000000000;
    uint256 public constant MULTI_BURN_FEE = 990000000000000;
    address public manifoldMembershipContract;

    address private _signingAddress;
    mapping(uint256 => mapping(address => mapping(uint256 => bool))) private _usedTokens;
    mapping(uint256 => mapping(bytes32 => bool)) private _usedNonces;
    mapping(uint256 => mapping(uint8 => uint64)) private _variationCount;
    mapping(uint256 => uint64) private _totalCount;

    constructor(address initialOwner, address signingAddress) {
        _transferOwnership(initialOwner);
        _signingAddress = signingAddress;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(AdminControl, IERC165) returns (bool) {
        return interfaceId == type(IPhysicalClaim).interfaceId
            || interfaceId == type(AdminControl).interfaceId
            || interfaceId == type(IERC1155Receiver).interfaceId
            || interfaceId == type(IERC721Receiver).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IPhysicalClaim-withdraw}.
     */
    function withdraw(address payable recipient, uint256 amount) external override adminRequired {
        _forwardValue(recipient, amount);
    }

    /**
     * @dev See {IPhysicalClaim-setManifoldMembership}.
     */
    function setMembershipAddress(address addr) external override adminRequired {
        manifoldMembershipContract = addr;
    }
    
    /**
     * @dev See {IPhysicalClaim-updateSigner}.
     */
    function updateSigner(address signingAddress) external override adminRequired {
        _signingAddress = signingAddress;
    }

    /**
     * @dev See {IPhysicalClaimCore-recover}.
     */
    function recover(address tokenAddress, uint256 tokenId, address destination) external override adminRequired {
        IERC721(tokenAddress).transferFrom(address(this), destination, tokenId);
    }

    /**
     * @dev See {IPhysicalClaimCore-burnRedeem}.
     */
    function burnRedeem(BurnSubmission calldata submission) external payable override nonReentrant {
        if (!_isVariationAvailable(submission)) revert SoldOut();
        _validateSubmission(submission);
        _burnTokens(submission.instanceId, msg.sender, submission.burnTokens);
        _redeem(msg.sender, submission, msg.value);
    }

    /**
     * @dev See {IPhysicalClaimCore-burnRedeem}.
     */
    function burnRedeem(BurnSubmission[] calldata submissions) external payable override nonReentrant {
        uint256 msgValue = msg.value;
        for (uint256 i; i < submissions.length;) {
            BurnSubmission calldata submission = submissions[i];
            if (_isVariationAvailable(submission)) {
                // Only validate if the variation requested available
                _validateSubmission(submission);
                _burnTokens(submission.instanceId, msg.sender, submission.burnTokens);
                msgValue = _redeem(msg.sender, submission, msgValue);
            }
            unchecked { ++i; }
        }
        if (msgValue > 0) {
            // Return remaining unused funds
            _forwardValue(payable(msg.sender), msgValue);
        }
    }

    function _validateSubmission(BurnSubmission memory submission) private {
        if (block.timestamp > submission.expiration) revert ExpiredSignature();
        // Verify valid message based on input variables
        bytes memory messageData = abi.encode(submission.instanceId, submission.burnTokens, submission.variation, submission.variationLimit, submission.totalLimit, submission.erc20, submission.price, submission.fundsRecipient, submission.expiration, submission.nonce);
        bytes32 expectedMessage = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageData));
        address signer = submission.message.recover(submission.signature);
        if (submission.message != expectedMessage || signer != _signingAddress) revert InvalidSignature();
        if (_usedNonces[submission.instanceId][submission.nonce]) revert InvalidNonce();
        _usedNonces[submission.instanceId][submission.nonce] = true;
    }

    function _isVariationAvailable(BurnSubmission memory submission) private view returns(bool) {
        // Check variation limit
        if (submission.variationLimit > 0 && _variationCount[submission.instanceId][submission.variation] >= submission.variationLimit) return false;
        if (submission.totalLimit > 0 && _totalCount[submission.instanceId] >= submission.totalLimit) return false;
        return true;
    }

    function _burnTokens(uint256 instanceId, address from, BurnToken[] calldata burnTokens) private {
        for (uint256 i; i < burnTokens.length;) {
            BurnToken memory burnToken = burnTokens[i];
            _burn(instanceId, from, burnToken);
            unchecked { ++i; }
        }
    }

    /**
     * Helper to burn token
     */
    function _burn(uint256 instanceId, address from, BurnToken memory burnToken) private {
        if (burnToken.tokenSpec == TokenSpec.ERC1155) {
            if (burnToken.burnSpec == BurnSpec.NONE) {
                // Send to 0xdEaD to burn if contract doesn't have burn function
                IERC1155(burnToken.contractAddress).safeTransferFrom(from, address(0xdEaD), burnToken.tokenId, burnToken.amount, "");

            } else if (burnToken.burnSpec == BurnSpec.MANIFOLD) {
                // Burn using the creator core's burn function
                uint256[] memory tokenIds = new uint256[](1);
                tokenIds[0] = burnToken.tokenId;
                uint256[] memory amounts = new uint256[](1);
                amounts[0] = burnToken.amount;
                Manifold1155(burnToken.contractAddress).burn(from, tokenIds, amounts);

            } else if (burnToken.burnSpec == BurnSpec.OPENZEPPELIN) {
                // Burn using OpenZeppelin's burn function
                OZBurnable1155(burnToken.contractAddress).burn(from, burnToken.tokenId, burnToken.amount);

            } else {
                revert InvalidBurnSpec();
            }
        } else if (burnToken.tokenSpec == TokenSpec.ERC721) {
            if (burnToken.amount != 1) revert InvalidToken(burnToken.contractAddress, burnToken.tokenId);
            if (burnToken.burnSpec == BurnSpec.NONE) {
                // Send to 0xdEaD to burn if contract doesn't have burn function
                IERC721(burnToken.contractAddress).safeTransferFrom(from, address(0xdEaD), burnToken.tokenId, "");

            } else if (burnToken.burnSpec == BurnSpec.MANIFOLD || burnToken.burnSpec == BurnSpec.OPENZEPPELIN) {
                if (from != address(this)) {
                    // 721 `burn` functions do not have a `from` parameter, so we must verify the owner
                    if (IERC721(burnToken.contractAddress).ownerOf(burnToken.tokenId) != from) {
                        revert TransferFailure();
                    }
                }
                // Burn using the contract's burn function
                Burnable721(burnToken.contractAddress).burn(burnToken.tokenId);

            } else {
                revert InvalidBurnSpec();
            }
        } else if (burnToken.tokenSpec == TokenSpec.ERC721_NO_BURN) {
            if (from != address(this)) {
                // 721 `burn` functions do not have a `from` parameter, so we must verify the owner
                if (IERC721(burnToken.contractAddress).ownerOf(burnToken.tokenId) != from) {
                    revert TransferFailure();
                }
            }
            // Make sure token hasn't previously been used
            if (_usedTokens[instanceId][burnToken.contractAddress][burnToken.tokenId]) {
                revert InvalidToken(burnToken.contractAddress, burnToken.tokenId);
            }
            // Mark token as used
            _usedTokens[instanceId][burnToken.contractAddress][burnToken.tokenId] = true;

       } else {
            revert InvalidTokenSpec();
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
        // Do burn redeem
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
        // Do burn redeem
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
        (BurnSubmission memory submission) = abi.decode(data, (BurnSubmission));

        // A single ERC721 can only be sent in directly for a burn if:
        // 1. There is no ETH price to the burn (because no payment can be sent with a transfer)
        // 2. The burn only requires one NFT (one burnToken)
        // 3. They are an active member (because no fee payment can be sent with a transfer)
        _validateCanReceive(submission.erc20, submission.price, from);
        if (submission.burnTokens.length != 1) {
            revert InvalidInput();
        }
        if (!_isVariationAvailable(submission)) revert SoldOut();
        _validateSubmission(submission);

        // Check that the burn token is valid
        BurnToken memory burnToken = submission.burnTokens[0];

        // Can only take in one burn item
        if (burnToken.tokenSpec != TokenSpec.ERC721) {
            revert InvalidInput();
        }
        if (burnToken.contractAddress != msg.sender || burnToken.tokenId != id || burnToken.amount != 1) {
            revert InvalidToken(burnToken.contractAddress, burnToken.tokenId);
        }

        // Do burn and redeem
        _burn(submission.instanceId, address(this), burnToken);
        _redeem(from, submission, 0);
    }

    /**
     * Execute onERC1155Received burn/redeem
     */
    function _onERC1155Received(address from, uint256 tokenId, uint256 value, bytes calldata data) private {
        (BurnSubmission memory submission) = abi.decode(data, (BurnSubmission));

        // A single 1155 can only be sent in directly for a burn if:
        // 1. There is no cost to the burn (because no payment can be sent with a transfer)
        // 2. The burn only requires one NFT (one burnToken)
        // 3. They are an active member (because no fee payment can be sent with a transfer)
        _validateCanReceive(submission.erc20, submission.price, from);
        if (submission.burnTokens.length != 1) {
            revert InvalidInput();
        }
        if (!_isVariationAvailable(submission)) revert SoldOut();
        _validateSubmission(submission);


        // Check that the burn token is valid
        BurnToken memory burnToken = submission.burnTokens[0];

        // Can only take in one burn item
        if (burnToken.tokenSpec != TokenSpec.ERC1155) {
            revert InvalidInput();
        }
        if (burnToken.contractAddress != msg.sender || burnToken.tokenId != tokenId) {
            revert InvalidToken(burnToken.contractAddress, burnToken.tokenId);
        }
        if (burnToken.amount != value) {
            revert InvalidBurnAmount();
        }

        // Do burn and redeem
        _burn(submission.instanceId, address(this), burnToken);
        _redeem(from, submission, 0);
    }

    /**
     * Execute onERC1155BatchReceived burn/redeem
     */
    function _onERC1155BatchReceived(address from, uint256[] calldata tokenIds, uint256[] calldata values, bytes calldata data) private {
        (BurnSubmission memory submission) = abi.decode(data, (BurnSubmission));

        // A single 1155 can only be sent in directly for a burn if:
        // 1. There is no cost to the burn (because no payment can be sent with a transfer)
        // 2. We have the right data length
        // 3. They are an active member (because no fee payment can be sent with a transfer)
        _validateCanReceive(submission.erc20, submission.price, from);
        if (submission.burnTokens.length != tokenIds.length) {
            revert InvalidInput();
        }
        if (!_isVariationAvailable(submission)) revert SoldOut();
        _validateSubmission(submission);
    
        // Verify the values match what is needed and burn tokens
        for (uint256 i; i < submission.burnTokens.length;) {
            BurnToken memory burnToken = submission.burnTokens[i];
            if (burnToken.contractAddress != msg.sender || burnToken.tokenId != tokenIds[i] || burnToken.amount != values[i]) {
                revert InvalidToken(burnToken.contractAddress, burnToken.tokenId);
            }
            _burn(submission.instanceId, address(this), burnToken);
            unchecked { ++i; }
        }

        // Do redeem
        _redeem(from, submission, 0);
    }

    /**
     * Helper to validate we can receive tokens direcly
     */
    function _validateCanReceive(address erc20, uint256 price, address from) private view {
        if ((erc20 == address(0) && price != 0) || !_isActiveMember(from)) {
            revert InvalidInput();
        }
    }

    /**
     * Helper to check if the sender holds an active Manifold membership
     */
    function _isActiveMember(address sender) private view returns(bool) {
        return manifoldMembershipContract != address(0) &&
            IManifoldMembership(manifoldMembershipContract).isActiveMember(sender);
    }

    /**
     * Helper to perform the redeem and returns the remaining msg value after consumed amount
     */
    function _redeem(address redeemer, BurnSubmission memory submission, uint256 msgValue) private returns (uint256) {
        // Increment variation count
        _variationCount[submission.instanceId][submission.variation]++;
        // Increment total count
        _totalCount[submission.instanceId]++;

        // Transfer funds
        uint256 payableCost = submission.erc20 == address(0) ? submission.price : 0;
        if (!_isActiveMember(redeemer)) {
            payableCost += submission.burnTokens.length <= 1 ? BURN_FEE : MULTI_BURN_FEE;
        }
        
        // Check we have sufficient funds
        if (payableCost > msgValue) {
            revert InvalidPaymentAmount();
        }

        // Send funds if necessary
        if (submission.price > 0) {
            if (submission.erc20 == address(0)) {
                _forwardValue(submission.fundsRecipient, submission.price);
            } else {
                IERC20(submission.erc20).transferFrom(redeemer, submission.fundsRecipient, submission.price);
            }
        }

        // Redeem
        emit Redeem(submission.instanceId, redeemer, submission.variation, submission.nonce);

        return msgValue - payableCost;
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
     * @dev See {IPhysicalClaim-getVariationCounts}.
     */
    function getVariationCounts(uint256 instanceId, uint8[] calldata variations) external view override returns(uint64[] memory counts) {
        counts = new uint64[](variations.length);
        for (uint256 i; i < variations.length;) {
            counts[i] = _variationCount[instanceId][variations[i]];
            unchecked { ++i; }
        }
    }

    /**
     * @dev See {IPhysicalClaim-getTotalCount}.
     */
    function getTotalCount(uint256 instanceId) external view override returns(uint64) {
        return _totalCount[instanceId];
    }

}
