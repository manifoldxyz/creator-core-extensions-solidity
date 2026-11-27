// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC721Creator.sol";
import "@manifoldxyz/creator-core-extensions-solidity/contracts/lazyclaim/IERC721LazyPayableClaim.sol";
import "@manifoldxyz/creator-core-extensions-solidity/contracts/lazyclaim/ILazyPayableClaimCore.sol";

import "../contracts/ERC721ClaimSecretReveal.sol";
import "../contracts/IERC721ClaimSecretReveal.sol";

interface ILazyPayableClaimMint {
    function MINT_FEE() external view returns (uint256);
    function mint(
        address creatorContractAddress,
        uint256 instanceId,
        uint32 mintIndex,
        bytes32[] calldata merkleProof,
        address mintFor
    ) external payable;
}

/**
 * Runs against the ERC721 lazy claim extensions deployed on Sepolia.
 * SEPOLIA_RPC_URL=<rpc> forge test --match-contract Fork
 * Skipped when SEPOLIA_RPC_URL is not set.
 */
contract ERC721ClaimSecretRevealForkTest is Test {
    // ERC721 lazy claim extensions on Sepolia. StorageProtocol.ADDRESS needs the current claim (V8);
    // the previous release (V7) predates it.
    address internal constant CLAIM_V8 = 0xd5455d23d2052e88C084039A495C51808817040e;
    address internal constant CLAIM_V7 = 0x23aA05a271DEBFFAA3D75739aF5581f744b326E4;

    // Test secret, also used by the unit tests
    bytes32 internal constant SECRET = 0xd711c815a6fe15f8c628758a0a3c4c98de3c08081ca75bb769346711f7de8c1d;
    bytes32 internal constant COMMIT = 0xf7662ad1de0218254a94420e9cf9dfdf6d51024e30214dfbb4fb51ed5a8f91ef;

    address internal owner = address(0xA11CE);
    address internal collector = address(0xC011);
    address payable internal receiver = payable(address(0x5E11));

    function _fork() internal returns (bool) {
        string memory rpc = vm.envOr("SEPOLIA_RPC_URL", string(""));
        if (bytes(rpc).length == 0) return false;
        vm.createSelectFork(rpc);
        return true;
    }

    function testForkClaimV8() public {
        if (!_fork()) {
            emit log("SEPOLIA_RPC_URL not set, skipping");
            return;
        }
        assertGt(CLAIM_V8.code.length, 0, "claim not deployed");
        // fresh accounts on the fork
        vm.etch(collector, "");
        vm.deal(collector, 1 ether);

        vm.startPrank(owner);
        ERC721Creator creator = new ERC721Creator("Token", "NFT");
        creator.registerExtension(CLAIM_V8, "");
        ERC721ClaimSecretReveal sr = new ERC721ClaimSecretReveal(
            address(creator),
            COMMIT,
            100,
            "key-v1:",
            IERC721ClaimSecretReveal.Renderer({
                name: "Piece", description: "d", imageURI: "ar://cover", animationURI: "ar://generator"
            })
        );
        IERC721LazyPayableClaim(CLAIM_V8).initializeClaim(address(creator), 1, _params(address(sr)));
        vm.stopPrank();

        uint256 price = 0.001 ether + ILazyPayableClaimMint(CLAIM_V8).MINT_FEE();
        vm.prank(collector);
        ILazyPayableClaimMint(CLAIM_V8).mint{value: price}(address(creator), 1, 0, new bytes32[](0), collector);
        assertEq(creator.ownerOf(1), collector);

        string memory cover = creator.tokenURI(1);
        assertEq(cover, sr.tokenURI(address(creator), 1, 1, 1));
        emit log_named_string("tokenURI before reveal", cover);

        vm.prank(owner);
        sr.reveal(SECRET);
        string memory revealed = creator.tokenURI(1);
        assertEq(revealed, sr.tokenURI(address(creator), 1, 1, 1));
        assertTrue(keccak256(bytes(revealed)) != keccak256(bytes(cover)));
        assertEq(sr.editionKey(1), 0xf887a8f18acf88c28aded7114edf99ad8f066a970e8a53b7921c334385a9a5a8);
        emit log_named_string("tokenURI after reveal", revealed);
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
        vm.expectRevert();
        IERC721LazyPayableClaim(CLAIM_V7).initializeClaim(address(creator), 1, _params(address(this)));
        vm.stopPrank();
    }

    function _params(address metadata) internal view returns (IERC721LazyPayableClaim.ClaimParameters memory) {
        return IERC721LazyPayableClaim.ClaimParameters({
            totalMax: 100,
            walletMax: 0,
            startDate: uint48(block.timestamp),
            endDate: 0,
            storageProtocol: ILazyPayableClaimCore.StorageProtocol.ADDRESS,
            identical: false,
            merkleRoot: bytes32(0),
            location: string(abi.encodePacked(metadata)),
            cost: 0.001 ether,
            paymentReceiver: receiver,
            erc20: address(0),
            signingAddress: address(0)
        });
    }
}
