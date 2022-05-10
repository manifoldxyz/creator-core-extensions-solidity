const truffleAssert = require('truffle-assertions');
const ERC721LazyMint = artifacts.require("ERC721LazyMint");
const ERC721Creator = artifacts.require('@manifoldxyz/creator-core-extensions-solidity/ERC721Creator');
const { MerkleTree } = require('merkletreejs');
const keccak256 = require('keccak256');

contract('LazyMint', function ([...accounts]) {
  const [owner, owner2, creatorCore, marketplace, anyone1, anyone2, anyone3, anyone4, anyone5, anyone6, anyone7] = accounts;
  describe('LazyMint', function () {
    let creator, lazyMint;
    let merkleTree;
    beforeEach(async function () {
      creator = await ERC721Creator.new("Test", "TEST", {from:owner});
      lazyMint = await ERC721LazyMint.new({from:owner});

      await creator.registerExtension(lazyMint.address, "http://", {from:owner});

      const merkleElements = [owner, owner2, anyone1, anyone2];
      merkleTree = new MerkleTree(merkleElements, keccak256, { hashLeaves: true, sortPairs: true });
    });


    it('access test', async function () {
      await truffleAssert.reverts(lazyMint.initializeListing(creator.address, "0x1", "0x2", {from:anyone1})); // Must be admin
    });

    it('basic test', async function() {
      // Test initializing a new listing

      // Should fail to initialize if non-admin wallet is used
      truffleAssert.reverts(lazyMint.initializeListing(creator.address, merkleTree.getHexRoot(), 'https://', {from:owner2}));

      await lazyMint.initializeListing(creator.address, merkleTree.getHexRoot(), 'https://', {from:owner});
      // Trying to initialize a second time should revert
      truffleAssert.reverts(lazyMint.initializeListing(creator.address, merkleTree.getHexRoot(), 'https://', {from:owner}));
    
      // Listing should have expected info
      const listing = await lazyMint.getListing(creator.address, {from:owner});
      assert.equal(listing.merkleRoot, merkleTree.getHexRoot());
      assert.equal(listing.uri, 'https://');
      assert.equal(listing.initialized, true);

      // Test minting

      // Mint a token to random wallet
      const merkleLeaf = keccak256(anyone1);
      const merkleProof = merkleTree.getHexProof(merkleLeaf);
      await lazyMint.mint(creator.address, merkleProof, {from:anyone1});

      // Minting again to the same wallet should revert
      truffleAssert.reverts(lazyMint.mint(creator.address, merkleProof, {from:anyone1}));

      // Minting with an invalid proof should revert
      truffleAssert.reverts(lazyMint.mint(creator.address, merkleProof, {from:anyone2}));

      const merkleLeaf2 = keccak256(anyone2);
      const merkleProof2 = merkleTree.getHexProof(merkleLeaf2);
      await lazyMint.mint(creator.address, merkleProof2, {from:anyone2});

      // Now ensure that the creator contract state is what we expect
      let balance = await creator.balanceOf(anyone1, {from:anyone3});
      assert.equal(1,balance);
      let balance2 = await creator.balanceOf(anyone2, {from:anyone3});
      assert.equal(1,balance2);
      let tokenURI = await creator.tokenURI(1);
      assert.equal('https://', tokenURI);
      let tokenOwner = await creator.ownerOf(1);
      assert.equal(anyone1, tokenOwner);
    });
  });
});