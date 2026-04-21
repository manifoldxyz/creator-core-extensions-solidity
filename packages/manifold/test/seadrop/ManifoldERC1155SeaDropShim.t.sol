// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

/// @author: manifold.xyz

import "forge-std/Test.sol";

import {ERC1155Creator} from "@manifoldxyz/creator-core-solidity/contracts/ERC1155Creator.sol";

import {ManifoldERC1155SeaDropShim} from "../../contracts/seadrop/ManifoldERC1155SeaDropShim.sol";
import {
    AllowListData,
    MultiConfigureStruct,
    PublicDrop,
    StorageProtocol
} from "../../contracts/seadrop/SeaDropStructs.sol";

import {MockSeaDrop} from "./mocks/MockSeaDrop.sol";

/**
 * @notice Shared Foundry harness for every ManifoldERC1155SeaDropShim test.
 * @dev setUp deploys a real ERC1155Creator (not a mock — we want the full
 *      Creator Core mintExtensionNew / mintExtensionExisting paths exercised),
 *      a MockSeaDrop trace mock, and the shim bound to both. The shim is
 *      registered as a Creator Core extension inside the same admin prank so
 *      subsequent tests can call initialize() without repeating the wiring.
 *
 *      _defaultCfg() returns a sane MultiConfigureStruct that every
 *      scenario-specific test can mutate; centralising the defaults keeps
 *      later test stories focused on the field(s) under test.
 */
contract ManifoldERC1155SeaDropShimTest is Test {
    uint256 internal constant INSTANCE_ID = 1;

    // Creator admin for the ERC1155Creator — used to register the shim and
    // later to call initialize() / multiConfigure() via vm.prank.
    address internal creatorAdmin = address(0xA11CE);
    address internal payoutAddress = address(0xBEEF);
    address internal feeRecipient = address(0xFEE);

    ERC1155Creator internal creator;
    MockSeaDrop internal mockSeaDrop;
    ManifoldERC1155SeaDropShim internal shim;

    function setUp() public virtual {
        vm.startPrank(creatorAdmin);

        creator = new ERC1155Creator("TestCreator", "TEST");
        mockSeaDrop = new MockSeaDrop();

        address[] memory allowed = new address[](1);
        allowed[0] = address(mockSeaDrop);
        shim = new ManifoldERC1155SeaDropShim(address(creator), INSTANCE_ID, allowed);

        creator.registerExtension(address(shim), "");

        vm.stopPrank();
    }

    /**
     * @dev Canonical default MultiConfigureStruct for scenarios that don't
     *      exercise a specific field. Scenario tests should clone into a
     *      memory variable, tweak the fields they care about, then pass in.
     */
    function _defaultCfg() internal view returns (MultiConfigureStruct memory cfg) {
        address[] memory feeRecipients = new address[](1);
        feeRecipients[0] = feeRecipient;

        cfg = MultiConfigureStruct({
            maxSupply: 100,
            maxMintsPerWallet: 5,
            tokenUriLocation: "https://example.com/meta.json",
            storageProtocol: StorageProtocol.NONE,
            contractURI: "https://example.com/contract.json",
            seaDropImpl: address(mockSeaDrop),
            publicDrop: PublicDrop({
                mintPrice: 0.01 ether,
                startTime: uint48(block.timestamp),
                endTime: uint48(block.timestamp + 7 days),
                maxTotalMintableByWallet: 5,
                feeBps: 500,
                restrictFeeRecipients: true
            }),
            allowListData: AllowListData({
                merkleRoot: bytes32(0),
                publicKeyURIs: new string[](0),
                allowListURI: ""
            }),
            creatorPayoutAddress: payoutAddress,
            allowedFeeRecipients: feeRecipients
        });
    }

    function testScaffoldBoots() public {
        assertTrue(address(shim) != address(0), "shim deployed");
        assertTrue(address(creator) != address(0), "creator deployed");
        assertTrue(address(mockSeaDrop) != address(0), "mockSeaDrop deployed");
        assertEq(shim.creatorContractAddress(), address(creator), "shim bound to creator");
        assertEq(shim.instanceId(), INSTANCE_ID, "instanceId stored");

        address[] memory allowed = shim.getAllowedSeaDrop();
        assertEq(allowed.length, 1, "one allowed seadrop");
        assertEq(allowed[0], address(mockSeaDrop), "mockSeaDrop is allowed");
    }
}
