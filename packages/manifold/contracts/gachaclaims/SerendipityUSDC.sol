// SPDX-License-Identifier: MIT
// solhint-disable reason-string
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./ISerendipityUSDC.sol";
import "./SerendipityCore.sol";

/**
 * @title Serendipity USDC Lazy Claim
 * @author manifold.xyz
 * @notice USDC payment version of Serendipity with updatable fees
 */
abstract contract SerendipityUSDC is SerendipityCore, ISerendipityUSDC {
    uint256 public MINT_FEE;
    address public immutable USDC_ADDRESS;

    constructor(address initialOwner, address usdcAddress) SerendipityCore(initialOwner) {
        USDC_ADDRESS = usdcAddress;
    }

    /**
     * See {ISerendipityUSDC-setMintFee}.
     */
    function setMintFee(uint256 _mintFee) external override adminRequired {
        MINT_FEE = _mintFee;
    }

    /**
     * See {ISerendipityCore-withdraw}.
     */
    function withdraw(address payable receiver, uint256 amount) external override adminRequired {
        require(IERC20(USDC_ADDRESS).transfer(receiver, amount), "Failed to transfer USDC");
    }

    function _transferFundsUSDC(
        address erc20,
        uint256 cost,
        address payable recipient,
        uint32 mintCount
    ) internal {
        if (USDC_ADDRESS == ADDRESS_ZERO) {
            revert ISerendipityCore.InvalidPayment();
        }
        if (erc20 != USDC_ADDRESS) {
            revert ISerendipityUSDC.InvalidUSDCAddress();
        }

        uint256 payableCost = cost;
        // Add mint fee
        payableCost += MINT_FEE;

        if (mintCount > 1) {
            payableCost *= mintCount;
            cost *= mintCount;
        }

        // Transfer full amount (cost + fees) from sender to this contract
        require(IERC20(erc20).transferFrom(msg.sender, address(this), payableCost), "Insufficient funds");
        // Transfer cost portion to recipient (payment receiver)
        if (cost > 0) {
            IERC20(erc20).transfer(recipient, cost);
        }
    }
}
