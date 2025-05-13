// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../contracts/lazyUpdatableFeeClaim/ERC1155LazyPayableClaimV2.sol";
import "../../contracts/lazyclaim/IERC1155LazyPayableClaim.sol";
import "../../contracts/lazyclaim/IERC1155LazyPayableClaimMetadata.sol";
import "@manifoldxyz/creator-core-solidity/contracts/ERC1155Creator.sol";
import "../mocks/delegation-registry/DelegationRegistry.sol";
import "../mocks/delegation-registry/DelegationRegistryV2.sol";
import "../mocks/Mock.sol";
import "../../lib/murky/src/Merkle.sol";

contract ERC1155LazyPayableClaimMetadataV2 is IERC1155LazyPayableClaimMetadata {
    using Strings for uint256;

    function tokenURI(address creatorContract, uint256 tokenId, uint256 instanceId)
        external
        pure
        override
        returns (string memory)
    {
        return string(
            abi.encodePacked(
                uint256(uint160(creatorContract)).toString(), "/", tokenId.toString(), "/", instanceId.toString()
            )
        );
    }
}

contract ERC1155LazyPayableClaimTest is Test {
    using Strings for uint256;

    ERC1155LazyPayableClaimV2 public example;
    ERC1155Creator public creatorCore;
    ERC1155LazyPayableClaimMetadataV2 public metadata;
    DelegationRegistry public delegationRegistry;
    DelegationRegistryV2 public delegationRegistryV2;
    MockManifoldMembership public manifoldMembership;
    Merkle public merkle;
    uint256 public defaultMintFee = 500000000000000;
    uint256 public defaultMintFeeMerkle = 690000000000000;

    // creator of the extension contract
    address public owner = 0x6140F00e4Ff3936702E68744f2b5978885464cbB;
    // creator of the creator contract
    address public creator = 0xCD56df7B4705A99eBEBE2216e350638a1582bEC4;
    address public other = 0xc78Dc443c126af6E4f6Ed540c1e740C1b5be09cd;
    address public other2 = 0x80AAC46bbd3C2FcE33681541a52CacBEd14bF425;
    address public other3 = 0x5174cD462b60c536eb51D4ceC1D561D3Ea31004F;

    address public zeroAddress = address(0);

    function setUp() public {
        vm.startPrank(owner);
        delegationRegistry = new DelegationRegistry();
        delegationRegistryV2 = new DelegationRegistryV2();
        example = new ERC1155LazyPayableClaimV2(owner, address(delegationRegistry), address(delegationRegistryV2));
        // set mint fees
        example.setMintFees(defaultMintFee, defaultMintFeeMerkle);

        manifoldMembership = new MockManifoldMembership();
        example.setMembershipAddress(address(manifoldMembership));
        metadata = new ERC1155LazyPayableClaimMetadataV2();

        merkle = new Merkle();

        vm.deal(owner, 10 ether);
        vm.deal(creator, 10 ether);
        vm.deal(other, 10 ether);
        vm.deal(other2, 10 ether);
        vm.deal(other3, 10 ether);
        vm.stopPrank();

        vm.startPrank(creator);
        creatorCore = new ERC1155Creator("Token", "NFT");
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
        // Must be admin to set mint fees
        vm.expectRevert("AdminControl: Must be owner or admin");
        example.setMintFees(defaultMintFee, defaultMintFeeMerkle);
        // Must be admin to pause/unpause
        vm.expectRevert();
        example.setActive(false);

        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;

        IERC1155LazyPayableClaim.ClaimParameters memory claimP = IERC1155LazyPayableClaim.ClaimParameters({
            merkleRoot: "",
            location: "arweaveHash1",
            totalMax: 10,
            walletMax: 1,
            startDate: nowC,
            endDate: later,
            storageProtocol: ILazyPayableClaimCore.StorageProtocol.ARWEAVE,
            cost: 1,
            paymentReceiver: payable(other),
            erc20: zeroAddress,
            signingAddress: address(0)
        });
        // Must be admin
        vm.expectRevert();
        example.initializeClaim(address(creatorCore), 1, claimP);
        // Succeeds because is admin
        vm.stopPrank();
        vm.startPrank(creator);
        example.initializeClaim(address(creatorCore), 1, claimP);
        // can't set mint fees as creator
        vm.expectRevert();
        example.setMintFees(defaultMintFee, defaultMintFeeMerkle);
        // can't pause, unpause as creator
        vm.expectRevert();
        example.setActive(false);
        vm.stopPrank();
        // Update, not admin
        vm.stopPrank();
        vm.startPrank(other);
        vm.expectRevert();
        example.updateClaim(address(creatorCore), 1, claimP);

        vm.expectRevert();
        example.updateTokenURIParams(address(creatorCore), 1, ILazyPayableClaimCore.StorageProtocol.IPFS, "");

        vm.expectRevert();
        example.extendTokenURI(address(creatorCore), 2, "");

        vm.stopPrank();
        vm.startPrank(creator);

        claimP.totalMax = 9;
        claimP.paymentReceiver = payable(creator);
        example.updateClaim(address(creatorCore), 1, claimP);

        ERC1155LazyPayableClaimV2.Claim memory claim = example.getClaim(address(creatorCore), 1);

        assertEq(claim.merkleRoot, "");
        assertEq(claim.location, "arweaveHash1");
        assertEq(claim.totalMax, 9);
        assertEq(claim.walletMax, 1);
        assertEq(claim.startDate, nowC);
        assertEq(claim.endDate, later);
        assertEq(claim.cost, 1);
        assertEq(claim.paymentReceiver, creator);

        assertEq("https://arweave.net/arweaveHash1", creatorCore.uri(1));

        example.updateTokenURIParams(
            address(creatorCore), 1, ILazyPayableClaimCore.StorageProtocol.ARWEAVE, "arweaveHash3"
        );
        assertEq("https://arweave.net/arweaveHash3", creatorCore.uri(1));
        // Extend uri
        vm.expectRevert();
        example.extendTokenURI(address(creatorCore), 1, "");
        example.updateTokenURIParams(address(creatorCore), 1, ILazyPayableClaimCore.StorageProtocol.NONE, "part1");
        example.extendTokenURI(address(creatorCore), 1, "part2");
        assertEq("part1part2", creatorCore.uri(1));

        vm.stopPrank();
    }

    function testinitializeClaimSanitization() public {
        vm.startPrank(creator);
        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;

        IERC1155LazyPayableClaim.ClaimParameters memory claimP = IERC1155LazyPayableClaim.ClaimParameters({
            merkleRoot: "",
            location: "arweaveHash1",
            totalMax: 10,
            walletMax: 1,
            startDate: nowC,
            endDate: later,
            storageProtocol: ILazyPayableClaimCore.StorageProtocol.INVALID,
            cost: 1,
            paymentReceiver: payable(other),
            erc20: zeroAddress,
            signingAddress: address(0)
        });

        vm.expectRevert(ILazyPayableClaimCore.InvalidStorageProtocol.selector);
        example.initializeClaim(address(creatorCore), 1, claimP);

        claimP.startDate = nowC + 2000;
        claimP.storageProtocol = ILazyPayableClaimCore.StorageProtocol.ARWEAVE;
        vm.expectRevert(ILazyPayableClaimCore.InvalidStartDate.selector);
        example.initializeClaim(address(creatorCore), 1, claimP);

        claimP.startDate = nowC;
        claimP.merkleRoot = "0x0";
        vm.expectRevert("Cannot provide both walletMax and merkleRoot");
        example.initializeClaim(address(creatorCore), 1, claimP);

        claimP.merkleRoot = "";
        vm.expectRevert(ILazyPayableClaimCore.ClaimNotInitialized.selector);
        example.updateClaim(address(creatorCore), 1, claimP);

        vm.stopPrank();
    }

    function testUpdateClaimSanitization() public {
        vm.startPrank(creator);
        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;

        IERC1155LazyPayableClaim.ClaimParameters memory claimP = IERC1155LazyPayableClaim.ClaimParameters({
            merkleRoot: "",
            location: "arweaveHash1",
            totalMax: 10,
            walletMax: 1,
            startDate: nowC,
            endDate: later,
            storageProtocol: ILazyPayableClaimCore.StorageProtocol.ARWEAVE,
            cost: 1,
            paymentReceiver: payable(other),
            erc20: zeroAddress,
            signingAddress: address(0)
        });

        example.initializeClaim(address(creatorCore), 1, claimP);

        claimP.storageProtocol = ILazyPayableClaimCore.StorageProtocol.INVALID;
        vm.expectRevert(ILazyPayableClaimCore.InvalidStorageProtocol.selector);
        example.updateClaim(address(creatorCore), 1, claimP);

        claimP.storageProtocol = ILazyPayableClaimCore.StorageProtocol.ADDRESS;
        vm.expectRevert(ILazyPayableClaimCore.InvalidStorageProtocol.selector);
        example.updateClaim(address(creatorCore), 1, claimP);

        claimP.startDate = nowC + 2000;
        claimP.storageProtocol = ILazyPayableClaimCore.StorageProtocol.ARWEAVE;
        vm.expectRevert(ILazyPayableClaimCore.InvalidStartDate.selector);
        example.updateClaim(address(creatorCore), 1, claimP);

        claimP.startDate = nowC;
        claimP.erc20 = 0x0000000000000000000000000000000000000001;
        vm.expectRevert(ILazyPayableClaimCore.CannotChangePaymentToken.selector);
        example.updateClaim(address(creatorCore), 1, claimP);

        vm.expectRevert(ILazyPayableClaimCore.InvalidStorageProtocol.selector);
        example.updateTokenURIParams(address(creatorCore), 1, ILazyPayableClaimCore.StorageProtocol.INVALID, "");

        vm.expectRevert(ILazyPayableClaimCore.InvalidStorageProtocol.selector);
        example.updateTokenURIParams(address(creatorCore), 1, ILazyPayableClaimCore.StorageProtocol.ADDRESS, "");
        vm.stopPrank();
    }

    function testMerkleMint() public {
        vm.startPrank(creator);
        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;

        bytes32[] memory allowListTuples = new bytes32[](4);
        allowListTuples[0] = keccak256(abi.encodePacked(creator, uint32(0)));
        allowListTuples[1] = keccak256(abi.encodePacked(other2, uint32(1)));
        allowListTuples[2] = keccak256(abi.encodePacked(other2, uint32(2)));
        allowListTuples[3] = keccak256(abi.encodePacked(other3, uint32(3)));

        IERC1155LazyPayableClaim.ClaimParameters memory claimP = IERC1155LazyPayableClaim.ClaimParameters({
            merkleRoot: merkle.getRoot(allowListTuples),
            location: "arweaveHash1",
            totalMax: 3,
            walletMax: 0,
            startDate: nowC,
            endDate: later,
            storageProtocol: ILazyPayableClaimCore.StorageProtocol.ARWEAVE,
            cost: 1,
            paymentReceiver: payable(other),
            erc20: zeroAddress,
            signingAddress: address(0)
        });

        example.initializeClaim(address(creatorCore), 1, claimP);

        // Balance of creator should be zero, we defer creating the token until the first mint or airdrop
        assertEq(creatorCore.balanceOf(creator, 1), 0);

        bytes32[] memory merkleProof1 = merkle.getProof(allowListTuples, uint32(0));

        vm.stopPrank();
        vm.startPrank(other);

        vm.expectRevert("Could not verify merkle proof");
        example.mint(address(creatorCore), 1, 1, merkleProof1, other);

        vm.stopPrank();
        vm.startPrank(other2);
        vm.expectRevert("Could not verify merkle proof");
        example.mint(address(creatorCore), 1, 0, merkleProof1, other2);

        vm.stopPrank();
        vm.startPrank(creator);

        uint256 mintFee = example.MINT_FEE_MERKLE() + 1;

        example.mint{value: mintFee}(address(creatorCore), 1, 0, merkleProof1, creator);

        vm.roll(block.number + 1);
        vm.expectRevert("Already minted");
        example.mint{value: mintFee}(address(creatorCore), 1, 0, merkleProof1, creator);

        vm.stopPrank();
        vm.startPrank(other2);

        bytes32[] memory merkleProof2 = merkle.getProof(allowListTuples, uint32(1));

        example.mint{value: mintFee}(address(creatorCore), 1, 1, merkleProof2, other2);
        bytes32[] memory merkleProof3 = merkle.getProof(allowListTuples, uint32(2));

        example.mint{value: mintFee}(address(creatorCore), 1, 2, merkleProof3, other2);

        vm.stopPrank();
        vm.startPrank(other3);
        bytes32[] memory merkleProof4 = merkle.getProof(allowListTuples, uint32(3));

        vm.expectRevert(ILazyPayableClaimCore.TooManyRequested.selector);
        example.mint{value: mintFee}(address(creatorCore), 1, 3, merkleProof4, other3);

        claimP.totalMax = 4;
        vm.stopPrank();
        vm.startPrank(creator);
        example.updateClaim(address(creatorCore), 1, claimP);
        vm.stopPrank();
        vm.startPrank(other3);
        example.mint{value: mintFee}(address(creatorCore), 1, 3, merkleProof4, other3);

        vm.stopPrank();
    }

    function testMerkleMintBatch() public {
        vm.startPrank(creator);
        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;
        uint256 mintFee = example.MINT_FEE_MERKLE() + 1;

        bytes32[] memory allowListTuples = new bytes32[](5);
        allowListTuples[0] = keccak256(abi.encodePacked(creator, uint32(0)));
        allowListTuples[1] = keccak256(abi.encodePacked(other2, uint32(1)));
        allowListTuples[2] = keccak256(abi.encodePacked(other2, uint32(2)));
        allowListTuples[3] = keccak256(abi.encodePacked(other3, uint32(3)));
        allowListTuples[4] = keccak256(abi.encodePacked(other3, uint32(4)));

        IERC1155LazyPayableClaim.ClaimParameters memory claimP = IERC1155LazyPayableClaim.ClaimParameters({
            merkleRoot: merkle.getRoot(allowListTuples),
            location: "arweaveHash1",
            totalMax: 3,
            walletMax: 0,
            startDate: nowC,
            endDate: later,
            storageProtocol: ILazyPayableClaimCore.StorageProtocol.ARWEAVE,
            cost: 1,
            paymentReceiver: payable(other),
            erc20: zeroAddress,
            signingAddress: address(0)
        });

        example.initializeClaim(address(creatorCore), 1, claimP);

        bytes32[] memory merkleProof1 = merkle.getProof(allowListTuples, uint32(0));

        vm.stopPrank();
        vm.startPrank(creator);

        uint32[] memory amountsInput = new uint32[](1);
        amountsInput[0] = 0;

        bytes32[][] memory proofsInput = new bytes32[][](1);
        proofsInput[0] = merkleProof1;

        vm.expectRevert(ILazyPayableClaimCore.InvalidInput.selector);
        example.mintBatch(address(creatorCore), 1, 2, amountsInput, proofsInput, creator);

        amountsInput = new uint32[](2);
        amountsInput[0] = 0;
        amountsInput[1] = 0;

        vm.expectRevert(ILazyPayableClaimCore.InvalidInput.selector);
        example.mintBatch(address(creatorCore), 1, 1, amountsInput, proofsInput, creator);

        amountsInput = new uint32[](1);
        amountsInput[0] = 0;
        proofsInput = new bytes32[][](2);
        proofsInput[0] = merkleProof1;
        proofsInput[1] = merkleProof1;
        vm.expectRevert(ILazyPayableClaimCore.InvalidInput.selector);
        example.mintBatch(address(creatorCore), 1, 1, amountsInput, proofsInput, creator);

        proofsInput = new bytes32[][](1);
        proofsInput[0] = merkleProof1;
        example.mintBatch{value: mintFee}(address(creatorCore), 1, 1, amountsInput, proofsInput, creator);

        vm.expectRevert("Already minted");
        example.mint{value: mintFee}(address(creatorCore), 1, 0, merkleProof1, creator);
        vm.expectRevert("Already minted");
        example.mintBatch{value: mintFee}(address(creatorCore), 1, 1, amountsInput, proofsInput, creator);

        bytes32[] memory merkleProof2 = merkle.getProof(allowListTuples, uint32(1));
        bytes32[] memory merkleProof3 = merkle.getProof(allowListTuples, uint32(2));
        bytes32[] memory merkleProof4 = merkle.getProof(allowListTuples, uint32(3));
        bytes32[] memory merkleProof5 = merkle.getProof(allowListTuples, uint32(4));

        amountsInput = new uint32[](2);
        amountsInput[0] = 1;
        amountsInput[1] = 3;

        proofsInput = new bytes32[][](2);
        proofsInput[0] = merkleProof2;
        proofsInput[1] = merkleProof4;

        vm.stopPrank();
        vm.startPrank(other2);
        vm.expectRevert("Could not verify merkle proof");
        example.mintBatch(address(creatorCore), 1, 2, amountsInput, proofsInput, other2);

        proofsInput[1] = merkleProof3;
        amountsInput[1] = 2;
        example.mintBatch{value: mintFee * 2}(address(creatorCore), 1, 2, amountsInput, proofsInput, other2);

        vm.stopPrank();
        vm.startPrank(creator);

        address[] memory recipientsInput = new address[](1);
        recipientsInput[0] = other3;

        uint256[] memory mintsInput = new uint256[](1);
        mintsInput[0] = 1;

        string[] memory urisInput = new string[](1);
        urisInput[0] = "";
        // base mint something in between
        creatorCore.mintBaseNew(recipientsInput, mintsInput, urisInput);

        vm.stopPrank();
        vm.startPrank(other3);

        amountsInput = new uint32[](1);
        amountsInput[0] = 3;

        proofsInput = new bytes32[][](1);
        proofsInput[0] = merkleProof4;
        vm.expectRevert(ILazyPayableClaimCore.TooManyRequested.selector);
        example.mintBatch(address(creatorCore), 1, 1, amountsInput, proofsInput, other3);

        vm.stopPrank();
        vm.startPrank(creator);
        claimP.totalMax = 4;
        example.updateClaim(address(creatorCore), 1, claimP);

        vm.stopPrank();
        vm.startPrank(other3);
        amountsInput = new uint32[](2);
        amountsInput[0] = 3;
        amountsInput[1] = 4;

        proofsInput = new bytes32[][](2);
        proofsInput[0] = merkleProof4;
        proofsInput[1] = merkleProof5;
        vm.expectRevert(ILazyPayableClaimCore.TooManyRequested.selector);
        example.mintBatch(address(creatorCore), 1, 2, amountsInput, proofsInput, other3);

        vm.stopPrank();
        vm.startPrank(creator);
        claimP.totalMax = 5;
        example.updateClaim(address(creatorCore), 1, claimP);

        // Cannot mint with same mintIndex again
        vm.stopPrank();
        vm.startPrank(other2);
        vm.expectRevert("Already minted");
        example.mint(address(creatorCore), 1, 1, merkleProof2, other2);
        vm.expectRevert("Already minted");
        example.mint(address(creatorCore), 1, 2, merkleProof3, other2);

        amountsInput[0] = 1;
        amountsInput[1] = 2;
        proofsInput[0] = merkleProof2;
        proofsInput[1] = merkleProof3;
        vm.expectRevert("Already minted");
        example.mintBatch(address(creatorCore), 1, 2, amountsInput, proofsInput, other2);

        vm.stopPrank();
        vm.startPrank(other3);

        amountsInput[0] = 3;
        amountsInput[1] = 4;
        proofsInput[0] = merkleProof4;
        proofsInput[1] = merkleProof5;
        example.mintBatch{value: mintFee * 2}(address(creatorCore), 1, 2, amountsInput, proofsInput, other3);

        assertEq(creatorCore.balanceOf(creator, 1), 1);
        assertEq(creatorCore.balanceOf(other2, 1), 2);
        assertEq(creatorCore.balanceOf(other3, 1), 2);
        assertEq(creatorCore.uri(1), "https://arweave.net/arweaveHash1");

        vm.stopPrank();
    }

    function testNonMerkleMintBatch() public {
        vm.startPrank(creator);
        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;
        uint256 mintFee = example.MINT_FEE_MERKLE() + 1;

        IERC1155LazyPayableClaim.ClaimParameters memory claimP = IERC1155LazyPayableClaim.ClaimParameters({
            merkleRoot: "",
            location: "arweaveHash1",
            totalMax: 5,
            walletMax: 3,
            startDate: nowC,
            endDate: later,
            storageProtocol: ILazyPayableClaimCore.StorageProtocol.ARWEAVE,
            cost: 1,
            paymentReceiver: payable(other),
            erc20: zeroAddress,
            signingAddress: address(0)
        });

        example.initializeClaim(address(creatorCore), 1, claimP);

        vm.stopPrank();
        vm.startPrank(creator);
        vm.expectRevert(ILazyPayableClaimCore.TooManyRequested.selector);
        example.mintBatch{value: mintFee * 4}(address(creatorCore), 1, 4, new uint32[](0), new bytes32[][](0), creator);

        example.mintBatch{value: mintFee * 3}(address(creatorCore), 1, 3, new uint32[](0), new bytes32[][](0), creator);

        vm.expectRevert(ILazyPayableClaimCore.TooManyRequested.selector);
        example.mintBatch{value: mintFee}(address(creatorCore), 1, 1, new uint32[](0), new bytes32[][](0), creator);

        vm.stopPrank();
        vm.startPrank(other2);
        vm.expectRevert(ILazyPayableClaimCore.TooManyRequested.selector);
        example.mintBatch{value: mintFee * 3}(address(creatorCore), 1, 3, new uint32[](0), new bytes32[][](0), other2);

        example.mintBatch{value: mintFee * 2}(address(creatorCore), 1, 2, new uint32[](0), new bytes32[][](0), other2);

        vm.stopPrank();
    }

    function testNonMerkleMintNotEnoughMoney() public {
        vm.startPrank(creator);
        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;
        uint256 mintFee = example.MINT_FEE_MERKLE() + 1;

        IERC1155LazyPayableClaim.ClaimParameters memory claimP = IERC1155LazyPayableClaim.ClaimParameters({
            merkleRoot: "",
            location: "arweaveHash1",
            totalMax: 5,
            walletMax: 3,
            startDate: nowC,
            endDate: later,
            storageProtocol: ILazyPayableClaimCore.StorageProtocol.ARWEAVE,
            cost: 1,
            paymentReceiver: payable(other),
            erc20: zeroAddress,
            signingAddress: address(0)
        });

        example.initializeClaim(address(creatorCore), 1, claimP);

        vm.stopPrank();
        vm.startPrank(creator);
        vm.expectRevert("Invalid amount");
        example.mintBatch{value: mintFee * 2}(address(creatorCore), 1, 3, new uint32[](0), new bytes32[][](0), creator);

        vm.expectRevert("Invalid amount");
        example.mintBatch{value: 2}(address(creatorCore), 1, 2, new uint32[](0), new bytes32[][](0), creator);

        vm.expectRevert("Invalid amount");
        example.mint(address(creatorCore), 1, 0, new bytes32[](0), creator);

        vm.stopPrank();
    }

    function testNonMerkleMintCheckBalance() public {
        vm.startPrank(creator);
        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;
        uint256 mintFee = example.MINT_FEE_MERKLE() + 1;

        IERC1155LazyPayableClaim.ClaimParameters memory claimP = IERC1155LazyPayableClaim.ClaimParameters({
            merkleRoot: "",
            location: "arweaveHash1",
            totalMax: 5,
            walletMax: 3,
            startDate: nowC,
            endDate: later,
            storageProtocol: ILazyPayableClaimCore.StorageProtocol.ARWEAVE,
            cost: 1,
            paymentReceiver: payable(creator),
            erc20: zeroAddress,
            signingAddress: address(0)
        });

        example.initializeClaim(address(creatorCore), 1, claimP);

        uint256 beforeBalance = creator.balance;
        vm.stopPrank();
        vm.startPrank(other2);
        example.mintBatch{value: mintFee}(address(creatorCore), 1, 1, new uint32[](0), new bytes32[][](0), other2);
        example.mint{value: mintFee}(address(creatorCore), 1, 0, new bytes32[](0), other2);
        uint256 afterBalance = creator.balance;
        assertEq(2, afterBalance - beforeBalance);
        vm.stopPrank();
    }

    function testTokenURI() public {
        vm.startPrank(creator);
        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;
        uint256 mintFee = example.MINT_FEE() + 1;

        IERC1155LazyPayableClaim.ClaimParameters memory claimP = IERC1155LazyPayableClaim.ClaimParameters({
            merkleRoot: "",
            location: "XXX",
            totalMax: 11,
            walletMax: 3,
            startDate: nowC,
            endDate: later,
            storageProtocol: ILazyPayableClaimCore.StorageProtocol.ARWEAVE,
            cost: 1,
            paymentReceiver: payable(creator),
            erc20: zeroAddress,
            signingAddress: address(0)
        });

        address[] memory recipientsInput = new address[](1);
        recipientsInput[0] = other;
        uint256[] memory amountsInput = new uint256[](1);
        amountsInput[0] = 1;
        string[] memory urisInput = new string[](1);
        urisInput[0] = "";

        // Mint a token using creator contract, to test breaking up extension's indexRange
        creatorCore.mintBaseNew(recipientsInput, amountsInput, urisInput);

        example.initializeClaim(address(creatorCore), 1, claimP);

        vm.stopPrank();
        vm.startPrank(other);
        // Mint 2 tokens using the extension
        example.mint{value: mintFee}(address(creatorCore), 1, 0, new bytes32[](0), other);
        vm.stopPrank();
        vm.startPrank(other2);
        example.mint{value: mintFee}(address(creatorCore), 1, 0, new bytes32[](0), other2);
        // Mint a token using creator contract, to test breaking up extension's indexRange
        vm.stopPrank();
        vm.startPrank(creator);
        creatorCore.mintBaseNew(recipientsInput, amountsInput, urisInput);
        // Mint 1 token using the extension
        vm.stopPrank();
        vm.startPrank(other3);
        example.mint{value: mintFee}(address(creatorCore), 1, 0, new bytes32[](0), other3);
        assertEq("https://arweave.net/XXX", creatorCore.uri(2));

        vm.stopPrank();
    }

    function testTokenURIAddress() public {
        vm.startPrank(creator);
        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;
        uint256 mintFee = example.MINT_FEE() + 1;
        uint256 instanceId = 101;

        IERC1155LazyPayableClaim.ClaimParameters memory claimP = IERC1155LazyPayableClaim.ClaimParameters({
            merkleRoot: "",
            location: string(abi.encodePacked(address(metadata))),
            totalMax: 11,
            walletMax: 3,
            startDate: nowC,
            endDate: later,
            storageProtocol: ILazyPayableClaimCore.StorageProtocol.ADDRESS,
            cost: 1,
            paymentReceiver: payable(creator),
            erc20: zeroAddress,
            signingAddress: address(0)
        });

        address[] memory recipientsInput = new address[](1);
        recipientsInput[0] = other;
        uint256[] memory amountsInput = new uint256[](1);
        amountsInput[0] = 1;
        string[] memory urisInput = new string[](1);
        urisInput[0] = "";

        // Mint a token using creator contract, to test breaking up extension's indexRange
        creatorCore.mintBaseNew(recipientsInput, amountsInput, urisInput);

        example.initializeClaim(address(creatorCore), instanceId, claimP);

        vm.stopPrank();
        vm.startPrank(other);
        // Mint 2 tokens using the extension
        example.mint{value: mintFee}(address(creatorCore), instanceId, 0, new bytes32[](0), other);
        vm.stopPrank();
        vm.startPrank(other2);
        example.mint{value: mintFee}(address(creatorCore), instanceId, 0, new bytes32[](0), other2);
        // Mint a token using creator contract, to test breaking up extension's indexRange
        vm.stopPrank();
        vm.startPrank(creator);
        creatorCore.mintBaseNew(recipientsInput, amountsInput, urisInput);
        // Mint 1 token using the extension
        vm.stopPrank();
        vm.startPrank(other3);
        example.mint{value: mintFee}(address(creatorCore), instanceId, 0, new bytes32[](0), other3);
        assertEq(
            string(abi.encodePacked(uint256(uint160(address(creatorCore))).toString(), "/2/101")), creatorCore.uri(2)
        );

        vm.stopPrank();
    }

    function testFunctionality() public {
        vm.startPrank(creator);
        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;
        uint256 mintFee = example.MINT_FEE_MERKLE();

        bytes32[] memory allowListTuples = new bytes32[](3);
        allowListTuples[0] = keccak256(abi.encodePacked(creator, uint32(0)));
        allowListTuples[1] = keccak256(abi.encodePacked(other2, uint32(1)));
        allowListTuples[2] = keccak256(abi.encodePacked(other2, uint32(2)));

        IERC1155LazyPayableClaim.ClaimParameters memory claimP = IERC1155LazyPayableClaim.ClaimParameters({
            merkleRoot: merkle.getRoot(allowListTuples),
            location: "arweaveHash",
            totalMax: 3,
            walletMax: 0,
            startDate: nowC + 500,
            endDate: later,
            storageProtocol: ILazyPayableClaimCore.StorageProtocol.ARWEAVE,
            cost: 1,
            paymentReceiver: payable(other),
            erc20: zeroAddress,
            signingAddress: address(0)
        });

        // Should fail to initialize if non-admin wallet is used
        vm.stopPrank();
        vm.startPrank(other);
        vm.expectRevert("Wallet is not an administrator for contract");
        example.initializeClaim(address(creatorCore), 1, claimP);

        // Cannot claim before initialization
        vm.stopPrank();
        vm.startPrank(creator);
        bytes32[] memory merkleProof1 = merkle.getProof(allowListTuples, uint32(0));
        vm.expectRevert(ILazyPayableClaimCore.ClaimNotInitialized.selector);
        example.mint(address(creatorCore), 1, 0, merkleProof1, creator);

        example.initializeClaim(address(creatorCore), 1, claimP);

        // Overwrite the claim with parameters changed
        claimP.location = "arweaveHash1";
        claimP.walletMax = 0;
        example.updateClaim(address(creatorCore), 1, claimP);

        // Initialize a second claim - with optional parameters disabled
        claimP.location = "arweaveHash2";
        claimP.totalMax = 0;
        claimP.startDate = 0;
        claimP.endDate = 0;
        claimP.walletMax = 0;
        claimP.merkleRoot = "";
        example.initializeClaim(address(creatorCore), 2, claimP);

        // Claim should have expected info
        IERC1155LazyPayableClaim.Claim memory claim = example.getClaim(address(creatorCore), 1);
        assertEq(claim.merkleRoot, merkle.getRoot(allowListTuples));
        assertEq(claim.location, "arweaveHash1");
        assertEq(claim.totalMax, 3);
        assertEq(claim.walletMax, 0);
        assertEq(claim.startDate, nowC + 500);
        assertEq(claim.endDate, later);

        // Test minting
        // Mint a token to random wallet
        vm.stopPrank();
        vm.startPrank(creator);
        vm.expectRevert(ILazyPayableClaimCore.ClaimInactive.selector);
        example.mint{value: mintFee + 1}(address(creatorCore), 1, 0, merkleProof1, creator);

        vm.warp(nowC + 501);
        example.mint{value: mintFee + 1}(address(creatorCore), 1, 0, merkleProof1, creator);

        claim = example.getClaim(address(creatorCore), 1);
        assertEq(claim.total, 1);

        // ClaimByToken should have expected info
        (uint256 instanceId, IERC1155LazyPayableClaim.Claim memory claimInfo) =
            example.getClaimForToken(address(creatorCore), 1);
        assertEq(instanceId, 1);
        assertEq(claimInfo.merkleRoot, merkle.getRoot(allowListTuples));
        assertEq(claimInfo.location, "arweaveHash1");
        assertEq(claimInfo.totalMax, 3);
        assertEq(claimInfo.walletMax, 0);
        assertEq(claimInfo.startDate, nowC + 500);
        assertEq(claimInfo.endDate, later);

        bytes32[] memory merkleProof2 = merkle.getProof(allowListTuples, uint32(1));
        vm.stopPrank();
        vm.startPrank(other2);
        example.mint{value: mintFee + 1}(address(creatorCore), 1, 1, merkleProof2, other2);

        // Now ensure that the creator contract state is what we expect after mints
        assertEq(creatorCore.balanceOf(creator, 1), 1);
        assertEq(creatorCore.balanceOf(other2, 1), 1);
        assertEq("https://arweave.net/arweaveHash1", creatorCore.uri(1));

        // Additionally test that tokenURIs are dynamic
        vm.stopPrank();
        vm.startPrank(creator);

        claimP.location = "test.com";
        claimP.endDate = later;
        example.updateClaim(address(creatorCore), 1, claimP);

        assertEq("https://arweave.net/test.com", creatorCore.uri(1));

        // Optional parameters - using claim 2
        // Cannot mint for someone else
        vm.expectRevert(ILazyPayableClaimCore.InvalidInput.selector);
        example.mint{value: mintFee}(address(creatorCore), 2, 0, new bytes32[](0), other);

        example.mint{value: mintFee + 1}(address(creatorCore), 2, 0, new bytes32[](0), creator);
        example.mint{value: mintFee + 1}(address(creatorCore), 2, 0, new bytes32[](0), creator);
        vm.stopPrank();
        vm.startPrank(other);
        example.mint{value: mintFee + 1}(address(creatorCore), 2, 0, new bytes32[](0), other);

        // end claim period
        vm.warp(later * 2);
        // Reverts due to end of mint period
        bytes32[] memory merkleProof3 = merkle.getProof(allowListTuples, uint32(2));

        vm.stopPrank();
        vm.startPrank(other2);
        vm.expectRevert(ILazyPayableClaimCore.ClaimInactive.selector);
        example.mint{value: mintFee + 1}(address(creatorCore), 1, 2, merkleProof3, other2);

        // Passes with valid withdrawal amount from owner
        vm.stopPrank();
        vm.startPrank(owner);
        uint256 balanceBefore = owner.balance;
        example.withdraw(payable(owner), mintFee);
        uint256 balanceAfter = owner.balance;
        assertEq(balanceAfter, balanceBefore + mintFee);

        vm.stopPrank();
    }

    function testAirdrop() public {
        vm.startPrank(creator);
        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;
        uint256 mintFee = example.MINT_FEE_MERKLE();

        bytes32[] memory allowListTuples = new bytes32[](2);
        allowListTuples[0] = keccak256(abi.encodePacked(creator, uint32(0)));
        allowListTuples[1] = keccak256(abi.encodePacked(other2, uint32(1)));

        IERC1155LazyPayableClaim.ClaimParameters memory claimP = IERC1155LazyPayableClaim.ClaimParameters({
            merkleRoot: merkle.getRoot(allowListTuples),
            location: "XXX",
            totalMax: 0,
            walletMax: 0,
            startDate: nowC,
            endDate: later,
            storageProtocol: ILazyPayableClaimCore.StorageProtocol.ARWEAVE,
            cost: 1,
            paymentReceiver: payable(other),
            erc20: zeroAddress,
            signingAddress: address(0)
        });
        address[] memory receivers = new address[](1);
        receivers[0] = other;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1;

        vm.expectRevert(ILazyPayableClaimCore.ClaimNotInitialized.selector);
        example.airdrop(address(creatorCore), 1, receivers, amounts);

        example.initializeClaim(address(creatorCore), 1, claimP);
        // Perform an airdrop
        example.airdrop(address(creatorCore), 1, receivers, amounts);

        IERC1155LazyPayableClaim.Claim memory claim = example.getClaim(address(creatorCore), 1);
        assertEq(claim.total, 1);
        assertEq(claim.totalMax, 0);

        // Mint
        bytes32[] memory merkleProof1 = merkle.getProof(allowListTuples, uint32(0));

        example.mint{value: mintFee + 1}(address(creatorCore), 1, 0, merkleProof1, creator);

        // Update totalMax to 1, will actually set to 2 because there are two
        claimP.totalMax = 1;
        example.updateClaim(address(creatorCore), 1, claimP);
        claim = example.getClaim(address(creatorCore), 1);
        assertEq(claim.totalMax, 2);

        // Perform another airdrop after minting
        receivers = new address[](2);
        receivers[0] = other2;
        receivers[1] = other3;
        amounts = new uint256[](2);
        amounts[0] = 1;
        amounts[1] = 5;
        example.airdrop(address(creatorCore), 1, receivers, amounts);
        claim = example.getClaim(address(creatorCore), 1);
        assertEq(claim.total, 8);
        assertEq(claim.totalMax, 8);

        // Update totalMax back to 0
        claimP.totalMax = 0;
        example.updateClaim(address(creatorCore), 1, claimP);
        claim = example.getClaim(address(creatorCore), 1);
        assertEq(claim.totalMax, 0);

        // Mint again after second airdrop
        bytes32[] memory merkleProof2 = merkle.getProof(allowListTuples, uint32(1));
        vm.stopPrank();
        vm.startPrank(other2);
        example.mint{value: mintFee + 1}(address(creatorCore), 1, 1, merkleProof2, other2);

        assertEq(1, creatorCore.balanceOf(creator, 1));
        assertEq(1, creatorCore.balanceOf(other, 1));
        assertEq(2, creatorCore.balanceOf(other2, 1));
        assertEq(5, creatorCore.balanceOf(other3, 1));

        vm.stopPrank();
    }

    function testDelegateV2Minting() public {
        vm.startPrank(creator);
        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;
        uint256 mintFee = example.MINT_FEE_MERKLE();

        bytes32[] memory allowListTuples = new bytes32[](3);
        allowListTuples[0] = keccak256(abi.encodePacked(creator, uint32(0)));
        allowListTuples[1] = keccak256(abi.encodePacked(other2, uint32(1)));
        allowListTuples[2] = keccak256(abi.encodePacked(other3, uint32(2)));

        IERC1155LazyPayableClaim.ClaimParameters memory claimP = IERC1155LazyPayableClaim.ClaimParameters({
            merkleRoot: merkle.getRoot(allowListTuples),
            location: "XXX",
            totalMax: 0,
            walletMax: 0,
            startDate: nowC,
            endDate: later,
            storageProtocol: ILazyPayableClaimCore.StorageProtocol.ARWEAVE,
            cost: 1,
            paymentReceiver: payable(other),
            erc20: zeroAddress,
            signingAddress: address(0)
        });

        example.initializeClaim(address(creatorCore), 1, claimP);

        // Set delegations
        delegationRegistryV2.delegateAll(other, "", true);

        vm.stopPrank();
        vm.startPrank(other2);
        delegationRegistryV2.delegateContract(other, address(example), "", true);

        // Mint with wallet-level delegate
        bytes32[] memory merkleProof1 = merkle.getProof(allowListTuples, uint32(0));
        vm.stopPrank();
        vm.startPrank(other);
        example.mint{value: mintFee + 1}(address(creatorCore), 1, 0, merkleProof1, creator);
        assertEq(creatorCore.balanceOf(creator, 1), 0);
        assertEq(creatorCore.balanceOf(other, 1), 1);

        // Mint with contract-level delegate
        bytes32[] memory merkleProof2 = merkle.getProof(allowListTuples, uint32(1));
        example.mint{value: mintFee + 1}(address(creatorCore), 1, 1, merkleProof2, other2);

        // Fail to mint when no delegate is set
        bytes32[] memory merkleProof3 = merkle.getProof(allowListTuples, uint32(2));
        vm.expectRevert("Invalid delegate");
        example.mint{value: mintFee + 1}(address(creatorCore), 1, 2, merkleProof3, other3);

        vm.stopPrank();
    }

    function testDelegateMinting() public {
        vm.startPrank(creator);
        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;
        uint256 mintFee = example.MINT_FEE_MERKLE();

        bytes32[] memory allowListTuples = new bytes32[](3);
        allowListTuples[0] = keccak256(abi.encodePacked(creator, uint32(0)));
        allowListTuples[1] = keccak256(abi.encodePacked(other2, uint32(1)));
        allowListTuples[2] = keccak256(abi.encodePacked(other3, uint32(2)));

        IERC1155LazyPayableClaim.ClaimParameters memory claimP = IERC1155LazyPayableClaim.ClaimParameters({
            merkleRoot: merkle.getRoot(allowListTuples),
            location: "XXX",
            totalMax: 0,
            walletMax: 0,
            startDate: nowC,
            endDate: later,
            storageProtocol: ILazyPayableClaimCore.StorageProtocol.ARWEAVE,
            cost: 1,
            paymentReceiver: payable(other),
            erc20: zeroAddress,
            signingAddress: address(0)
        });

        example.initializeClaim(address(creatorCore), 1, claimP);

        // Set delegations
        delegationRegistry.delegateForAll(other, true);

        vm.stopPrank();
        vm.startPrank(other2);
        delegationRegistry.delegateForContract(other, address(example), true);

        // Mint with wallet-level delegate
        bytes32[] memory merkleProof1 = merkle.getProof(allowListTuples, uint32(0));
        vm.stopPrank();
        vm.startPrank(other);
        example.mint{value: mintFee + 1}(address(creatorCore), 1, 0, merkleProof1, creator);
        assertEq(creatorCore.balanceOf(creator, 1), 0);
        assertEq(creatorCore.balanceOf(other, 1), 1);

        // Mint with contract-level delegate
        bytes32[] memory merkleProof2 = merkle.getProof(allowListTuples, uint32(1));
        example.mint{value: mintFee + 1}(address(creatorCore), 1, 1, merkleProof2, other2);

        // Fail to mint when no delegate is set
        bytes32[] memory merkleProof3 = merkle.getProof(allowListTuples, uint32(2));
        vm.expectRevert("Invalid delegate");
        example.mint{value: mintFee + 1}(address(creatorCore), 1, 2, merkleProof3, other3);

        vm.stopPrank();
    }

    function testDelegateRegistryAddress() public {
        vm.startPrank(owner);

        ERC1155LazyPayableClaimV2 claim = new ERC1155LazyPayableClaimV2(
            address(creatorCore),
            address(0x00000000000076A84feF008CDAbe6409d2FE638B),
            address(0x00000000000000447e69651d841bD8D104Bed493)
        );
        address onChainAddress = claim.DELEGATION_REGISTRY();
        assertEq(0x00000000000076A84feF008CDAbe6409d2FE638B, onChainAddress);
        address onChainAddressV2 = claim.DELEGATION_REGISTRY_V2();
        assertEq(0x00000000000000447e69651d841bD8D104Bed493, onChainAddressV2);

        vm.stopPrank();
    }

    function testAllowReceipientContract() public {
        vm.startPrank(creator);
        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;
        uint256 mintFee = example.MINT_FEE_MERKLE();

        // Construct a contract receiver
        MockETHReceiver mockETHReceiver = new MockETHReceiver();

        IERC1155LazyPayableClaim.ClaimParameters memory claimP = IERC1155LazyPayableClaim.ClaimParameters({
            merkleRoot: "",
            location: "XXX",
            totalMax: 5,
            walletMax: 3,
            startDate: nowC,
            endDate: later,
            storageProtocol: ILazyPayableClaimCore.StorageProtocol.ARWEAVE,
            cost: 1,
            paymentReceiver: payable(address(mockETHReceiver)),
            erc20: zeroAddress,
            signingAddress: address(0)
        });

        example.initializeClaim(address(creatorCore), 1, claimP);
        // Perform a mint on the claim
        example.mint{value: mintFee + 1}(address(creatorCore), 1, 0, new bytes32[](0), creator);

        vm.stopPrank();
    }

    function testMembershipMint() public {
        vm.startPrank(creator);
        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;

        bytes32[] memory allowListTuples = new bytes32[](2);
        allowListTuples[0] = keccak256(abi.encodePacked(creator, uint32(0)));
        allowListTuples[1] = keccak256(abi.encodePacked(creator, uint32(1)));

        IERC1155LazyPayableClaim.ClaimParameters memory claimP = IERC1155LazyPayableClaim.ClaimParameters({
            merkleRoot: "",
            location: "XXX",
            totalMax: 10,
            walletMax: 10,
            startDate: nowC,
            endDate: later,
            storageProtocol: ILazyPayableClaimCore.StorageProtocol.ARWEAVE,
            cost: 1,
            paymentReceiver: payable(other),
            erc20: zeroAddress,
            signingAddress: address(0)
        });

        example.initializeClaim(address(creatorCore), 1, claimP);

        claimP.merkleRoot = merkle.getRoot(allowListTuples);
        claimP.totalMax = 5;
        claimP.walletMax = 0;
        example.initializeClaim(address(creatorCore), 2, claimP);

        manifoldMembership.setMember(creator, true);
        // Perform a mint on the claim
        example.mintBatch{value: 3}(address(creatorCore), 1, 3, new uint32[](0), new bytes32[][](0), creator);

        bytes32[] memory merkleProof1 = merkle.getProof(allowListTuples, uint32(0));
        bytes32[] memory merkleProof2 = merkle.getProof(allowListTuples, uint32(1));

        uint32[] memory amountsInput = new uint32[](2);
        amountsInput[0] = 0;
        amountsInput[1] = 1;

        bytes32[][] memory proofsInput = new bytes32[][](2);
        proofsInput[0] = merkleProof1;
        proofsInput[1] = merkleProof2;

        example.mintBatch{value: 2}(address(creatorCore), 2, 2, amountsInput, proofsInput, creator);

        vm.stopPrank();
    }

    function testProxyMint() public {
        vm.startPrank(creator);
        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;
        uint256 mintFee = example.MINT_FEE_MERKLE();
        uint256 mintFeeNon = example.MINT_FEE();

        bytes32[] memory allowListTuples = new bytes32[](2);
        allowListTuples[0] = keccak256(abi.encodePacked(creator, uint32(0)));
        allowListTuples[1] = keccak256(abi.encodePacked(creator, uint32(1)));

        IERC1155LazyPayableClaim.ClaimParameters memory claimP = IERC1155LazyPayableClaim.ClaimParameters({
            merkleRoot: "",
            location: "XXX",
            totalMax: 10,
            walletMax: 10,
            startDate: nowC,
            endDate: later,
            storageProtocol: ILazyPayableClaimCore.StorageProtocol.ARWEAVE,
            cost: 1,
            paymentReceiver: payable(creator),
            erc20: zeroAddress,
            signingAddress: address(0)
        });

        example.initializeClaim(address(creatorCore), 1, claimP);

        claimP.merkleRoot = merkle.getRoot(allowListTuples);
        claimP.totalMax = 5;
        claimP.walletMax = 0;
        example.initializeClaim(address(creatorCore), 3, claimP);

        // The sender is a member, but proxy minting will ignore the fact they are a member
        manifoldMembership.setMember(other, true);
        // Perform a mint on the claim
        uint256 balance = other.balance;
        uint256 creatorBalance = creator.balance;

        vm.stopPrank();
        vm.startPrank(other);
        example.mintProxy{value: mintFee * 3 + 3}(
            address(creatorCore), 1, 3, new uint32[](0), new bytes32[][](0), creator
        );

        assertEq(3, creatorCore.balanceOf(creator, 1));

        // Ensure funds taken from message sender
        assertEq(other.balance, balance - mintFee * 3 - 3);

        // Ensure seller got funds
        assertEq(creator.balance, creatorBalance + 3);

        // Mint merkle claims
        bytes32[] memory merkleProof1 = merkle.getProof(allowListTuples, uint32(0));
        bytes32[] memory merkleProof2 = merkle.getProof(allowListTuples, uint32(1));

        uint32[] memory amountsInput = new uint32[](2);
        amountsInput[0] = 0;
        amountsInput[1] = 1;

        bytes32[][] memory proofsInput = new bytes32[][](2);
        proofsInput[0] = merkleProof1;
        proofsInput[1] = merkleProof2;

        vm.expectRevert("Invalid amount");
        example.mintProxy{value: mintFeeNon * 2 + 2}(address(creatorCore), 3, 2, amountsInput, proofsInput, creator);
        example.mintProxy{value: mintFee * 2 + 2}(address(creatorCore), 3, 2, amountsInput, proofsInput, creator);
        assertEq(2, creatorCore.balanceOf(creator, 2));
        vm.stopPrank();
    }

    function testPauseAndUnpause() public {
        // stop new claims from being initialized
        vm.startPrank(owner);
        example.setActive(false);
        vm.stopPrank();

        vm.startPrank(creator);
        uint48 nowC = uint48(block.timestamp);
        uint48 later = nowC + 1000;
        IERC1155LazyPayableClaim.ClaimParameters memory claimP = IERC1155LazyPayableClaim.ClaimParameters({
            merkleRoot: "",
            location: "arweaveHash1",
            totalMax: 5,
            walletMax: 3,
            startDate: nowC,
            endDate: later,
            storageProtocol: ILazyPayableClaimCore.StorageProtocol.ARWEAVE,
            cost: 1,
            paymentReceiver: payable(creator),
            erc20: zeroAddress,
            signingAddress: address(0)
        });
        vm.expectRevert(ILazyPayableClaimV2.Inactive.selector);
        example.initializeClaim(address(creatorCore), 1, claimP);

        // resume new claims
        vm.startPrank(owner);
        example.setActive(true);
        vm.stopPrank();

        vm.startPrank(creator);
        example.initializeClaim(address(creatorCore), 1, claimP);
        vm.stopPrank();

        // can still mint even if claim creations are paused
        vm.startPrank(owner);
        example.setActive(false);
        vm.stopPrank();

        vm.startPrank(other);
        example.mint{value: defaultMintFee + 1}(address(creatorCore), 1, 1, new bytes32[](0), other);
        uint32[] memory amountsInput = new uint32[](1);
        amountsInput[0] = 0;
        bytes32[][] memory proofsInput = new bytes32[][](1);
        proofsInput[0] = new bytes32[](0);
        example.mintBatch{value: defaultMintFee * 2 + 2}(address(creatorCore), 1, 2, amountsInput, proofsInput, other);
        vm.stopPrank();
    }
}
