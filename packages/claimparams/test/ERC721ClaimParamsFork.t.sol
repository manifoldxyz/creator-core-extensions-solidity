// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC721Creator.sol";
import "@manifoldxyz/creator-core-extensions-solidity/contracts/lazyclaim/IERC721LazyPayableClaim.sol";
import "@manifoldxyz/creator-core-extensions-solidity/contracts/lazyclaim/ILazyPayableClaimCore.sol";

import "../contracts/ERC721ClaimParams.sol";
import "../contracts/IERC721ClaimParams.sol";

/**
 * Runs against the ERC721 lazy claim extensions deployed on Sepolia.
 * SEPOLIA_RPC_URL=<rpc> forge test --match-contract Fork
 * Skipped when SEPOLIA_RPC_URL is not set.
 */
contract ERC721ClaimParamsForkTest is Test {
    // ERC721 lazy claim extensions on Sepolia. StorageProtocol.ADDRESS needs the current claim (V8);
    // the previous release (V7) predates it.
    address internal constant CLAIM_V8 = 0xd5455d23d2052e88C084039A495C51808817040e;
    address internal constant CLAIM_V7 = 0x23aA05a271DEBFFAA3D75739aF5581f744b326E4;

    address internal owner = address(0xA11CE);
    address internal collector = address(0xC011);
    address payable internal receiver = payable(address(0x5E11));

    function _fork() internal returns (bool) {
        string memory rpc = vm.envOr("SEPOLIA_RPC_URL", string(""));
        if (bytes(rpc).length == 0) return false;
        vm.createSelectFork(rpc);
        return true;
    }

    function _run(address claimAddress) internal {
        if (!_fork()) {
            emit log("SEPOLIA_RPC_URL not set, skipping");
            return;
        }
        assertGt(claimAddress.code.length, 0, "claim not deployed");
        // fresh accounts on the fork
        vm.etch(collector, "");
        vm.deal(collector, 1 ether);

        vm.startPrank(owner);
        ERC721Creator creator = new ERC721Creator("Token", "NFT");
        creator.registerExtension(claimAddress, "");
        IERC721LazyPayableClaim(claimAddress).initializeClaim(address(creator), 1, _params());
        IERC721LazyPayableClaim.Claim memory c = IERC721LazyPayableClaim(claimAddress).getClaim(address(creator), 1);
        assertGe(c.contractVersion, 3, "creator contract version");

        ERC721ClaimParams cp = new ERC721ClaimParams(claimAddress, address(creator), 1, 64);
        cp.setRenderer(
            IERC721ClaimParams.Renderer({
                name: "Piece", description: "d", imageURI: "ar://preview", animationURI: "ar://renderer"
            })
        );
        IERC721LazyPayableClaim(claimAddress)
            .updateTokenURIParams(
                address(creator),
                1,
                ILazyPayableClaimCore.StorageProtocol.ADDRESS,
                false,
                string(abi.encodePacked(address(cp)))
            );
        cp.lockRenderer();
        vm.stopPrank();

        bytes memory p = new bytes(64);
        p[0] = 0xab;
        p[63] = 0xcd;
        uint256 price = cp.mintPrice();
        emit log_named_uint("mintPrice", price);
        uint256 claimBalance = claimAddress.balance;

        vm.prank(collector);
        cp.mint{value: price}(p, 0, new bytes32[](0));

        assertEq(creator.ownerOf(1), collector);
        assertEq(cp.getParams(1), p);
        assertEq(address(cp).balance, 0);
        assertEq(receiver.balance, 0.001 ether);
        assertEq(claimAddress.balance - claimBalance, price - 0.001 ether);

        string memory uri = creator.tokenURI(1);
        assertEq(uri, cp.tokenURI(address(creator), 1, 1, 1));
        emit log_named_string("tokenURI", uri);
    }

    function testForkClaimV8() public {
        _run(CLAIM_V8);
    }

    /// The previous claim release has no StorageProtocol.ADDRESS, so it can't point at this contract.
    function testForkClaimV7CannotUseAddressStorage() public {
        if (!_fork()) {
            emit log("SEPOLIA_RPC_URL not set, skipping");
            return;
        }
        vm.startPrank(owner);
        ERC721Creator creator = new ERC721Creator("Token", "NFT");
        creator.registerExtension(CLAIM_V7, "");
        IERC721LazyPayableClaim(CLAIM_V7).initializeClaim(address(creator), 1, _params());
        vm.expectRevert();
        IERC721LazyPayableClaim(CLAIM_V7)
            .updateTokenURIParams(
                address(creator),
                1,
                ILazyPayableClaimCore.StorageProtocol.ADDRESS,
                false,
                string(abi.encodePacked(address(this)))
            );
        vm.stopPrank();
    }

    function _params() internal view returns (IERC721LazyPayableClaim.ClaimParameters memory) {
        return IERC721LazyPayableClaim.ClaimParameters({
            totalMax: 256,
            walletMax: 0,
            startDate: uint48(block.timestamp),
            endDate: 0,
            storageProtocol: ILazyPayableClaimCore.StorageProtocol.ARWEAVE,
            identical: true,
            merkleRoot: bytes32(0),
            location: "placeholder",
            cost: 0.001 ether,
            paymentReceiver: receiver,
            erc20: address(0),
            signingAddress: address(0)
        });
    }
}
