// SPDX-License-Identifier: MIT
// solhint-disable reason-string
pragma solidity ^0.8.0;

import "./ERC1155SerendipityCore.sol";
import "./SerendipityUSDC.sol";
import "./ISerendipityUSDC.sol";

/**
 * @title Serendipity USDC Lazy Payable Claim - ERC-1155
 * @author manifold.xyz
 * @notice ERC1155 Serendipity with USDC payment and updatable fees
 */
contract ERC1155SerendipityUSDC is ERC1155SerendipityCore, SerendipityUSDC {
    constructor(address initialOwner, address usdcAddress, uint256 mintFee) SerendipityUSDC(initialOwner, usdcAddress, mintFee) {}
    
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1155SerendipityCore, AdminControl) returns (bool) {
        return
            interfaceId == type(ISerendipityUSDC).interfaceId ||
            ERC1155SerendipityCore.supportsInterface(interfaceId);
    }

    /**
     * See {IERC1155SerendipityCore-initializeClaim}.
     */
    function initializeClaim(
        address creatorContractAddress,
        uint256 instanceId,
        ClaimParameters calldata claimParameters
    ) external override creatorAdminRequired(creatorContractAddress) {
        if (claimParameters.erc20 != USDC_ADDRESS) revert ISerendipityUSDC.InvalidUSDCAddress();
        _initializeClaim(creatorContractAddress, instanceId, claimParameters);
    }

    /**
     * See {ISerendipity-mintReserve}.
     */
    function mintReserve(address creatorContractAddress, uint256 instanceId, uint32 mintCount) external override {
        (Claim storage claim, uint32 amountToReserve) = _validateMintReserve(creatorContractAddress, instanceId, mintCount);

        // Update state first
        _updateMintReserve(creatorContractAddress, instanceId, claim, amountToReserve);

        // Transfer USDC funds (only for the amount we're actually reserving)
        _transferFundsUSDC(claim.erc20, claim.cost, claim.paymentReceiver, amountToReserve);

        emit SerendipityMintReserved(creatorContractAddress, instanceId, msg.sender, amountToReserve);
    }
}
