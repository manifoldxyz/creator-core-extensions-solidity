const helper = require("../helpers/truffleTestHelper");
const truffleAssert = require('truffle-assertions');
const ERC721Creator = artifacts.require('MockTestERC721Creator');
const LazyWhitelist = artifacts.require("ERC721LazyMintWhitelist");
const LazyWhitelistTemplate = artifacts.require("ERC721LazyMintWhitelistTemplate");
const LazyWhitelistImplementation = artifacts.require("ERC721LazyMintWhitelistImplementation");
const { MerkleTree } = require('merkletreejs');
const keccak256 = require('keccak256');

contract('LazyWhitelist', function ([creator, ...accounts]) {
  const name = 'Token';
  const symbol = 'NFT';
  const minter = creator;
  const [
    owner,
    newOwner,
    another,
    anyone,
  ] = accounts;

  describe('LazyWhitelist', function() {
    var creator;
    var lazywhitelist;
    var lazywhitelistImplementation;
    var lazywhitelistTemplate;
    beforeEach(async function () {
      creator = await ERC721Creator.new(name, symbol, {from:owner});
      lazywhitelist = await LazyWhitelist.new(creator.address, "https://lazywhitelist/", {from:owner});
      await creator.registerExtension(lazywhitelist.address, "override", {from:owner})
      lazywhitelistImplementation = await LazyWhitelistImplementation.new();
      lazywhitelistTemplate = await LazyWhitelistTemplate.new(lazywhitelistImplementation.address, creator.address, "https://lazywhitelist/template", {from:owner});
      await creator.registerExtension(lazywhitelistTemplate.address, "override", {from:owner})
      lazywhitelistTemplate = await LazyWhitelist.at(lazywhitelistTemplate.address);
    });

    it('access test', async function () {
      await truffleAssert.reverts(lazywhitelist.premint([anyone], {from:anyone}), "AdminControl: Must be owner or admin");
      await truffleAssert.reverts(lazywhitelist.setTokenURIPrefix("", {from:anyone}), "AdminControl: Must be owner or admin");
      await truffleAssert.reverts(lazywhitelist.setAllowList("0x000000000000000000000000000000000000000000000000000000000000abcd", {from:anyone}), "AdminControl: Must be owner or admin");
      await truffleAssert.reverts(lazywhitelist.withdraw(anyone, 0, {from:anyone}), "AdminControl: Must be owner or admin");
    });

    /**
     * Should be able to premint their tokens. In the original case
     * this was built for they wanted to premint 25 to self, 25 to another address
     * and then 20 to self again
     */
    it('premint', async function () {

      // Mint 25 things
      var receivers = [];
      for (let i = 0; i < 25; i++) {
        receivers.push(another);
      }
      
      await lazywhitelist.premint(receivers, {from:owner}); 
      
      // Mint 25 more
      var otherReceivers = [];
      for (let i = 0; i < 25; i++) {
        otherReceivers.push(another);
      }
      
      await lazywhitelist.premint(otherReceivers, {from:owner}); 

      let finalReceivers = []
      for (let i = 0; i < 20; i++) {
        finalReceivers.push(another);
      }
      await lazywhitelist.premint(finalReceivers, {from:owner}); 
    });

    it('mint', async function () {
      
      const elements = [accounts[0], accounts[1], accounts[2], accounts[3]];
      
      const merkleTree = new MerkleTree(elements, keccak256, { hashLeaves: true, sortPairs: true });

      const root = merkleTree.getHexRoot();

      const leaf = keccak256(elements[0]);

      const proof = merkleTree.getHexProof(leaf);

      // Trying to mint before allowlist is set should throw error
      await truffleAssert.reverts(lazywhitelist.mint(1, proof, {from:accounts[0], value: 100000000000000000}), "Not on allowlist"); 

      // Set allowlist
      await lazywhitelist.setAllowList(root, {from:owner});

      // Try to mint if you are not on allowlist
      await truffleAssert.reverts(lazywhitelist.mint(1, proof, {from:accounts[4], value: 100000000000000000}), "Not on allowlist"); 

      // Try to mint if you are on allowlist
      await lazywhitelist.mint(1, proof, {from:accounts[0], value: 100000000000000000}); 

      // Mint 2 on allowslist
      await lazywhitelist.mint(2, proof, {from:accounts[0], value: 200000000000000000}); 

      // Try to mint without enough money
      await truffleAssert.reverts(lazywhitelist.mint(1, proof, {from:accounts[0], value: 1}), "Not enough ETH"); 

      // Try to mint with too much money
      await truffleAssert.reverts(lazywhitelist.mint(1, proof, {from:accounts[0], value: 200000000000000000}), "Not enough ETH"); 
    });

  });

});