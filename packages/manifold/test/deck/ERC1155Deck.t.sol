// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../contracts/deckClaims/IERC1155Deck.sol";
import "../../contracts/deckClaims/ERC1155Deck.sol";
import "../../contracts/deckClaims/IDeck.sol";
import "../../contracts/deckClaims/Deck.sol";

import "@manifoldxyz/creator-core-solidity/contracts/ERC1155Creator.sol";
import "../mocks/Mock.sol";

contract ERC1155DeckTest is Test {
  ERC1155Deck public example;
  ERC1155Creator public creatorCore1;
  ERC1155Creator public creatorCore2;

  address public creator = 0xc78Dc443c126af6E4f6Ed540c1e740C1b5be09cd;
  address public owner = 0x6140F00e4Ff3936702E68744f2b5978885464cbB;
  address public signingAddress = 0xc78dC443c126Af6E4f6eD540C1E740c1B5be09CE;
  address public other = 0x5174cD462b60c536eb51D4ceC1D561D3Ea31004F;
  address public other2 = 0x80AAC46bbd3C2FcE33681541a52CacBEd14bF425;

  address public zeroAddress = address(0);

  uint256 internal constant MAX_UINT_8 = 0xff;
  uint256 internal constant MAX_UINT_56 = 0xffffffffffffff;

  function setUp() public {
    vm.startPrank(creator);
    creatorCore1 = new ERC1155Creator("Token1", "NFT1");
    creatorCore2 = new ERC1155Creator("Token2", "NFT2");
    vm.stopPrank();

    vm.startPrank(owner);
    example = new ERC1155Deck(owner);
    example.setSigner(address(signingAddress));
    vm.stopPrank();

    vm.startPrank(creator);
    creatorCore1.registerExtension(address(example), "override");
    creatorCore2.registerExtension(address(example), "override");
    vm.stopPrank();

    vm.deal(creator, 10 ether);
    vm.deal(other, 10 ether);
    vm.deal(other2, 10 ether);
  }

  function testAccess() public {
    vm.startPrank(other);
    // Must be admin
    vm.expectRevert();
    example.withdraw(payable(other), 20);
    vm.expectRevert("AdminControl: Must be owner or admin");
    example.setSigner(other);

    IERC1155Deck.ClaimParameters memory claimP = IERC1155Deck.ClaimParameters({
      storageProtocol: IDeck.StorageProtocol.IPFS,
      tokenVariations: 5,
      location: "ipfsHash1"
    });
    // Must be admin
    vm.expectRevert();
    example.initializeClaim(address(creatorCore1), 1, claimP);
    // Succeeds because is admin
    vm.stopPrank();
    vm.startPrank(creator);
    example.initializeClaim(address(creatorCore1), 1, claimP);
    // Try as a different non admin
    vm.stopPrank();
    vm.startPrank(other2);
    vm.expectRevert();
    example.initializeClaim(address(creatorCore1), 2, claimP);

    vm.stopPrank();
  }

  function testInitializeClaimSanitization() public {
    vm.startPrank(creator);

    IERC1155Deck.ClaimParameters memory claimP = IERC1155Deck.ClaimParameters({
      storageProtocol: IDeck.StorageProtocol.INVALID,
      tokenVariations: 5,
      location: "arweaveHash1"
    });

    vm.expectRevert(IDeck.InvalidStorageProtocol.selector);
    example.initializeClaim(address(creatorCore1), 1, claimP);

    // Reset to valid storage protocol
    claimP.storageProtocol = IDeck.StorageProtocol.ARWEAVE;

    // Invalid instanceId = 0
    vm.expectRevert(IDeck.InvalidInstance.selector);
    example.initializeClaim(address(creatorCore1), 0, claimP);

    // Invalid instanceId > MAX_UINT_56
    vm.expectRevert(IDeck.InvalidInstance.selector);
    example.initializeClaim(address(creatorCore1), MAX_UINT_56 + 1, claimP);

    // Successful initialization
    example.initializeClaim(address(creatorCore1), 1, claimP);

    // Cannot reinitialize same instanceId
    vm.expectRevert(IDeck.ClaimAlreadyInitialized.selector);
    example.initializeClaim(address(creatorCore1), 1, claimP);

    vm.stopPrank();
  }

  function testInitializeClaimWithDifferentProtocols() public {
    vm.startPrank(creator);

    // Test ARWEAVE protocol
    IERC1155Deck.ClaimParameters memory claimP = IERC1155Deck.ClaimParameters({
      storageProtocol: IDeck.StorageProtocol.ARWEAVE,
      tokenVariations: 3,
      location: "arweaveHash1"
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);

    IERC1155Deck.Claim memory claim = example.getClaim(address(creatorCore1), 1);
    assertEq(uint(claim.storageProtocol), uint(IDeck.StorageProtocol.ARWEAVE));
    assertEq(claim.location, "arweaveHash1");
    assertEq(claim.tokenVariations, 3);
    assertEq(claim.total, 0);
    assertEq(claim.startingTokenId, 1);

    // Test IPFS protocol
    claimP.storageProtocol = IDeck.StorageProtocol.IPFS;
    claimP.location = "ipfsHash1";
    claimP.tokenVariations = 5;
    example.initializeClaim(address(creatorCore1), 2, claimP);

    claim = example.getClaim(address(creatorCore1), 2);
    assertEq(uint(claim.storageProtocol), uint(IDeck.StorageProtocol.IPFS));
    assertEq(claim.location, "ipfsHash1");
    assertEq(claim.tokenVariations, 5);
    assertEq(claim.total, 0);
    assertEq(claim.startingTokenId, 4); // after first claim's 3 tokens

    // Test NONE protocol
    claimP.storageProtocol = IDeck.StorageProtocol.NONE;
    claimP.location = "";
    example.initializeClaim(address(creatorCore1), 3, claimP);

    claim = example.getClaim(address(creatorCore1), 3);
    assertEq(uint(claim.storageProtocol), uint(IDeck.StorageProtocol.NONE));

    vm.stopPrank();
  }

  function test_InitializeClaimWithMaxVariations() public {
    vm.startPrank(creator);

    IERC1155Deck.ClaimParameters memory claimP = IERC1155Deck.ClaimParameters({
      storageProtocol: IDeck.StorageProtocol.ARWEAVE,
      tokenVariations: uint8(MAX_UINT_8),
      location: "arweaveHash1"
    });

    example.initializeClaim(address(creatorCore1), 1, claimP);

    IERC1155Deck.Claim memory claim = example.getClaim(address(creatorCore1), 1);
    assertEq(claim.tokenVariations, uint8(MAX_UINT_8));

    vm.stopPrank();
  }

  function test_UpdateClaim() public {
    vm.startPrank(creator);

    IERC1155Deck.ClaimParameters memory claimP = IERC1155Deck.ClaimParameters({
      storageProtocol: IDeck.StorageProtocol.ARWEAVE,
      tokenVariations: 5,
      location: "arweaveHash1"
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);

    IERC1155Deck.UpdateClaimParameters memory claimU = IERC1155Deck.UpdateClaimParameters({
      storageProtocol: IDeck.StorageProtocol.IPFS,
      location: "ipfsHashUpdated"
    });

    example.updateClaim(address(creatorCore1), 1, claimU);

    IERC1155Deck.Claim memory claim = example.getClaim(address(creatorCore1), 1);
    assertEq(uint(claim.storageProtocol), uint(IDeck.StorageProtocol.IPFS));
    assertEq(claim.location, "ipfsHashUpdated");
    // tokenVariations should remain unchanged
    assertEq(claim.tokenVariations, 5);

    vm.stopPrank();
  }

  function test_UpdateClaimSanitization() public {
    vm.startPrank(creator);

    IERC1155Deck.ClaimParameters memory claimP = IERC1155Deck.ClaimParameters({
      storageProtocol: IDeck.StorageProtocol.ARWEAVE,
      tokenVariations: 5,
      location: "arweaveHash1"
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);

    IERC1155Deck.UpdateClaimParameters memory claimU = IERC1155Deck.UpdateClaimParameters({
      storageProtocol: IDeck.StorageProtocol.INVALID,
      location: "newHash"
    });

    vm.expectRevert(IDeck.InvalidStorageProtocol.selector);
    example.updateClaim(address(creatorCore1), 1, claimU);

    // Cannot update non-existent claim
    claimU.storageProtocol = IDeck.StorageProtocol.ARWEAVE;
    vm.expectRevert(IDeck.ClaimNotInitialized.selector);
    example.updateClaim(address(creatorCore1), 99, claimU);

    // instanceId = 0 also fails with ClaimNotInitialized (checked before InvalidInstance in contract)
    vm.expectRevert(IDeck.ClaimNotInitialized.selector);
    example.updateClaim(address(creatorCore1), 0, claimU);

    vm.stopPrank();
  }

  function test_RevertWhen_UpdateClaimNotClaimOwner() public {
    vm.startPrank(creator);

    IERC1155Deck.ClaimParameters memory claimP = IERC1155Deck.ClaimParameters({
      storageProtocol: IDeck.StorageProtocol.IPFS,
      tokenVariations: 5,
      location: "ipfsHash1"
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);
    vm.stopPrank();

    vm.startPrank(other);
    IERC1155Deck.UpdateClaimParameters memory claimU = IERC1155Deck.UpdateClaimParameters({
      storageProtocol: IDeck.StorageProtocol.ARWEAVE,
      location: "newHash"
    });
    vm.expectRevert();
    example.updateClaim(address(creatorCore1), 1, claimU);
    vm.stopPrank();
  }

  function testInvalidSigner() public {
    vm.startPrank(creator);

    IERC1155Deck.ClaimParameters memory claimP = IERC1155Deck.ClaimParameters({
      storageProtocol: IDeck.StorageProtocol.ARWEAVE,
      tokenVariations: 5,
      location: "arweaveHash1"
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);
    vm.stopPrank();

    vm.startPrank(other);
    IDeck.ClaimMint[] memory mints = new IDeck.ClaimMint[](1);
    IDeck.VariationMint[] memory variationMints = new IDeck.VariationMint[](1);
    variationMints[0] = IDeck.VariationMint({ variationIndex: 1, amount: 1, recipient: other });
    mints[0] = IDeck.ClaimMint({
      creatorContractAddress: address(creatorCore1),
      instanceId: 1,
      variationMints: variationMints
    });

    vm.expectRevert(IDeck.InvalidSignature.selector);
    example.deliverMints(mints);
    vm.stopPrank();
  }

  function testDeliverMints() public {
    vm.startPrank(creator);

    IERC1155Deck.ClaimParameters memory claimP = IERC1155Deck.ClaimParameters({
      storageProtocol: IDeck.StorageProtocol.ARWEAVE,
      tokenVariations: 5,
      location: "arweaveHash1"
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);
    vm.stopPrank();

    vm.startPrank(signingAddress);
    IDeck.ClaimMint[] memory mints = new IDeck.ClaimMint[](1);
    IDeck.VariationMint[] memory variationMints = new IDeck.VariationMint[](2);
    variationMints[0] = IDeck.VariationMint({ variationIndex: 1, amount: 5, recipient: other });
    variationMints[1] = IDeck.VariationMint({ variationIndex: 3, amount: 10, recipient: other2 });
    mints[0] = IDeck.ClaimMint({
      creatorContractAddress: address(creatorCore1),
      instanceId: 1,
      variationMints: variationMints
    });

    example.deliverMints(mints);

    // Check balances
    assertEq(creatorCore1.balanceOf(other, 1), 5);
    assertEq(creatorCore1.balanceOf(other2, 3), 10);
    vm.stopPrank();
  }

  function testDeliverMintsMultipleClaims() public {
    vm.startPrank(creator);

    IERC1155Deck.ClaimParameters memory claimP = IERC1155Deck.ClaimParameters({
      storageProtocol: IDeck.StorageProtocol.ARWEAVE,
      tokenVariations: 5,
      location: "arweaveHash1"
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);

    claimP.location = "arweaveHash2";
    claimP.tokenVariations = 3;
    example.initializeClaim(address(creatorCore1), 2, claimP);
    vm.stopPrank();

    vm.startPrank(signingAddress);
    IDeck.ClaimMint[] memory mints = new IDeck.ClaimMint[](2);

    IDeck.VariationMint[] memory variationMints1 = new IDeck.VariationMint[](1);
    variationMints1[0] = IDeck.VariationMint({ variationIndex: 1, amount: 2, recipient: other });
    mints[0] = IDeck.ClaimMint({
      creatorContractAddress: address(creatorCore1),
      instanceId: 1,
      variationMints: variationMints1
    });

    IDeck.VariationMint[] memory variationMints2 = new IDeck.VariationMint[](1);
    variationMints2[0] = IDeck.VariationMint({ variationIndex: 2, amount: 3, recipient: other2 });
    mints[1] = IDeck.ClaimMint({
      creatorContractAddress: address(creatorCore1),
      instanceId: 2,
      variationMints: variationMints2
    });

    example.deliverMints(mints);

    // Check balances - first claim starts at tokenId 1, second at tokenId 6
    assertEq(creatorCore1.balanceOf(other, 1), 2);
    assertEq(creatorCore1.balanceOf(other2, 7), 3); // tokenId 6 + variationIndex 2 - 1 = 7
    vm.stopPrank();
  }

  function testDeliverMintsInvalidVariationIndex() public {
    vm.startPrank(creator);

    IERC1155Deck.ClaimParameters memory claimP = IERC1155Deck.ClaimParameters({
      storageProtocol: IDeck.StorageProtocol.ARWEAVE,
      tokenVariations: 5,
      location: "arweaveHash1"
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);
    vm.stopPrank();

    vm.startPrank(signingAddress);
    IDeck.ClaimMint[] memory mints = new IDeck.ClaimMint[](1);
    IDeck.VariationMint[] memory variationMints = new IDeck.VariationMint[](1);

    // variationIndex 0 is invalid (must be >= 1)
    variationMints[0] = IDeck.VariationMint({ variationIndex: 0, amount: 1, recipient: other });
    mints[0] = IDeck.ClaimMint({
      creatorContractAddress: address(creatorCore1),
      instanceId: 1,
      variationMints: variationMints
    });

    vm.expectRevert(IDeck.InvalidVariationIndex.selector);
    example.deliverMints(mints);

    // variationIndex 6 is invalid (tokenVariations is 5)
    variationMints[0] = IDeck.VariationMint({ variationIndex: 6, amount: 1, recipient: other });
    mints[0] = IDeck.ClaimMint({
      creatorContractAddress: address(creatorCore1),
      instanceId: 1,
      variationMints: variationMints
    });

    vm.expectRevert(IDeck.InvalidVariationIndex.selector);
    example.deliverMints(mints);

    vm.stopPrank();
  }

  function testTokenURI() public {
    vm.startPrank(creator);

    IERC1155Deck.ClaimParameters memory claimP = IERC1155Deck.ClaimParameters({
      storageProtocol: IDeck.StorageProtocol.ARWEAVE,
      tokenVariations: 5,
      location: "arweaveHash1"
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);

    // Check URIs for all variations
    assertEq("https://arweave.net/arweaveHash1/1", creatorCore1.uri(1));
    assertEq("https://arweave.net/arweaveHash1/2", creatorCore1.uri(2));
    assertEq("https://arweave.net/arweaveHash1/3", creatorCore1.uri(3));
    assertEq("https://arweave.net/arweaveHash1/4", creatorCore1.uri(4));
    assertEq("https://arweave.net/arweaveHash1/5", creatorCore1.uri(5));

    // Create second claim with different location
    claimP.tokenVariations = 3;
    claimP.location = "arweaveHash2";
    example.initializeClaim(address(creatorCore1), 2, claimP);

    // Second claim starts at tokenId 6
    assertEq("https://arweave.net/arweaveHash2/1", creatorCore1.uri(6));
    assertEq("https://arweave.net/arweaveHash2/2", creatorCore1.uri(7));
    assertEq("https://arweave.net/arweaveHash2/3", creatorCore1.uri(8));

    vm.stopPrank();
  }

  function testTokenURIWithIPFS() public {
    vm.startPrank(creator);

    IERC1155Deck.ClaimParameters memory claimP = IERC1155Deck.ClaimParameters({
      storageProtocol: IDeck.StorageProtocol.IPFS,
      tokenVariations: 3,
      location: "QmTestHash"
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);

    assertEq("ipfs://QmTestHash/1", creatorCore1.uri(1));
    assertEq("ipfs://QmTestHash/2", creatorCore1.uri(2));
    assertEq("ipfs://QmTestHash/3", creatorCore1.uri(3));

    vm.stopPrank();
  }

  function testTokenURIWithNone() public {
    vm.startPrank(creator);

    IERC1155Deck.ClaimParameters memory claimP = IERC1155Deck.ClaimParameters({
      storageProtocol: IDeck.StorageProtocol.NONE,
      tokenVariations: 2,
      location: "customLocation"
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);

    // NONE storage protocol should have no prefix
    assertEq("customLocation/1", creatorCore1.uri(1));
    assertEq("customLocation/2", creatorCore1.uri(2));

    vm.stopPrank();
  }

  function testUpdateTokenURI() public {
    vm.startPrank(creator);

    IERC1155Deck.ClaimParameters memory claimP = IERC1155Deck.ClaimParameters({
      storageProtocol: IDeck.StorageProtocol.ARWEAVE,
      tokenVariations: 5,
      location: "arweaveHash1"
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);

    // Original URIs
    assertEq("https://arweave.net/arweaveHash1/1", creatorCore1.uri(1));
    assertEq("https://arweave.net/arweaveHash1/2", creatorCore1.uri(2));

    // Update token URI
    example.updateTokenURIParams(address(creatorCore1), 1, IDeck.StorageProtocol.ARWEAVE, "arweaveHashNEW");

    assertEq("https://arweave.net/arweaveHashNEW/1", creatorCore1.uri(1));
    assertEq("https://arweave.net/arweaveHashNEW/2", creatorCore1.uri(2));

    // Update to different storage protocol
    example.updateTokenURIParams(address(creatorCore1), 1, IDeck.StorageProtocol.IPFS, "QmNewHash");

    assertEq("ipfs://QmNewHash/1", creatorCore1.uri(1));
    assertEq("ipfs://QmNewHash/2", creatorCore1.uri(2));

    vm.stopPrank();
  }

  function test_RevertWhen_UpdateTokenURIInvalidProtocol() public {
    vm.startPrank(creator);

    IERC1155Deck.ClaimParameters memory claimP = IERC1155Deck.ClaimParameters({
      storageProtocol: IDeck.StorageProtocol.ARWEAVE,
      tokenVariations: 5,
      location: "arweaveHash1"
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);

    vm.expectRevert(IDeck.InvalidStorageProtocol.selector);
    example.updateTokenURIParams(address(creatorCore1), 1, IDeck.StorageProtocol.INVALID, "newHash");

    vm.stopPrank();
  }

  function test_RevertWhen_UpdateTokenURINotAdmin() public {
    vm.startPrank(creator);

    IERC1155Deck.ClaimParameters memory claimP = IERC1155Deck.ClaimParameters({
      storageProtocol: IDeck.StorageProtocol.ARWEAVE,
      tokenVariations: 5,
      location: "arweaveHash1"
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);
    vm.stopPrank();

    vm.startPrank(other);
    vm.expectRevert();
    example.updateTokenURIParams(address(creatorCore1), 1, IDeck.StorageProtocol.IPFS, "newHash");
    vm.stopPrank();
  }

  function testGetClaimForToken() public {
    vm.startPrank(creator);

    IERC1155Deck.ClaimParameters memory claimP = IERC1155Deck.ClaimParameters({
      storageProtocol: IDeck.StorageProtocol.ARWEAVE,
      tokenVariations: 3,
      location: "arweaveHash1"
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);

    claimP.location = "arweaveHash2";
    claimP.tokenVariations = 2;
    example.initializeClaim(address(creatorCore1), 2, claimP);

    // Get claim for tokens from first claim
    (uint256 instanceId1, IERC1155Deck.Claim memory claim1) = example.getClaimForToken(address(creatorCore1), 1);
    assertEq(instanceId1, 1);
    assertEq(claim1.location, "arweaveHash1");

    (uint256 instanceId2, IERC1155Deck.Claim memory claim2) = example.getClaimForToken(address(creatorCore1), 3);
    assertEq(instanceId2, 1);
    assertEq(claim2.location, "arweaveHash1");

    // Get claim for tokens from second claim
    (uint256 instanceId3, IERC1155Deck.Claim memory claim3) = example.getClaimForToken(address(creatorCore1), 4);
    assertEq(instanceId3, 2);
    assertEq(claim3.location, "arweaveHash2");

    vm.stopPrank();
  }

  function test_RevertWhen_InitializeClaimOnDeprecated() public {
    vm.startPrank(owner);
    example.deprecate(true);
    vm.stopPrank();

    vm.startPrank(creator);
    IERC1155Deck.ClaimParameters memory claimP = IERC1155Deck.ClaimParameters({
      storageProtocol: IDeck.StorageProtocol.IPFS,
      tokenVariations: 5,
      location: "ipfsHash1"
    });
    vm.expectRevert(IDeck.ContractDeprecated.selector);
    example.initializeClaim(address(creatorCore1), 1, claimP);
    vm.stopPrank();

    vm.startPrank(owner);
    example.deprecate(false);
    vm.stopPrank();

    vm.startPrank(creator);
    // Can initialize claim after deprecation removal
    example.initializeClaim(address(creatorCore1), 1, claimP);
    vm.stopPrank();
  }

  function test_RevertWhen_UpdateClaimOnDeprecated() public {
    vm.startPrank(creator);
    IERC1155Deck.ClaimParameters memory claimP = IERC1155Deck.ClaimParameters({
      storageProtocol: IDeck.StorageProtocol.ARWEAVE,
      tokenVariations: 5,
      location: "arweaveHash1"
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);
    vm.stopPrank();

    vm.startPrank(owner);
    example.deprecate(true);
    vm.stopPrank();

    vm.startPrank(creator);
    IERC1155Deck.UpdateClaimParameters memory claimU = IERC1155Deck.UpdateClaimParameters({
      storageProtocol: IDeck.StorageProtocol.ARWEAVE,
      location: "newHash"
    });
    vm.expectRevert(IDeck.ContractDeprecated.selector);
    example.updateClaim(address(creatorCore1), 1, claimU);
    vm.stopPrank();

    vm.startPrank(owner);
    example.deprecate(false);
    vm.stopPrank();

    vm.startPrank(creator);
    // Can update claim after deprecation removal
    example.updateClaim(address(creatorCore1), 1, claimU);
    vm.stopPrank();
  }

  function test_Deprecate() public {
    assertEq(example.deprecated(), false);

    vm.startPrank(owner);
    example.deprecate(true);
    assertEq(example.deprecated(), true);
    example.deprecate(false);
    assertEq(example.deprecated(), false);
    vm.stopPrank();

    // Cannot call deprecate if not an admin
    vm.startPrank(other);
    vm.expectRevert(bytes("AdminControl: Must be owner or admin"));
    example.deprecate(true);
    vm.stopPrank();

    vm.startPrank(owner);
    example.approveAdmin(other);
    vm.stopPrank();

    vm.startPrank(other);
    example.deprecate(true);
    assertEq(example.deprecated(), true);
    vm.stopPrank();

    vm.startPrank(owner);
    example.revokeAdmin(other);
    vm.stopPrank();

    vm.startPrank(other);
    vm.expectRevert(bytes("AdminControl: Must be owner or admin"));
    example.deprecate(false);
    assertEq(example.deprecated(), true);
    vm.stopPrank();
  }

  function testWithdraw() public {
    // Send some ETH to the contract
    vm.deal(address(example), 1 ether);

    uint256 ownerBalanceBefore = owner.balance;

    vm.startPrank(owner);
    example.withdraw(payable(owner), 0.5 ether);
    vm.stopPrank();

    assertEq(owner.balance, ownerBalanceBefore + 0.5 ether);
    assertEq(address(example).balance, 0.5 ether);
  }

  function testSupportsInterface() public {
    // IERC1155Deck
    assertTrue(example.supportsInterface(type(IERC1155Deck).interfaceId));
    // IDeck
    assertTrue(example.supportsInterface(type(IDeck).interfaceId));
    // ICreatorExtensionTokenURI
    assertTrue(example.supportsInterface(type(ICreatorExtensionTokenURI).interfaceId));
    // IERC165
    assertTrue(example.supportsInterface(type(IERC165).interfaceId));
  }

  function testSetSigner() public {
    vm.startPrank(owner);
    example.setSigner(other);
    vm.stopPrank();

    // Now other should be the signer
    vm.startPrank(creator);
    IERC1155Deck.ClaimParameters memory claimP = IERC1155Deck.ClaimParameters({
      storageProtocol: IDeck.StorageProtocol.ARWEAVE,
      tokenVariations: 5,
      location: "arweaveHash1"
    });
    example.initializeClaim(address(creatorCore1), 1, claimP);
    vm.stopPrank();

    // Old signer should fail
    vm.startPrank(signingAddress);
    IDeck.ClaimMint[] memory mints = new IDeck.ClaimMint[](1);
    IDeck.VariationMint[] memory variationMints = new IDeck.VariationMint[](1);
    variationMints[0] = IDeck.VariationMint({ variationIndex: 1, amount: 1, recipient: other });
    mints[0] = IDeck.ClaimMint({
      creatorContractAddress: address(creatorCore1),
      instanceId: 1,
      variationMints: variationMints
    });

    vm.expectRevert(IDeck.InvalidSignature.selector);
    example.deliverMints(mints);
    vm.stopPrank();

    // New signer should succeed
    vm.startPrank(other);
    example.deliverMints(mints);
    assertEq(creatorCore1.balanceOf(other, 1), 1);
    vm.stopPrank();
  }

  function testMultipleCreatorContracts() public {
    vm.startPrank(creator);

    IERC1155Deck.ClaimParameters memory claimP = IERC1155Deck.ClaimParameters({
      storageProtocol: IDeck.StorageProtocol.ARWEAVE,
      tokenVariations: 3,
      location: "hash1"
    });

    // Initialize on both creator contracts with same instanceId
    example.initializeClaim(address(creatorCore1), 1, claimP);
    claimP.location = "hash2";
    example.initializeClaim(address(creatorCore2), 1, claimP);

    // Each should have their own claims
    IERC1155Deck.Claim memory claim1 = example.getClaim(address(creatorCore1), 1);
    IERC1155Deck.Claim memory claim2 = example.getClaim(address(creatorCore2), 1);

    assertEq(claim1.location, "hash1");
    assertEq(claim2.location, "hash2");

    vm.stopPrank();
  }
}
