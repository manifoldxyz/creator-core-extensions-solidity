// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../contracts/lazyclaim/ERC1155LazyPayableClaim.sol";
import "../../contracts/lazyclaim/IERC1155LazyPayableClaim.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC1155Creator.sol";
import "../../contracts/libraries/delegation-registry/DelegationRegistry.sol";
import "../mocks/Mock.sol";
import "../../lib/murky/src/Merkle.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract ERC1155LazyPayableClaimSignatureMintingTest is Test {
    using ECDSA for bytes32;

    ERC1155LazyPayableClaim public example;
    ERC1155Creator public creatorCore;
    DelegationRegistry public delegationRegistry;
    MockManifoldMembership public manifoldMembership;
    MockERC20 public mockERC20;
    Merkle public merkle;

    address public owner = 0x6140F00e4Ff3936702E68744f2b5978885464cbB;
    address public other = 0xc78Dc443c126af6E4f6Ed540c1e740C1b5be09cd;
    address public other2 = 0x80AAC46bbd3C2FcE33681541a52CacBEd14bF425;
    address public other3 = 0x5174cD462b60c536eb51D4ceC1D561D3Ea31004F;

    address public signingAddress;

    uint256 privateKey = 0x1010101010101010101010101010101010101010101010101010101010101010;
    uint256 privateKey2 = 0x1010101010101010101010101010101010101010101010101010101010101011;

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

        mockERC20 = new MockERC20("Test", "test");
        merkle = new Merkle();

        signingAddress = vm.addr(privateKey);

        vm.deal(owner, 10 ether);
        vm.deal(other, 10 ether);
        vm.deal(other2, 10 ether);
        vm.deal(other3, 10 ether);
        vm.stopPrank();
    }

    function testSignatureMint() public {
      vm.startPrank(owner);
      uint48 nowC = uint48(block.timestamp);
      uint48 later = nowC + 1000;
      uint mintFee = example.MINT_FEE_MERKLE();
      uint mintFeeNon = example.MINT_FEE();

      IERC1155LazyPayableClaim.ClaimParameters memory claimP = IERC1155LazyPayableClaim.ClaimParameters({
          merkleRoot: "",
          location: "arweaveHash1",
          totalMax: 1000,
          walletMax: 0,
          startDate: nowC,
          endDate: later,
          storageProtocol: ILazyPayableClaim.StorageProtocol.ARWEAVE,
          cost: 100,
          paymentReceiver: payable(owner),
          erc20: zeroAddress,
          signingAddress: signingAddress
      });

      example.initializeClaim(
        address(creatorCore),
        1,
        claimP
      );

      vm.stopPrank();
      vm.startPrank(other);

      bytes32 nonce = "1";
      uint expiration = uint(block.timestamp) + uint(120);
      bytes32 message = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", uint256(1), nonce, other2, expiration));

      (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, message);
      bytes memory signature = abi.encodePacked(r, s, v);

      // Perform a mint on the claim
      example.mintSignature{value: mintFee*3}(
        address(creatorCore),
        1,
        uint16(3),
        signature,
        message,
        nonce,
        other2,
        expiration
      );
      assertEq(3, creatorCore.balanceOf(other2, 1));

      // Cannot replay same tx with same nonce
      vm.expectRevert("Cannot replay transaction");
      example.mintSignature{value: mintFee*3}(
        address(creatorCore),
        1,
        uint16(3),
        signature,
        message,
        nonce,
        other2,
        expiration
      );

      bytes32 message = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", uint256(1), nonce, other, expiration));

      // Cannot replay same tx with same nonce, even with different mintfor
      vm.expectRevert("Cannot replay transaction");
      example.mintSignature{value: mintFee*3}(
        address(creatorCore),
        1,
        uint16(3),
        signature,
        message,
        nonce,
        other,
        expiration
      );

      uint expiration = uint(block.timestamp) + uint(121);
      bytes32 message = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", uint256(1), nonce, other2, expiration));

      // Cannot replay same tx with same nonce, even with different expiration
      vm.expectRevert("Cannot replay transaction");
      example.mintSignature{value: mintFee*3}(
        address(creatorCore),
        1,
        uint16(3),
        signature,
        message,
        nonce,
        other2,
        expiration
      );

      // Bad message signed
      nonce = "2";
      expiration = uint(block.timestamp) + uint(120);
      message = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", nonce, uint256(1), other2, expiration));

      (v, r, s) = vm.sign(privateKey, message);
      signature = abi.encodePacked(r, s, v);

      vm.expectRevert(InvalidSignature.selector);
      example.mintSignature{value: mintFee*3}(
        address(creatorCore),
        1,
        uint16(3),
        signature,
        message,
        nonce,
        other2,
        expiration
      );

      // Correct message, wrong signer
      nonce = "2";
      expiration = uint(block.timestamp) + uint(120);
      message = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", uint256(1), nonce, other2, expiration));
      (v, r, s) = vm.sign(privateKey2, message);
      signature = abi.encodePacked(r, s, v);
      vm.expectRevert(InvalidSignature.selector);
      example.mintSignature{value: mintFee*3}(
        address(creatorCore),
        1,
        uint16(3),
        signature,
        message,
        nonce,
        other2,
        expiration
      );

      // Expired signature
      nonce = "2";
      expiration = uint(0);
      message = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", uint256(1), nonce, other2, expiration));
      (v, r, s) = vm.sign(privateKey, message);
      signature = abi.encodePacked(r, s, v);
      vm.expectRevert(ExpiredSignature.selector);
      example.mintSignature{value: mintFee*3}(
        address(creatorCore),
        1,
        uint16(3),
        signature,
        message,
        nonce,
        other2,
        expiration
      );

      // Still only owns 3
      assertEq(3, creatorCore.balanceOf(other2, 1));

      // Cannot mint other ways when signature is non-zero
      vm.expectRevert(MustUseSignatureMinting.selector);
      example.mint{ value: mintFee * 3 }(address(creatorCore), 1, uint16(3), new bytes32[](0), other);

      vm.expectRevert(MustUseSignatureMinting.selector);
      example.mintBatch{value:mintFee*3}(address(creatorCore), 1, 3, new uint32[](0), new bytes32[][](0), other);

      vm.expectRevert(MustUseSignatureMinting.selector);
      example.mintProxy{value:mintFee*3}(address(creatorCore), 1, 3, new uint32[](0), new bytes32[][](0), other);

      // Other owns none because all mints with other methods failed
      assertEq(0, creatorCore.balanceOf(other, 1));

      // Cannot mintSignature for claim that isn't signature based
      claimP.signingAddress = zeroAddress;
      vm.stopPrank();
      vm.startPrank(owner);
      example.updateClaim(
        address(creatorCore),
        1,
        claimP
      );
      vm.stopPrank();
      vm.startPrank(other);
      nonce = "2";
      expiration = uint(block.timestamp) + uint(120);
      message = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", uint256(1), nonce, other2, expiration));
      (v, r, s) = vm.sign(privateKey, message);
      signature = abi.encodePacked(r, s, v);
      vm.expectRevert(MustUseSignatureMinting.selector);
      example.mintSignature{value: mintFee*3}(
        address(creatorCore),
        1,
        uint16(3),
        signature,
        message,
        nonce,
        other2,
        expiration
      );

    }

}