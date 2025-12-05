// SPDX-License-Identifier: MIT
// solhint-disable reason-string
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "./ERC1155SerendipityCore.sol";
import "./SerendipityUSDC.sol";
import "./ISerendipityUSDC.sol";

/**
 * @title Serendipity USDC Lazy Payable Claim - ERC-1155
 * @author manifold.xyz
 * @notice ERC1155 Serendipity with USDC payment and updatable fees
 */
contract ERC1155SerendipityUSDC is ERC1155SerendipityCore, SerendipityUSDC {
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1155SerendipityCore, AdminControl) returns (bool) {
        return
            interfaceId == type(ISerendipityUSDC).interfaceId ||
            ERC1155SerendipityCore.supportsInterface(interfaceId);
    }

    constructor(address initialOwner, address usdcAddress) SerendipityUSDC(initialOwner, usdcAddress) {
        if (usdcAddress == address(0)) revert ISerendipityUSDC.InvalidUSDCAddress();
    }

    /**
     * See {IERC1155SerendipityCore-initializeClaim}.
     */
    function initializeClaim(
        address creatorContractAddress,
        uint256 instanceId,
        ClaimParameters calldata claimParameters
    ) external payable override creatorAdminRequired(creatorContractAddress) {
        if (claimParameters.erc20 != USDC_ADDRESS) revert ISerendipityUSDC.InvalidUSDCAddress();
        _initializeClaim(creatorContractAddress, instanceId, claimParameters);
    }

    /**
     * See {ISerendipity-mintReserve}.
     */
    function mintReserve(address creatorContractAddress, uint256 instanceId, uint32 mintCount, address mintFor) external override {
        (Claim storage claim, uint32 amountToReserve) = _validateMintReserveUSDC(creatorContractAddress, instanceId, mintCount);

        // Update state first - reserve for the specified mintFor address
        _updateMintReserveFor(creatorContractAddress, instanceId, claim, amountToReserve, mintFor);

        // Transfer USDC funds (only for the amount we're actually reserving)
        _transferFundsUSDC(claim.erc20, claim.cost, claim.paymentReceiver, amountToReserve);

        emit SerendipityMintReserved(creatorContractAddress, instanceId, mintFor, amountToReserve);
    }

    /**
     * @notice Validate mint reserve without contract caller restriction
     */
    function _validateMintReserveUSDC(
        address creatorContractAddress,
        uint256 instanceId,
        uint32 mintCount
    ) internal view returns (Claim storage claim, uint32 amountToReserve) {
        claim = _getClaim(creatorContractAddress, instanceId);
        // Checks for reserving
        if (mintCount == 0 || mintCount >= MAX_UINT_32) revert ISerendipityCore.InvalidMintCount();
        if (claim.startDate > block.timestamp || (claim.endDate > 0 && claim.endDate < block.timestamp))
            revert ISerendipityCore.ClaimInactive();
        if (claim.totalMax != 0 && claim.total == claim.totalMax) revert ISerendipityCore.ClaimSoldOut();
        if (claim.total == MAX_UINT_32) revert ISerendipityCore.TooManyRequested();

        // calculate the amount to reserve
        amountToReserve = mintCount;
        if (claim.totalMax != 0) {
            amountToReserve = uint32(Math.min(mintCount, claim.totalMax - claim.total));
        }
    }
}
