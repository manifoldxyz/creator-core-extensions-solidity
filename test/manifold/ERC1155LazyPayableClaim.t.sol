// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../contracts/manifold/lazyclaim/ERC1155LazyPayableClaim.sol";
import "../../contracts/manifold/lazyclaim/IERC1155LazyPayableClaim.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC1155Creator.sol";
import "../../contracts/libraries/delegation-registry/DelegationRegistry.sol";
import "../../contracts/mocks/Mock.sol";

contract ERC1155LazyPayableClaimTest is Test {
    ERC1155LazyPayableClaim public example;
    ERC1155Creator public creatorCore;
    DelegationRegistry public delegationRegistry;
    MockManifoldMembership public manifoldMembership;

    address public owner = 0x6140F00e4Ff3936702E68744f2b5978885464cbB;
    address public other = 0xc78Dc443c126af6E4f6Ed540c1e740C1b5be09cd;
    address public other2 = 0x80AAC46bbd3C2FcE33681541a52CacBEd14bF425;
    address public other3 = 0x5174cD462b60c536eb51D4ceC1D561D3Ea31004F;

    address public zeroAddress = address(0);

    function setUp() public {
        vm.startPrank(owner);
        creatorCore = new ERC1155Creator("Token", "NFT");
        delegationRegistry = new DelegationRegistry();
        example = new ERC1155LazyPayableClaim(
          owner, address(delegationRegistry)
        );
        manifoldMembership = new MockManifoldMembership();
        example.setMembershipAddress(address(manifoldMembership));

        creatorCore.registerExtension(address(example), "override");
        vm.stopPrank();
    }

    function testAccess() public {
      vm.startPrank(other);
      // Must be admin
      vm.expectRevert();
      example.withdraw(payable(other), 20);
      // Must be admin
      vm.expectRevert();
      example.setMembershipAddress(other);

      IERC1155LazyPayableClaim.ClaimParameters memory claimP = IERC1155LazyPayableClaim.ClaimParameters({
        merkleRoot: "",
          location: "XXX",
          totalMax: 10,
          walletMax: 1,
          startDate: 0,
          endDate: 0,
          storageProtocol: ILazyPayableClaim.StorageProtocol.IPFS,
          cost: 1,
          paymentReceiver: payable(other),
          erc20: zeroAddress
      });
      // Must be admin
      vm.expectRevert();
      example.initializeClaim(
        address(creatorCore),
        1,
        claimP
      );
      // Succeeds because is admin
      vm.stopPrank();
      vm.startPrank(owner);
      example.initializeClaim(
        address(creatorCore),
        1,
        claimP
      );

      // Update, not admin
      vm.stopPrank();
      vm.startPrank(other);
      vm.expectRevert();
      example.updateClaim(
        address(creatorCore),
        1,
        claimP
      );

      vm.expectRevert();
      example.updateTokenURIParams(
        address(creatorCore),
        1,
        ILazyPayableClaim.StorageProtocol.IPFS,
        ""
      );

      vm.expectRevert();
      example.extendTokenURI(
        address(creatorCore),
        2,
        ""
      );

      vm.stopPrank();
    }            
}
