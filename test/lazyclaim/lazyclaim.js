const truffleAssert = require('truffle-assertions');
const ERC721LazyClaim = artifacts.require("ERC721LazyClaim");
const ERC721Creator = artifacts.require('@manifoldxyz/creator-core-extensions-solidity/ERC721Creator');
const { MerkleTree } = require('merkletreejs');
const keccak256 = require('keccak256');

contract('LazyClaim', function ([...accounts]) {
  const [owner, owner2, creatorCore, marketplace, anyone1, anyone2, anyone3, anyone4, anyone5, anyone6, anyone7] = accounts;
  describe('LazyClaim', function () {
    let creator, lazyClaim;
    let merkleTree;
    beforeEach(async function () {
      creator = await ERC721Creator.new("Test", "TEST", {from:owner});
      lazyClaim = await ERC721LazyClaim.new({from:owner});
      
      // Must register with empty prefix in order to set per-token uri's
      await creator.registerExtension(lazyClaim.address, {from:owner});

      const merkleElements = [owner, owner2, anyone1, anyone2];
      merkleTree = new MerkleTree(merkleElements, keccak256, { hashLeaves: true, sortPairs: true });
    });


    it('access test', async function () {
      let now = Math.floor(Date.now() / 1000) - 30; // seconds since unix epoch
      let later = now + 1000;

      await truffleAssert.reverts(lazyClaim.initializeClaim(
        creator.address,
        "0x1",
        "0x2",
        10,
        1,
        now,
        later,
        {from:anyone1}
      )); // Must be admin
    });

    it('basic test', async function() {
      // Test initializing a new claim
      let now = Math.floor(Date.now() / 1000) - 30; // seconds since unix epoch
      let later = now + 1000;

      // Should fail to initialize if non-admin wallet is used
      truffleAssert.reverts(lazyClaim.initializeClaim(
        creator.address,
        merkleTree.getHexRoot(),
        'zero.com',
        3,
        1,
        now,
        later,
        {from:owner2}
      ));

      await lazyClaim.initializeClaim(
        creator.address,
        merkleTree.getHexRoot(),
        'one.com',
        2,
        1,
        now,
        later,
        {from:owner}
      );

      // Overwrite the claim with one parameter changed
      await lazyClaim.overwriteClaim(
        creator.address,
        0, // the index of the claim we want to edit
        merkleTree.getHexRoot(),
        'one.com',
        3,
        1,
        now,
        later,
        {from:owner}
      );

      // Initialize a second claim - with optional parameters disabled
      await lazyClaim.initializeClaim(
        creator.address,
        "0x0",
        'two.com',
        0,
        0,
        0,
        0,
        {from:owner}
      );
    
      // Claim should have expected info
      const count = await lazyClaim.getClaimCount(creator.address, {from:owner});
      assert.equal(count, 2);
      const claim = await lazyClaim.getClaim(creator.address, 0, {from:owner});
      assert.equal(claim.merkleRoot, merkleTree.getHexRoot());
      assert.equal(claim.uri, 'one.com');
      assert.equal(claim.totalMax, 3);
      assert.equal(claim.walletMax, 1);
      assert.equal(claim.startDate, now);
      assert.equal(claim.endDate, later);

      // Test minting

      // Mint a token to random wallet
      const merkleLeaf = keccak256(anyone1);
      const merkleProof = merkleTree.getHexProof(merkleLeaf);
      await lazyClaim.mint(creator.address, 0, merkleProof, {from:anyone1});

      // Minting again to the same wallet should revert
      // truffleAssert.reverts(lazyMint.mint(creator.address, 0, merkleProof, {from:anyone1}));

      // Minting with an invalid proof should revert
      truffleAssert.reverts(lazyClaim.mint(creator.address, 0, merkleProof, {from:anyone2}));

      const merkleLeaf2 = keccak256(anyone2);
      const merkleProof2 = merkleTree.getHexProof(merkleLeaf2);
      await lazyClaim.mint(creator.address, 0, merkleProof2, {from:anyone2});

      // Now ensure that the creator contract state is what we expect after mints
      let balance = await creator.balanceOf(anyone1, {from:anyone3});
      assert.equal(1,balance);
      let balance2 = await creator.balanceOf(anyone2, {from:anyone3});
      assert.equal(1,balance2);
      let tokenURI = await creator.tokenURI(1);
      assert.equal('one.com', tokenURI);
      let tokenOwner = await creator.ownerOf(1);
      assert.equal(anyone1, tokenOwner);

      // Additionally test that tokenURIs are dynamic

      // Test wallet and total maximums
      await lazyClaim.setURI(creator.address, 0, "three.com", {from:owner});
      let newTokenURI = await creator.tokenURI(1);
      assert.equal('three.com', newTokenURI);

      // Try to mint again with wallet limit of 1, should revert
      truffleAssert.reverts(lazyClaim.mint(creator.address, 0, merkleProof, {from:anyone1}));
      // Increase wallet max to 3
      await lazyClaim.setWalletMax(creator.address, 0, 3, {from:owner});
      // Try to mint again, should succeed
      await lazyClaim.mint(creator.address, 0, merkleProof, {from:anyone1});
      // Try to mint again with total limit of 3, should revert
      truffleAssert.reverts(lazyClaim.mint(creator.address, 0, merkleProof, {from:anyone1}));
      // Increase total max to 4
      await lazyClaim.setTotalMax(creator.address, 0, 4, {from:owner});
      // Try to mint again, should succeed
      await lazyClaim.mint(creator.address, 0, merkleProof, {from:anyone1});

      // Optional parameters - using claim 2
      const garbageMerkleProof = merkleTree.getHexProof(keccak256(anyone3));
      await lazyClaim.mint(creator.address, 1, garbageMerkleProof, {from:anyone1});
      await lazyClaim.mint(creator.address, 1, garbageMerkleProof, {from:anyone1});
      await lazyClaim.mint(creator.address, 1, garbageMerkleProof, {from:anyone2});
    });
  });
});