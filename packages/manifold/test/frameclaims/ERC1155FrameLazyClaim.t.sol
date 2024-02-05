// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../contracts/frameclaims/ERC1155FrameLazyClaim.sol";
import "../../contracts/frameclaims/IERC1155FrameLazyClaim.sol";
import "../../contracts/frameclaims/FramePaymaster.sol";
import "../../contracts/frameclaims/IFramePaymaster.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC1155Creator.sol";
import "../mocks/Mock.sol";

contract ERC1155FrameLazyClaimTest is Test {
    ERC1155FrameLazyClaim public example;
    FramePaymaster public paymaster;
    ERC1155Creator public creatorCore1;
    ERC1155Creator public creatorCore2;

    address public owner = 0x6140F00e4Ff3936702E68744f2b5978885464cbB;
    address public creator = 0xc78Dc443c126af6E4f6Ed540c1e740C1b5be09cd;
    address public creatorOtherReceiver = 0xc78dC443c126Af6E4f6eD540C1E740c1B5be09CE;
    address public other = 0x5174cD462b60c536eb51D4ceC1D561D3Ea31004F;

    address public signingAddress;

    uint256 privateKey = 0x1010101010101010101010101010101010101010101010101010101010101010;

    function setUp() public {
        signingAddress = vm.addr(privateKey);

        vm.startPrank(creator);
        creatorCore1 = new ERC1155Creator("Token1", "NFT1");
        creatorCore2 = new ERC1155Creator("Token2", "NFT2");
        vm.stopPrank();
        vm.startPrank(owner);
        paymaster = new FramePaymaster();
        paymaster.setSigner(signingAddress);
        example = new ERC1155FrameLazyClaim(owner);
        example.setSigner(address(paymaster));
        vm.stopPrank();

        vm.startPrank(creator);
        creatorCore1.registerExtension(address(example), "override");
        creatorCore2.registerExtension(address(example), "override");
        vm.stopPrank();

        vm.deal(owner, 10 ether);
        vm.deal(creator, 10 ether);
        vm.deal(other, 10 ether);
    }

    function testAccess() public {
        vm.startPrank(other);
        // Must be admin
        vm.expectRevert();
        example.setSigner(other);

        IERC1155FrameLazyClaim.ClaimParameters memory claimP = IERC1155FrameLazyClaim.ClaimParameters({
          location: "arweaveHash1",
          storageProtocol: IFrameLazyClaim.StorageProtocol.ARWEAVE,
          paymentReceiver: payable(creator)
        });
        // Must be admin
        vm.expectRevert();
        example.initializeClaim(address(creatorCore1), 1, claimP);
        // Succeeds because is admin
        vm.stopPrank();
        vm.startPrank(creator);
        example.initializeClaim(address(creatorCore1), 1, claimP);

        // Update, not admin
        vm.stopPrank();
        vm.startPrank(other);
        vm.expectRevert();
        example.updateTokenURIParams(address(creatorCore1), 1, IFrameLazyClaim.StorageProtocol.IPFS, "");

        vm.expectRevert();
        example.extendTokenURI(address(creatorCore1), 2, "");

        vm.stopPrank();
        vm.startPrank(creator);
        example.updateTokenURIParams(address(creatorCore1), 1, IFrameLazyClaim.StorageProtocol.ARWEAVE, "arweaveHash3");
        assertEq("https://arweave.net/arweaveHash3", creatorCore1.uri(1));
        // Extend uri
        vm.expectRevert();
        example.extendTokenURI(address(creatorCore1), 1, "");
        example.updateTokenURIParams(address(creatorCore1), 1, IFrameLazyClaim.StorageProtocol.NONE, "part1");
        example.extendTokenURI(address(creatorCore1), 1, "part2");
        assertEq("part1part2", creatorCore1.uri(1));

        vm.stopPrank();
    }

    function testinitializeClaimSanitization() public {
        vm.startPrank(creator);

        IERC1155FrameLazyClaim.ClaimParameters memory claimP = IERC1155FrameLazyClaim.ClaimParameters({
            location: "arweaveHash1",
            storageProtocol: IFrameLazyClaim.StorageProtocol.INVALID,
            paymentReceiver: payable(creator)
        });

        vm.expectRevert("Cannot initialize with invalid storage protocol");
        example.initializeClaim(address(creatorCore1), 1, claimP);

        vm.expectRevert("Claim not initialized");
        example.updateTokenURIParams(address(creatorCore1), 1, IFrameLazyClaim.StorageProtocol.NONE, "");
        vm.expectRevert("Invalid storage protocol");
        example.extendTokenURI(address(creatorCore1), 1, "");

        vm.stopPrank();
    }

    function testUpdateClaimSanitization() public {
        vm.startPrank(creator);

        IERC1155FrameLazyClaim.ClaimParameters memory claimP = IERC1155FrameLazyClaim.ClaimParameters({
            location: "arweaveHash1",
            storageProtocol: IFrameLazyClaim.StorageProtocol.ARWEAVE,
            paymentReceiver: payable(creator)
        });

        example.initializeClaim(address(creatorCore1), 1, claimP);

        claimP.storageProtocol = IFrameLazyClaim.StorageProtocol.INVALID;
        vm.expectRevert("Cannot set invalid storage protocol");
        example.updateTokenURIParams(address(creatorCore1), 1, IFrameLazyClaim.StorageProtocol.INVALID, "");

        vm.stopPrank();
    }

    function testInvalidSigner() public {
        vm.startPrank(creator);
        IERC1155FrameLazyClaim.ClaimParameters memory claimP = IERC1155FrameLazyClaim.ClaimParameters({
            location: "arweaveHash1",
            storageProtocol: IFrameLazyClaim.StorageProtocol.ARWEAVE,
            paymentReceiver: payable(creator)
        });

        example.initializeClaim(address(creatorCore1), 1, claimP);

        vm.stopPrank();
      
        vm.startPrank(other);

        IFrameLazyClaim.Mint[] memory mints = new IFrameLazyClaim.Mint[](1);
        mints[0] = IFrameLazyClaim.Mint({
            creatorContractAddress: address(creatorCore1),
            instanceId: 1,
            recipient: other,
            amount: 1,
            payment: 0
        });
        vm.expectRevert(IFrameLazyClaim.InvalidSignature.selector);
        example.mint(mints);
        vm.stopPrank();
    }

    function testMintNoPayment() public {
        vm.startPrank(creator);
        IERC1155FrameLazyClaim.ClaimParameters memory claimP = IERC1155FrameLazyClaim.ClaimParameters({
          location: "arweaveHash1",
          storageProtocol: IFrameLazyClaim.StorageProtocol.ARWEAVE,
          paymentReceiver: payable(creator)
        });

        example.initializeClaim(address(creatorCore1), 1, claimP);

        vm.stopPrank();
      
        IFramePaymaster.Mint[] memory mints = new IFramePaymaster.Mint[](1);
        mints[0] = IFramePaymaster.Mint({
            creatorContractAddress: address(creatorCore1),
            instanceId: 1,
            amount: 5,
            payment: 0
        });
        IFramePaymaster.ExtensionMint[] memory extensionMints = new IFramePaymaster.ExtensionMint[](1);
        extensionMints[0] = IFramePaymaster.ExtensionMint({
            extensionAddress: address(example),
            mints: mints
        });

        IFramePaymaster.MintSubmission memory submission = _constructSubmission(extensionMints, 1, block.timestamp+1000, 1, 0);

        vm.startPrank(other);
        paymaster.checkout(submission);
        vm.stopPrank();

        assertEq(5, creatorCore1.balanceOf(other, 1));
    }

    function testMintWithPayment() public {
        vm.startPrank(creator);
        IERC1155FrameLazyClaim.ClaimParameters memory claimP = IERC1155FrameLazyClaim.ClaimParameters({
          location: "arweaveHash1",
          storageProtocol: IFrameLazyClaim.StorageProtocol.ARWEAVE,
          paymentReceiver: payable(creator)
        });

        example.initializeClaim(address(creatorCore1), 1, claimP);

        vm.stopPrank();
      
        IFramePaymaster.Mint[] memory mints = new IFramePaymaster.Mint[](1);
        mints[0] = IFramePaymaster.Mint({
            creatorContractAddress: address(creatorCore1),
            instanceId: 1,
            amount: 5,
            payment: 1 ether
        });
        IFramePaymaster.ExtensionMint[] memory extensionMints = new IFramePaymaster.ExtensionMint[](1);
        extensionMints[0] = IFramePaymaster.ExtensionMint({
            extensionAddress: address(example),
            mints: mints
        });

        IFramePaymaster.MintSubmission memory submission = _constructSubmission(extensionMints, 1, block.timestamp+1000, 1, 1 ether);

        vm.startPrank(other);
        paymaster.checkout{value: 1 ether}(submission);
        vm.stopPrank();

        assertEq(5, creatorCore1.balanceOf(other, 1));
        assertEq(11 ether, creator.balance);
    }

    function testMintMultipleForOneExtensionWithPayment() public {
        vm.startPrank(creator);
        IERC1155FrameLazyClaim.ClaimParameters memory claimP1 = IERC1155FrameLazyClaim.ClaimParameters({
          location: "arweaveHash1",
          storageProtocol: IFrameLazyClaim.StorageProtocol.ARWEAVE,
          paymentReceiver: payable(creator)
        });

        example.initializeClaim(address(creatorCore1), 1, claimP1);

        IERC1155FrameLazyClaim.ClaimParameters memory claimP2 = IERC1155FrameLazyClaim.ClaimParameters({
          location: "arweaveHash2",
          storageProtocol: IFrameLazyClaim.StorageProtocol.ARWEAVE,
          paymentReceiver: payable(creatorOtherReceiver)
        });

        example.initializeClaim(address(creatorCore2), 2, claimP2);

        vm.stopPrank();
      
        IFramePaymaster.Mint[] memory mints = new IFramePaymaster.Mint[](2);
        mints[0] = IFramePaymaster.Mint({
            creatorContractAddress: address(creatorCore1),
            instanceId: 1,
            amount: 5,
            payment: 1 ether
        });
        mints[1] = IFramePaymaster.Mint({
            creatorContractAddress: address(creatorCore2),
            instanceId: 2,
            amount: 2,
            payment: 2 ether
        });
        IFramePaymaster.ExtensionMint[] memory extensionMints = new IFramePaymaster.ExtensionMint[](1);
        extensionMints[0] = IFramePaymaster.ExtensionMint({
            extensionAddress: address(example),
            mints: mints
        });

        IFramePaymaster.MintSubmission memory submission = _constructSubmission(extensionMints, 1, block.timestamp+1000, 1, 3 ether);

        vm.startPrank(other);
        paymaster.checkout{value: 3 ether}(submission);
        vm.stopPrank();

        assertEq(5, creatorCore1.balanceOf(other, 1));
        assertEq(11 ether, creator.balance);
        assertEq(2, creatorCore2.balanceOf(other, 1));
        assertEq(2 ether, creatorOtherReceiver.balance);
    }

    function testMintMultipleExtensionsWithPayment() public {
        vm.startPrank(owner);
        ERC1155FrameLazyClaim example2 = new ERC1155FrameLazyClaim(owner);
        example2.setSigner(address(paymaster));
        vm.stopPrank();

        vm.startPrank(creator);
        IERC1155FrameLazyClaim.ClaimParameters memory claimP1 = IERC1155FrameLazyClaim.ClaimParameters({
          location: "arweaveHash1",
          storageProtocol: IFrameLazyClaim.StorageProtocol.ARWEAVE,
          paymentReceiver: payable(creator)
        });

        example.initializeClaim(address(creatorCore1), 1, claimP1);

        creatorCore2.registerExtension(address(example2), "override");
        IERC1155FrameLazyClaim.ClaimParameters memory claimP2 = IERC1155FrameLazyClaim.ClaimParameters({
          location: "arweaveHash2",
          storageProtocol: IFrameLazyClaim.StorageProtocol.ARWEAVE,
          paymentReceiver: payable(creatorOtherReceiver)
        });

        example2.initializeClaim(address(creatorCore2), 2, claimP2);

        vm.stopPrank();
      
        IFramePaymaster.Mint[] memory mints1 = new IFramePaymaster.Mint[](1);
        mints1[0] = IFramePaymaster.Mint({
            creatorContractAddress: address(creatorCore1),
            instanceId: 1,
            amount: 5,
            payment: 1 ether
        });
        IFramePaymaster.Mint[] memory mints2 = new IFramePaymaster.Mint[](1);
        mints2[0] = IFramePaymaster.Mint({
            creatorContractAddress: address(creatorCore2),
            instanceId: 2,
            amount: 2,
            payment: 2 ether
        });
        IFramePaymaster.ExtensionMint[] memory extensionMints = new IFramePaymaster.ExtensionMint[](2);
        extensionMints[0] = IFramePaymaster.ExtensionMint({
            extensionAddress: address(example),
            mints: mints1
        });
        extensionMints[1] = IFramePaymaster.ExtensionMint({
            extensionAddress: address(example2),
            mints: mints2
        });

        IFramePaymaster.MintSubmission memory submission = _constructSubmission(extensionMints, 1, block.timestamp+1000, 1, 3 ether);

        vm.startPrank(other);
        paymaster.checkout{value: 3 ether}(submission);
        vm.stopPrank();

        assertEq(5, creatorCore1.balanceOf(other, 1));
        assertEq(11 ether, creator.balance);
        assertEq(2, creatorCore2.balanceOf(other, 1));
        assertEq(2 ether, creatorOtherReceiver.balance);
    }

    function _constructSubmission(IFramePaymaster.ExtensionMint[] memory extensionMints, uint256 fid, uint256 expiration, uint256 nonce, uint256 totalAmount) internal view returns (IFramePaymaster.MintSubmission memory submission) {
        bytes memory messageData = abi.encode(extensionMints, fid, expiration, nonce, totalAmount);
        bytes32 message = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageData));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, message);
        bytes memory signature = abi.encodePacked(r, s, v);

        submission.signature = signature;
        submission.message = message;
        submission.extensionMints = extensionMints;
        submission.fid = fid;
        submission.expiration = expiration;
        submission.nonce = nonce;
    }

}
